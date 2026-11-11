import Foundation

/// Sessions commanding other sessions through the aquarium (docs/extensions.md, 11): the routes under /control.
/// An orchestrator is just a session that calls them (`fishbots spawn | reply | stop | wait`); what a session takes
/// is still its provider's to say, so nothing here types where the card wouldn't. Off until turned on in Preferences.
///
///   POST /control/spawn  {"agent": "claude-code", "cwd": "/…", "prompt": "…", "label": "…", "model": "…", "launcher": "rex",
///                         "tab": true, "env": {"CLAUDE_CONFIG_DIR": "…"}}
///   POST /control/reply  {"fish": "claude-code:abc", "text": "…"}
///   POST /control/stop   {"fish": "claude-code:abc"}
///   POST /control/wait   {"fish": ["…", "…"], "states": ["done", "waiting", "error", "idle"], "timeout": 600}
///
/// `spawn` opens a pane (Launchers.swift) running the agent with the prompt, and holds the answer until the session
/// in it shows up as a fish. The one asking is found by where it runs (the X-Where-* headers `fishbots` sends, the
/// hook's own): the new fish is its child. A child doesn't launch others, and a parent has a limit of them.
/// The new pane doesn't have the asker's environment, so what picks the agent's account or profile comes in `env`
/// (`fishbots spawn` sends CLAUDE_CONFIG_DIR and CODEX_HOME when it has them).
/// `wait` holds the answer until one of the fish is in one of the states (by default, until it stops working:
/// done, waiting for an answer, error, or idle, which is how an interrupted one ends), and says which, with its
/// last reply.
/// A fish that was just sent a line doesn't count as it stands (it's still "done" from the turn before): only
/// what it says next does.
final class SessionControl: EventSink {
    let id = "session-control"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "sessionControl") }
    static let routes = ["POST /control/spawn", "POST /control/reply", "POST /control/stop", "POST /control/wait",
                         "POST /control/close"]
    /// Sessions one parent can have at work at once (the ones that finished and sit at their prompt don't count).
    static let maxChildren = 6

    private struct Waiter {
        let id: Int
        let fish: [String]
        let states: Set<String>
        let reply: (Int, Data) -> Void
    }

    /// A pane that was opened and whose session hasn't shown up yet.
    private struct Birth {
        let id: Int
        let source: String
        let place: [String: String]
        let parent: String?
        let cwd: String
        /// The fish of that agent that were already there: not the one being born.
        let before: Set<String>
        let reply: (Int, Data) -> Void
    }

    private let tank: Tank
    private let port: () -> UInt16
    private let can: (Capability, Fish) -> Bool
    private var waiters: [Waiter] = []
    private var births: [Birth] = []
    private var next = 1
    /// Fish that were sent a line and haven't changed state since.
    private var sent: Set<String> = []
    private var ticker: Timer?
    /// The last reply is read from the transcript a moment after the turn ends.
    private let settle: TimeInterval = 1.5

    init(tank: Tank, port: @escaping () -> UInt16, can: @escaping (Capability, Fish) -> Bool) {
        self.tank = tank
        self.port = port
        self.can = can
    }

    /// A deferred route of the server: true if the request is one of these (answered through `reply`).
    func handle(_ method: String, _ path: String, _ headers: [String: String], _ body: Data, _ reply: @escaping (Int, Data) -> Void) -> Bool {
        let route = path.split(separator: "?").first.map(String.init) ?? path
        guard route.hasPrefix("/control/") else { return false }
        guard method == "POST" else { reply(404, Self.error("unknown route")); return true }
        guard Self.enabled else { reply(403, Self.error("session control is off: turn it on in Preferences → General")); return true }
        let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if route == "/control/spawn" { spawn(m, headers, reply); return true }

        let names = (m["fish"] as? [String]) ?? (m["fish"] as? String).map { [$0] } ?? []
        var found: [Fish] = []
        for n in names {
            guard let f = fish(n) else { reply(404, Self.error("no fish \(n) (or more than one): see GET /state")); return true }
            found.append(f)
        }
        guard !found.isEmpty else { reply(400, Self.error(#"send {"fish": "<source>:<entity>"}"#)); return true }

        switch route {
        case "/control/reply":
            let f = found[0]
            guard let text = m["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                reply(400, Self.error(#"send {"fish": "…", "text": "…"}"#)); return true
            }
            guard can(.reply, f), let provider = Providers.of(f.source) else {
                reply(409, Self.error("\(f.id) can't take a reply now (state: \(f.state.rawValue))")); return true
            }
            sent.insert(f.id)
            provider.reply(f, text) { [weak self, weak f] failure in
                guard let self else { return }
                if let failure {
                    if let f { self.sent.remove(f.id) }
                    reply(409, Self.error(failure))
                    return
                }
                if let f {
                    f.glow = 1
                    f.moment = (tr("↩︎ respondido"), self.tank.time + 4)
                }
                reply(200, Data(#"{"ok":true}"#.utf8))
            }
        case "/control/stop":
            let f = found[0]
            guard can(.stop, f), let provider = Providers.of(f.source) else {
                reply(409, Self.error("\(f.id) has nothing to stop (state: \(f.state.rawValue))")); return true
            }
            provider.stop(f)
            reply(200, Data(#"{"ok":true}"#.utf8))
        case "/control/close":
            // only what the asker itself launched: its pane closes, whatever it's doing, and its fish leaves
            let f = found[0]
            guard let asker = caller(headers), f.whereabouts["parent"] == asker.id else {
                reply(409, Self.error("\(f.id) wasn't launched by the session asking: only its own children can be closed")); return true
            }
            guard let launcher = Launchers.all.first(where: { $0.hosts(f.whereabouts) }) else {
                reply(409, Self.error("\(f.id) isn't in a pane that can be closed")); return true
            }
            launcher.close(f.whereabouts) { [weak self, weak f] failure in
                if let failure { reply(409, Self.error(failure)); return }
                if let f { self?.tank.remove(source: f.source, entity: String(f.id.dropFirst(f.source.count + 1))) }
                reply(200, Data(#"{"ok":true}"#.utf8))
            }
        case "/control/wait":
            let asked = (m["states"] as? [String] ?? ["done", "waiting", "error", "idle"]).compactMap { State(wire: $0)?.rawValue }
            guard !asked.isEmpty else { reply(400, Self.error("no known state in \"states\"")); return true }
            let states = Set(asked)
            // already there (and not just sent a line)?
            if let f = found.first(where: { !sent.contains($0.id) && states.contains($0.state.rawValue) }) {
                reply(200, Self.json(Self.snapshot(f))); return true
            }
            let w = Waiter(id: next, fish: found.map(\.id), states: states, reply: reply)
            next += 1
            waiters.append(w)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.seconds(m["timeout"], or: 600, upTo: 3600)) { [weak self] in
                self?.finish(w.id) { _ in Data(#"{"timeout":true}"#.utf8) }
            }
            watch()
        default:
            reply(404, Self.error("unknown route"))
        }
        return true
    }

    // MARK: - a new session

    /// The account's variables the last session that launched another passed along, by agent: a session opened from
    /// the aquarium's own menu has no shell to take them from, and should run on the same account.
    private static let accountVariables = ["CLAUDE_CONFIG_DIR", "CODEX_HOME"]

    /// The account a session opened from the menu runs on: the one this agent's most recent session here runs on,
    /// read from where its conversation file is kept (<account>/projects/… for Claude Code, <account>/sessions/…
    /// for Codex; the usual folder needs no variable); with none in the tank, what the last spawn passed along.
    private func account(_ agent: String) -> [String: String] {
        let kept: [String: (variable: String, under: String, usual: String)] = [
            "claude-code": ("CLAUDE_CONFIG_DIR", "/projects/", "~/.claude"),
            "codex": ("CODEX_HOME", "/sessions/", "~/.codex"),
        ]
        if let k = kept[agent],
           let path = tank.fish.filter({ $0.source == agent && !$0.decor && $0.transcriptPath != nil }).max(by: { $0.bornAt < $1.bornAt })?.transcriptPath,
           let cut = path.range(of: k.under) {
            let home = String(path[..<cut.lowerBound])
            return home == NSString(string: k.usual).expandingTildeInPath ? [:] : [k.variable: home]
        }
        return (UserDefaults.standard.dictionary(forKey: "launchAccount") as? [String: [String: String]])?[agent] ?? [:]
    }

    /// From the aquarium itself (the "Nova sessão…" menu): a session of the person's own, nobody's child. `done`
    /// gets what went wrong, or nil once its fish is born.
    func open(agent: String, cwd: String, prompt: String?, model: String?, label: String? = nil, done: @escaping (String?) -> Void) {
        var m: [String: Any] = ["agent": agent, "cwd": cwd, "tab": true, "focus": true]
        if let prompt { m["prompt"] = prompt }
        if let model { m["model"] = model }
        m["env"] = account(agent)
        // the host's session it gets is named after its task (or its folder)
        let words = (prompt ?? "").split(whereSeparator: { $0.isWhitespace }).prefix(5).joined(separator: " ")
        m["label"] = label ?? (words.isEmpty ? (cwd as NSString).lastPathComponent : String(words.prefix(32)))
        spawn(m, [:]) { code, data in
            // 504: the pane is open and in front of the person, with whatever the agent asks first; nothing to add
            done(code == 200 || code == 504 ? nil : (Whereabouts.json(data)?["error"] as? String ?? "error \(code)"))
        }
    }

    private func spawn(_ m: [String: Any], _ headers: [String: String], _ reply: @escaping (Int, Data) -> Void) {
        let parent = caller(headers)
        if let parent {
            guard parent.whereabouts["parent"] == nil else {
                reply(409, Self.error("\(parent.id) was launched by another session: it can't launch its own")); return
            }
            guard children(of: parent.id).filter({ ![.done, .idle, .ok].contains($0.state) }).count < Self.maxChildren else {
                reply(409, Self.error("\(parent.id) already has \(Self.maxChildren) sessions at work: wait for one to finish")); return
            }
        }
        let agent = m["agent"] as? String ?? parent?.source ?? "claude-code"
        let prompt = (m["prompt"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let model = (m["model"] as? String).flatMap { $0.range(of: #"^[A-Za-z0-9][A-Za-z0-9._:/\[\]-]*$"#, options: .regularExpression) == nil ? nil : $0 }
        guard let provider = Providers.of(agent), let command = provider.launchCommand(prompt: prompt, model: model) else {
            let known = Providers.all.values.filter { $0.launchCommand(prompt: nil, model: nil) != nil }.map(\.id).sorted().joined(separator: ", ")
            reply(400, Self.error("don't know how to start \"\(agent)\" (can start: \(known))")); return
        }
        guard let folder = (m["cwd"] as? String ?? parent?.whereabouts["cwd"]).map({ NSString(string: $0).expandingTildeInPath }) else {
            reply(400, Self.error(#"send "cwd": the folder the session works in"#)); return
        }
        var isDir: ObjCBool = false
        guard folder.hasPrefix("/"), FileManager.default.fileExists(atPath: folder, isDirectory: &isDir), isDir.boolValue else {
            reply(400, Self.error("\(folder) isn't a folder")); return
        }
        let wanted = m["launcher"] as? String
        guard let launcher = Launchers.pick(wanted, near: parent?.whereabouts) else {
            let known = Launchers.all.map(\.id).joined(separator: ", ")
            reply(409, Self.error(wanted.map { "can't launch through \"\($0)\" (launchers: \(known))" } ?? "nowhere to launch a session (none of \(known) is installed)")); return
        }
        var env: [String: String] = [:]
        for (k, v) in m["env"] as? [String: String] ?? [:] where k.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil {
            env[k] = v
        }
        if parent != nil {
            let account = env.filter { Self.accountVariables.contains($0.key) }
            var known = UserDefaults.standard.dictionary(forKey: "launchAccount") as? [String: [String: String]] ?? [:]
            if !account.isEmpty, known[agent] != account {
                known[agent] = account
                UserDefaults.standard.set(known, forKey: "launchAccount")
            }
        }
        if let parent { env["FISHBOTS_PARENT"] = parent.id }
        // an aquarium on another port (a test instance): the new session's hook reports to this one
        if port() != 7777 { env["FISHBOTS_PORT"] = String(port()) }
        let patience = Self.seconds(m["timeout"], or: 30, upTo: 120)
        let before = Set(tank.fish.filter { $0.source == provider.id }.map(\.id))
        let request = LaunchRequest(command: command, cwd: folder, label: m["label"] as? String, near: parent?.whereabouts,
                                    tab: m["tab"] as? Bool ?? false,
                                    siblings: (parent.map { children(of: $0.id) } ?? []).sorted { $0.bornAt < $1.bornAt }.map(\.whereabouts),
                                    focus: parent == nil && m["focus"] as? Bool == true, env: env)
        launcher.launch(request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let e):
                reply(409, Self.error(e.message))
            case .success(let place):
                let b = Birth(id: self.next, source: provider.id, place: place, parent: parent?.id, cwd: folder, before: before, reply: reply)
                self.next += 1
                self.births.append(b)
                DispatchQueue.main.asyncAfter(deadline: .now() + patience) { [weak self] in
                    self?.deliver(b.id, 504, ["error": "the pane opened, but no \(provider.id) session reported from it in \(Int(patience)) s (is its hook installed? is it asking something first?)",
                                              "where": place])
                }
                self.watch()
            }
        }
    }

    /// The agent session the request came from, by where it runs.
    private func caller(_ headers: [String: String]) -> Fish? {
        for key in Launchers.placeKeys {
            guard let v = headers["x-where-" + key.replacingOccurrences(of: "_", with: "-")] else { continue }
            if let f = tank.fish.first(where: { $0.isAgent && !$0.decor && !$0.leaving && $0.whereabouts[key] == v }) { return f }
        }
        return nil
    }

    private func children(of id: String) -> [Fish] {
        tank.fish.filter { !$0.decor && !$0.leaving && $0.whereabouts["parent"] == id }
    }

    /// The fish that was born in a launched pane, if it's there already: the one whose hook says it runs there.
    /// Some agents' hooks don't run in the terminal at all (Codex's run in its daemon), so they can't say: then it's
    /// the new fish of that agent, in that folder, that came from no terminal, and it's put in the pane.
    private func born(_ b: Birth) -> Fish? {
        guard let key = Launchers.placeKeys.first(where: { b.place[$0] != nil }) else { return nil }
        let its = tank.fish.filter { $0.source == b.source && !$0.leaving }
        if let f = its.first(where: { $0.whereabouts[key] == b.place[key] }) { return f }
        let terminal = Launchers.placeKeys + ["term", "tty", "app", "entrypoint", "iterm", "wezterm", "kitty"]
        let folder = URL(fileURLWithPath: b.cwd).standardizedFileURL.path
        guard let f = its.first(where: { f in
            !b.before.contains(f.id) && terminal.allSatisfy { f.whereabouts[$0] == nil }
                && f.whereabouts["cwd"].map { URL(fileURLWithPath: $0).standardizedFileURL.path } == folder
        }) else { return nil }
        Whereabouts.put(f, in: b.place)
        return f
    }

    private func deliver(_ id: Int, _ status: Int, _ body: [String: Any]) {
        guard let i = births.firstIndex(where: { $0.id == id }) else { return }
        births.remove(at: i).reply(status, Self.json(body))
        rest()
    }

    // MARK: - what the tank says

    func send(_ e: TankEvent) {
        guard e.type == "state" else { return }
        let fishId = e.source + ":" + e.entity
        sent.remove(fishId)
        for w in waiters where w.fish.contains(fishId) && w.states.contains(e.state) {
            let id = w.id
            // the waiter stays in the list meanwhile, so nothing else answers it twice: `finish` takes it out
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [weak self] in
                self?.finish(id) { me in
                    Self.json(me.tank.fish.first { $0.id == fishId && !$0.leaving }.map(Self.snapshot) ?? ["fish": fishId, "gone": true])
                }
            }
        }
    }

    /// Answers a waiter once; later calls for the same one do nothing.
    private func finish(_ id: Int, _ body: (SessionControl) -> Data) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        let w = waiters.remove(at: i)
        w.reply(200, body(self))
        rest()
    }

    /// While someone waits: a new session's fish is looked for, and so is a fish that left (its session ended
    /// and says nothing more).
    private func watch() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            for b in self.births {
                guard let f = self.born(b) else { continue }
                if let p = b.parent, f.whereabouts["parent"] == nil { f.whereabouts["parent"] = p }
                var d = Self.snapshot(f)
                d["where"] = b.place
                if let p = b.parent { d["parent"] = p }
                self.deliver(b.id, 200, d)
            }
            let alive = Set(self.tank.fish.filter { !$0.leaving }.map(\.id))
            for w in self.waiters {
                if let lost = w.fish.first(where: { !alive.contains($0) }) { self.finish(w.id) { _ in Self.json(["fish": lost, "gone": true]) } }
            }
            self.sent.formIntersection(alive)
        }
    }

    private func rest() {
        if waiters.isEmpty && births.isEmpty { ticker?.invalidate(); ticker = nil }
    }

    // MARK: - fish and answers

    /// By its whole id ("source:entity"), or by the start of its entity if only one fish has it.
    private func fish(_ name: String) -> Fish? {
        let all = tank.fish.filter { !$0.decor && !$0.leaving }
        if let f = all.first(where: { $0.id == name }) { return f }
        // the start of the entity, with or without its source in front ("2d265f0e", "claude-code:2d265f0e")
        let like = all.filter { $0.id.dropFirst($0.source.count + 1).hasPrefix(name) || (name.count > $0.source.count + 1 && $0.id.hasPrefix(name)) }
        return like.count == 1 ? like[0] : nil
    }

    private static func seconds(_ v: Any?, or usual: Double, upTo most: Double) -> Double {
        min(max((v as? NSNumber)?.doubleValue ?? usual, 1), most)
    }

    private static func snapshot(_ f: Fish) -> [String: Any] {
        var d: [String: Any] = ["fish": f.id, "state": f.state.rawValue, "label": f.label]
        if let t = f.displayTitle { d["title"] = t }
        if let r = f.lastReplyMarkdown ?? f.lastReply { d["reply"] = r }
        if f.state == .waiting, let q = f.asked { d["asked"] = q }
        return d
    }

    private static func json(_ d: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private static func error(_ text: String) -> Data { json(["error": text]) }
}
