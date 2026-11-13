import Foundation
import simd

/// The aquarium's resident assistant: a creature that lives in the tank (a moray in its burrow, a presence of the
/// app's own) and answers for the aquarium. It has no model of its own: a brain (Brains.swift) thinks for it, the
/// agent the person already has, run in the background in a folder of the assistant's own, where its instructions,
/// its notes and its skills are. It sleeps between conversations: nothing runs until someone talks to it.
///
/// What it knows comes with each question (the sessions in the tank, the day's journal); what it remembers is the
/// notes file its brain reads and writes; what it does goes through the `fishbots` command, like any session that
/// leads others. What its brain may not do on its own is asked on the card (AssistantCard.swift).
final class Assistant {
    struct Turn {
        let question: String
        var answer = ""
        /// What it's doing right now (a tool), while it thinks.
        var doing: String?
        var failed = false
        /// The fish its answer talks about (their ids): the card offers a way to each.
        var mentions: [String] = []
    }

    static let source = "fishbots"
    static let entity = "assistant"

    // MARK: - settings (Preferences → Assistant)

    static var on: Bool {
        get { UserDefaults.standard.object(forKey: "assistant") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "assistant") }
    }
    static var brainID: String {
        get { UserDefaults.standard.string(forKey: "assistantBrain") ?? "claude-code" }
        set { UserDefaults.standard.set(newValue, forKey: "assistantBrain") }
    }
    /// The model, by brain. Claude Code answers on its small one unless told otherwise: the wait is what's felt.
    static func model(_ brain: String) -> String {
        UserDefaults.standard.string(forKey: "assistantModel." + brain) ?? (brain == "claude-code" ? "haiku" : "")
    }
    static func setModel(_ brain: String, _ m: String) { UserDefaults.standard.set(m.trimmingCharacters(in: .whitespaces), forKey: "assistantModel." + brain) }
    /// Reads every answer aloud (one asked by voice always is).
    static var speaks: Bool {
        get { UserDefaults.standard.bool(forKey: "assistantSpeaks") }
        set { UserDefaults.standard.set(newValue, forKey: "assistantSpeaks") }
    }
    /// What the person said it may always do: a tool's name, or "Bash:" and the start of a command.
    static var allowed: [String] {
        get { UserDefaults.standard.stringArray(forKey: "assistantAllow") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "assistantAllow") }
    }

    /// Its own folder: instructions (CLAUDE.md, AGENTS.md), notes.md, the skills. Its brain runs here.
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fishbots/assistant")
    }

    // MARK: - state

    private let tank: Tank
    private let journal: Journal
    /// What a fish is asking permission for, if anything (the app's Permissions).
    var pendingPermission: ((Fish) -> String?)?
    /// The account an agent's sessions run on here (SessionControl.account).
    var account: ((String) -> [String: String])?
    var port: () -> UInt16 = { 7777 }
    /// Something to show changed (the card redraws).
    var changed: (() -> Void)?
    /// The creature was clicked.
    var onOpen: (() -> Void)?
    /// Is its card open? (An answer that arrives with the card closed stays on the creature until it's read.)
    var cardOpen: () -> Bool = { false }

    private(set) var turns: [Turn] = []
    private(set) var thinking = false
    private(set) var request: BrainRequest?
    /// The model answering, as the brain reported it.
    private(set) var answeringModel: String?
    private var unread = false
    private var spoken = false
    private var triedFresh = false
    private var lastContextAt: Date?
    private var sleepTimer: Timer?
    /// Is there a brain to think with? (Found out in the background; nil: not yet known.)
    private(set) var hasBrain: Bool?

    init(tank: Tank, journal: Journal) {
        self.tank = tank
        self.journal = journal
    }

    var brain: Brain? { Brains.of(Self.brainID) }

    // MARK: - the conversation kept between runs

    private struct Kept: Codable { var brain: String; var session: String; var day: String }
    private static var today: String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }
    private var kept: Kept? {
        get { UserDefaults.standard.data(forKey: "assistantSession").flatMap { try? JSONDecoder().decode(Kept.self, from: $0) } }
        set { UserDefaults.standard.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: "assistantSession") }
    }
    /// The conversation to go on with: today's, with this brain. A new day starts a new one (the notes carry over).
    var session: String? {
        guard let k = kept, k.brain == Self.brainID, k.day == Self.today else { return nil }
        return k.session
    }

    // MARK: - in the tank

    /// Puts the creature in the tank, or takes it out: it lives there while the assistant is on and has a brain.
    func settle() {
        guard Self.on, let brain else { leave(); return }
        DispatchQueue.global(qos: .utility).async {
            let ok = brain.installed
            DispatchQueue.main.async {
                self.hasBrain = ok
                if ok, Self.on { self.reflect() } else { self.leave() }
                self.changed?()
            }
        }
    }

    private func leave() {
        tank.scene.remove(source: Self.source, id: Self.entity, party: false, tank)
        brain?.sleep()
    }

    /// The creature shows how the assistant is: thinking, wanting an answer, with something unread, or resting.
    private func reflect() {
        guard Self.on, hasBrain == true else { return }
        let state: State = request != nil ? .waiting : thinking ? .busy : turns.last?.failed == true && unread ? .alert : unread ? .done : .ok
        var detail = ""
        if let r = request { detail = tr("quer usar %@", Self.toolName(r.tool)) }
        else if thinking { detail = turns.last?.doing ?? tr("pensando…") }
        else if unread, let a = turns.last?.answer.split(separator: "\n").first { detail = String(a.prefix(70)) }
        // its burrow, the first time: a free stretch of sand right of the middle (the day's first pearls gather on the left)
        // (and again if the scenery ended up over it: another theme, another window size)
        let w = tank.size.x
        /// How far the nearest piece of scenery is from there, up to 80 points (0: right on one).
        func room(_ x: Float) -> Float {
            for m in stride(from: Float(0), through: 80, by: 8) where tank.scenery.blocks(tank, x - m) || tank.scenery.blocks(tank, x + m) { return m }
            return 88
        }
        let now = tank.scene.presence(source: Self.source, id: Self.entity)
        var x: Float?
        if w > 1, now.map({ room($0.pos.x) == 0 }) ?? true {
            // the roomiest gap between the scenery, the nearer to three quarters of the way across the better
            let spots = stride(from: Float(0.16), through: 0.9, by: 0.01).map { u in (u, room(w * u) - abs(u - 0.74) * 20) }
            x = spots.max { $0.1 < $1.1 }?.0
        }
        _ = tank.scene.upsert(tank, source: Self.source, id: Self.entity, kind: "moray", state: state, label: tr("assistente"),
                              detail: detail, link: nil, value: nil, color: nil, x: x)
        tank.scene.presence(source: Self.source, id: Self.entity)?.open = { [weak self] in
            // (called: it comes out to look at who clicked, for as long as a short exchange takes)
            if let self { self.tank.scene.presence(source: Self.source, id: Self.entity)?.outUntil = self.tank.time + 12 }
            self?.onOpen?()
        }
    }

    /// Where the creature is, for the card to point at.
    var place: SIMD2<Float>? { tank.scene.presence(source: Self.source, id: Self.entity).map { tank.scene.hitCenter($0) } }

    /// The card was opened: what was waiting to be read has been.
    func seen() {
        guard unread else { return }
        unread = false
        reflect()
    }

    // MARK: - talking

    /// Asks it something. `spoken`: asked by voice, so the answer is read aloud.
    /// `shown`: what the card shows in the question's place, when it isn't the person asking (the app's own word that
    /// a watched session stopped).
    func ask(_ text: String, spoken: Bool = false, shown: String? = nil) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !thinking, let brain else { return }
        self.spoken = spoken
        triedFresh = false
        turns.append(Turn(question: shown ?? q))
        if turns.count > 30 { turns.removeFirst(turns.count - 30) }
        thinking = true
        unread = false
        sleepTimer?.invalidate()
        reflect()
        changed?()
        send(q, to: brain)
    }

    private func send(_ q: String, to brain: Brain) {
        let context = self.context()
        lastContextAt = Date()
        let resume = session
        // the person's token for the control routes: the assistant acts for them (fishbots spawn, reply, stop…)
        var env = ["FISHBOTS_ROLE": "assistant", "FISHBOTS_TOKEN": ControlTokens.person]
        if port() != 7777 { env["FISHBOTS_PORT"] = String(port()) }
        if let agent = brain.agent, let a = account?(agent) { env.merge(a) { $1 } }
        let id = brain.id, model = Self.model(brain.id)
        DispatchQueue.global(qos: .userInitiated).async {
            Self.prepareFolder()
            // the aquarium's command where its shell finds it, even if the person's PATH doesn't have it
            if let cli = Self.cli { env["PATH"] = (cli as NSString).deletingLastPathComponent + ":" + AgentCLIs.shellPath }
            let setup = BrainSetup(folder: Self.folder, persona: Self.persona(notes: true), model: model, session: resume, environment: env)
            brain.ask(context + "\n\n" + q, setup: setup) { [weak self] e in self?.heard(e, brain: id, question: q, resumed: resume != nil) }
        }
    }

    private func heard(_ e: BrainEvent, brain id: String, question: String, resumed: Bool) {
        guard !turns.isEmpty else { return }
        let i = turns.count - 1
        switch e {
        case .started(let s, let m):
            if let s { kept = Kept(brain: id, session: s, day: Self.today) }
            if let m, !m.isEmpty { answeringModel = m }
        case .text(let t):
            turns[i].answer += t
            turns[i].doing = nil
        case .tool(let name, let what):
            turns[i].doing = Self.toolName(name) + (what.isEmpty ? "" : ": " + String(what.prefix(60)))
            reflect()
        case .permission(let r):
            if r.tool == "AskUserQuestion" { Brains.of(id)?.decide(r, allow: false); return }     // (it asks in plain words)
            if allowedByItself(r) || Self.allowedByRule(r) { Brains.of(id)?.decide(r, allow: true); return }
            request = r
            reflect()
        case .done(let whole):
            if let whole, turns[i].answer.isEmpty { turns[i].answer = whole }
            finish(i)
        case .failed(let why):
            // a conversation that can't be resumed (another account, cleaned up): once more, from a new one
            if resumed, !triedFresh, turns[i].answer.isEmpty, let brain = Brains.of(id) {
                triedFresh = true
                kept = nil
                brain.sleep()
                send(question, to: brain)
                return
            }
            turns[i].failed = true
            turns[i].answer += (turns[i].answer.isEmpty ? "" : "\n\n") + why
            finish(i)
        }
        changed?()
    }

    private func finish(_ i: Int) {
        thinking = false
        request = nil
        turns[i].doing = nil
        turns[i].answer = turns[i].answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !turns[i].failed { point(i) }
        unread = !cardOpen()
        reflect()
        if !turns[i].failed, spoken || Self.speaks, !turns[i].answer.isEmpty {
            Speaker.shared.speak(ClaudeCodeHook.stripMarkdown(turns[i].answer))
        }
        // asleep after a while without talk: the process goes, the conversation is resumed when it's needed
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in self?.brain?.sleep() }
        // a watched session stopped while it was answering: now it's told
        if !toTell.isEmpty { let next = toTell.removeFirst(); ask(next.text, shown: next.shown) }
    }

    // MARK: - telling on its own

    /// The sessions it was asked to watch (`fishbots watch`): fish id → what the person wants to know when it stops.
    private var watches: [String: String] = [:]
    private var toTell: [(shown: String, text: String)] = []
    /// A fish by its id or the start of it (SessionControl's way).
    var findFish: ((String) -> Fish?)?

    private static func answer(_ o: [String: Any], _ code: Int = 200) -> (Int, Data) {
        (code, (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data())
    }

    /// POST /assistant/watch {"fish": …, "note": …}: the assistant wants to be woken when that session stops working
    /// (finishes, asks something, breaks), to tell the person without being asked again.
    func watch(_ body: Data) -> (Int, Data) {
        guard let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let name = m["fish"] as? String else {
            return Self.answer(["error": #"send {"fish": "…", "note": "what the person wants to know"}"#], 400)
        }
        guard Self.on, hasBrain == true else { return Self.answer(["error": "the assistant is off"], 409) }
        guard let f = findFish?(name) else { return Self.answer(["error": "no fish like \"\(name)\" (or more than one): see `fishbots show`"], 404) }
        // not working right now: there's nothing to wait for, what it says is already there
        guard f.state == .busy || f.state == .born else {
            var o: [String: Any] = ["watching": false, "fish": f.id, "state": f.state.rawValue, "note": "it isn't working now: this is how it stands"]
            if let q = f.asked, f.state == .waiting { o["asks"] = q }
            if let r = f.lastReply { o["last_reply"] = String(r.suffix(3000)) }
            return Self.answer(o)
        }
        watches[f.id] = m["note"] as? String ?? ""
        return Self.answer(["watching": true, "fish": f.id, "state": f.state.rawValue,
                            "note": "you will get a message from the app when it stops; end your answer now and tell the person you'll let them know"])
    }

    /// A watched session stopped: the assistant is told, and tells the person (the moray comes out with the answer).
    private func tell(_ id: String, _ note: String) {
        guard Self.on, hasBrain == true else { return }
        let f = tank.fish.first { $0.id == id && !$0.leaving }
        let name = f.map { $0.nickname ?? $0.displayTitle ?? $0.label } ?? id
        var lines = ["[This message is from the aquarium app, not from the person.] The session you were watching, fish \(id) (\(name)), stopped working."]
        if let f {
            lines.append("It is now: \(f.state.rawValue).")
            if let p = pendingPermission?(f) { lines.append("It wants permission for: \(Self.clip(p, 300))") }
            else if f.state == .waiting, let q = f.asked, !q.isEmpty { lines.append("It asks: \(Self.clip(q, 600))") }
            if let r = f.lastReply, !r.isEmpty { lines.append("Its last reply:\n" + String(r.suffix(3000))) }
        } else {
            lines.append("Its session ended and its fish left the tank.")
        }
        if !note.isEmpty { lines.append("What the person wanted from it: \(note)") }
        lines.append("Tell the person now, briefly: what they wanted to know, or what it needs from them.")
        let shown = "🔔 " + tr("%@ parou", name)
        if thinking { toTell.append((shown, lines.joined(separator: "\n"))) } else { ask(lines.joined(separator: "\n"), shown: shown) }
        if !cardOpen() { tank.notice = (tr("o assistente tem um recado"), tank.time) }
    }

    /// What the tank says (the assistant is one of its outputs, `AssistantEars`): a watched session that stopped.
    func heardFromTank(_ e: TankEvent) {
        let fish = e.source + ":" + e.entity
        guard let note = watches[fish] else { return }
        let stopped = e.type == "permission" || (e.type == "state" && [State.done, .waiting, .error, .idle].map(\.rawValue).contains(e.state))
        guard stopped else { return }
        watches[fish] = nil
        // a moment later, so the session's last reply has been read
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.tell(fish, note) }
    }

    /// The fish the answer talks about light up, and the card gets a way to each.
    private func point(_ i: Int) {
        let text = turns[i].answer.lowercased()
        var found: [String] = []
        for f in tank.fish where f.isAgent && !f.decor && !f.leaving {
            let names = [f.displayTitle, f.nickname, f.label].compactMap { $0?.lowercased() }.filter { $0.count >= 4 }
            guard names.contains(where: text.contains) else { continue }
            found.append(f.id)
            f.glow = 1
            tank.ring(at: f.pos, color: f.color, size: f.size * 0.5, grow: 120, life: 0.9)
        }
        turns[i].mentions = Array(found.prefix(4))
    }

    /// Stops what it's doing.
    func stop() {
        guard thinking else { return }
        if let r = request { brain?.decide(r, allow: false); request = nil }
        brain?.interrupt()
    }

    /// The person's answer to what it wants to use. `always`: from now on, without asking.
    func decide(allow: Bool, always: String? = nil) {
        guard let r = request else { return }
        if allow, let k = always, Self.ruleKeys(r).contains(k), !Self.allowed.contains(k) { Self.allowed.append(k) }
        request = nil
        brain?.decide(r, allow: allow)
        reflect()
        changed?()
    }

    /// Forgets the conversation (not the notes): the next question starts another.
    func newConversation() {
        stop()
        brain?.sleep()
        kept = nil
        turns = []
        thinking = false
        request = nil
        unread = false
        lastContextAt = nil
        reflect()
        changed?()
    }

    /// The brain or its settings changed: whatever runs is let go, and the creature comes or goes.
    func settingsChanged() {
        for b in Brains.all { b.sleep() }
        thinking = false
        request = nil
        settle()
    }

    /// The conversation goes on in a terminal, where the person can see everything and take over (where a launcher
    /// can open one: Rex, Herdr, tmux). What went wrong, or nil.
    func openInTerminal(done: @escaping (String?) -> Void) {
        guard let brain, let s = session, let command = brain.terminalCommand(session: s) else { done(tr("ainda não há conversa para abrir")); return }
        guard let launcher = Launchers.terminal else { done(tr("nenhum terminal onde abrir (Rex, Herdr ou tmux)")); return }
        stop()
        brain.sleep()
        var env: [String: String] = [:]
        if let agent = brain.agent {
            env = account?(agent) ?? [:]
            env.merge(AgentCLIs.environment(agent)) { $1 }
        }
        if port() != 7777 { env["FISHBOTS_PORT"] = String(port()) }
        let r = LaunchRequest(command: command, cwd: Self.folder.path, label: tr("assistente"), near: nil, tab: true, siblings: [], own: true, env: env)
        launcher.launch(r) { result in
            if case .failure(let e) = result { done(e.message) } else { done(nil) }
        }
    }

    var canOpenInTerminal: Bool { session != nil && brain?.terminalCommand(session: "x") != nil && Launchers.terminal != nil }

    // MARK: - what it may do

    static func toolName(_ t: String) -> String {
        // "mcp__claude_ai_Gmail__search_threads" → "Gmail: search_threads"
        guard t.hasPrefix("mcp__") else { return t }
        let parts = t.dropFirst(5).components(separatedBy: "__")
        let server = (parts.first ?? "").replacingOccurrences(of: "claude_ai_", with: "").replacingOccurrences(of: "_", with: " ")
        return parts.count > 1 ? server + ": " + parts.dropFirst().joined(separator: " ") : server
    }

    /// One plain command, with nothing a shell would take as more than words.
    private static func plainCommand(_ r: BrainRequest) -> String? {
        guard r.tool == "Bash", let c = (r.input["command"] as? String)?.trimmingCharacters(in: .whitespaces), !c.isEmpty,
              c.range(of: "[;&|`$<>()\\n\\\\]", options: .regularExpression) == nil else { return nil }
        return c
    }

    /// What "always" could allow for this request, the narrowest first: for a shell command its first two words
    /// ("Bash:rex send") and then the whole program ("Bash:rex"); for a connector's tool, the tool and then the whole
    /// connector ("mcp__server"); otherwise the tool. Empty: nothing to generalize (a command with pipes,
    /// redirections…), so it's asked each time.
    static func ruleKeys(_ r: BrainRequest) -> [String] {
        if r.tool == "Bash" {
            guard let c = plainCommand(r) else { return [] }
            let words = c.split(separator: " ")
            let program = "Bash:" + words[0]
            return words.count > 1 ? ["Bash:" + words.prefix(2).joined(separator: " "), program] : [program]
        }
        let parts = r.tool.components(separatedBy: "__")
        if r.tool.hasPrefix("mcp__"), parts.count > 2 { return [r.tool, parts.prefix(2).joined(separator: "__")] }
        return [r.tool]
    }

    static func allowedByRule(_ r: BrainRequest) -> Bool { ruleKeys(r).contains(where: allowed.contains) }

    /// A rule, as people read it: "rex send …", "rex (tudo)", "Gmail: search threads", "Gmail (tudo)".
    static func ruleName(_ k: String) -> String {
        if k.hasPrefix("Bash:") {
            let c = String(k.dropFirst(5))
            return c.contains(" ") ? c + " …" : c + " " + tr("(tudo)")
        }
        if k.hasPrefix("mcp__"), k.components(separatedBy: "__").count == 2 { return toolName(k) + " " + tr("(tudo)") }
        return toolName(k)
    }

    /// What needs no asking: its own folder (the notes), and looking at the aquarium.
    private func allowedByItself(_ r: BrainRequest) -> Bool {
        if ["Read", "Write", "Edit", "MultiEdit", "NotebookEdit"].contains(r.tool), let p = r.input["file_path"] as? String {
            let path = URL(fileURLWithPath: p).resolvingSymlinksInPath().standardizedFileURL.path
            let home = Self.folder.resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(home + "/") && !path.hasPrefix(home + "/.claude/")
        }
        if let c = Self.plainCommand(r) {
            return c.range(of: #"^fishbots (show|journal|wait|watch)( .*)?$"#, options: .regularExpression) != nil
        }
        return false
    }

    /// Is this hook event from the assistant's own brain? It runs in the assistant's folder and nothing else does,
    /// so the aquarium doesn't take it for a session (it's the resident, not one more fish).
    static func owns(_ body: Data) -> Bool {
        // (a quick look before parsing: every hook event of every session passes here)
        guard body.range(of: Data("Fishbots".utf8)) != nil,
              let o = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let cwd = o["cwd"] as? String else { return false }
        let here = URL(fileURLWithPath: cwd).resolvingSymlinksInPath().standardizedFileURL.path
        let home = folder.resolvingSymlinksInPath().standardizedFileURL.path
        return here == home || here.hasPrefix(home + "/")
    }

    // MARK: - what it knows

    /// Questions worth a click right now, from what's in the tank.
    var suggestions: [String] {
        let fish = tank.fish.filter { $0.isAgent && !$0.decor && !$0.leaving }
        var out: [String] = []
        let waiting = fish.filter { $0.state == .waiting }.count
        if waiting > 0 { out.append(tr("Quem está me esperando?")) }
        if fish.contains(where: { $0.state == .error }) { out.append(tr("O que deu errado?")) }
        let midnight = Calendar.current.startOfDay(for: Date())
        if !journal.between(midnight, Date()).isEmpty { out.append(tr("O que aconteceu hoje?")) }
        if fish.contains(where: { $0.state == .busy }) { out.append(tr("O que cada um está fazendo?")) }
        return Array(out.prefix(3))
    }

    private static func clip(_ s: String, _ n: Int) -> String {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        return t.count > n ? String(t.prefix(n)) + "…" : t
    }

    /// The aquarium right now and what happened in it, as the brain reads it in front of each question: the first
    /// time the whole day, afterwards what's new since the last one.
    func context() -> String {
        let hour = DateFormatter(); hour.dateFormat = "HH:mm"
        let day = DateFormatter(); day.dateFormat = "EEEE, yyyy-MM-dd HH:mm"; day.locale = Locale(identifier: "en_US")
        let language = L10n.isPortuguese ? "Brazilian Portuguese" : "English"
        var lines = ["<aquarium at=\"\(day.string(from: Date()))\" app-language=\"\(language)\">"]
        func age(_ f: Fish) -> String { Journal.duration(max(0, tank.time - f.since)) }
        let fish = tank.fish.filter { !$0.decor && !$0.leaving }
        let sessions = fish.filter(\.isAgent)
        func rank(_ f: Fish) -> Int { f.state == .waiting ? 0 : f.state == .error ? 1 : f.state == .busy ? 2 : 3 }
        lines.append(sessions.isEmpty ? "sessions: none in the tank" : "sessions (\(sessions.count)):")
        for f in sessions.sorted(by: { (rank($0), $0.since) < (rank($1), $1.since) }) {
            var parts = ["- fish \(f.id)", "project \(f.label)"]
            if let t = f.displayTitle, !t.isEmpty { parts.append("title \"\(Self.clip(t, 80))\"") }
            parts.append("\(f.state.rawValue) for \(age(f))")
            if let b = f.branch, !b.isEmpty { parts.append("branch \(b)") }
            if let cwd = f.whereabouts["cwd"] { parts.append("in \((cwd as NSString).abbreviatingWithTildeInPath)") }
            if let p = f.whereabouts["parent"] { parts.append("launched by \(p)") }
            if let c = f.context, c >= 0 { parts.append("context \(Int(c * 100))%") }
            if f.state == .busy, let d = f.doing, !d.isEmpty { parts.append("doing: \(Self.clip(d, 80))") }
            if let p = pendingPermission?(f) { parts.append("wants permission for: \(Self.clip(p, 160))") }
            else if f.state == .waiting, let q = f.asked, !q.isEmpty { parts.append("asks: \(Self.clip(q, 300))") }
            else if [.done, .idle, .ok].contains(f.state), let r = f.lastReply, !r.isEmpty { parts.append("its last reply ends: \(Self.clip(String(r.suffix(240)), 240))") }
            let can = (Providers.of(f.source)?.capabilities(f) ?? []).map(\.rawValue).sorted()
            if !can.isEmpty { parts.append("takes: \(can.joined(separator: ", "))") }
            lines.append(parts.joined(separator: " · "))
        }
        let others = fish.filter { !$0.isAgent && [.waiting, .alert, .error].contains($0.state) }
        let presences = tank.scene.presences.filter { !$0.leaving && $0.needsYou && $0.source != Self.source }
        if !others.isEmpty || !presences.isEmpty {
            lines.append("other things asking for attention:")
            for f in others { lines.append("- \(f.source) \(f.label): \(f.state.rawValue)" + (f.sub.map { " (\(Self.clip($0, 80)))" } ?? "")) }
            for p in presences { lines.append("- \(p.source) \(p.label): \(p.state.rawValue)" + (p.detail.map { " (\(Self.clip($0, 80)))" } ?? "")) }
        }
        let since = lastContextAt ?? Calendar.current.startOfDay(for: Date())
        let news = journal.between(since, Date()).suffix(60)
        if lastContextAt == nil { lines.append(news.isEmpty ? "today so far: nothing recorded" : "today so far:") }
        else if !news.isEmpty { lines.append("since your last answer:") }
        let words: [Happening.Kind: String] = [.done: "finished", .error: "error", .waiting: "waited for the person", .merge: "PR merged", .event: "event"]
        for h in news { lines.append("- \(hour.string(from: h.when)) \(words[h.kind] ?? "") \(Self.clip(h.label, 80))") }
        lines.append("</aquarium>")
        return lines.joined(separator: "\n")
    }

    // MARK: - its folder

    private static let managed = "<!-- fishbots:managed 1 (the app rewrites this file while this line is here; delete the line to keep your own) -->"

    /// Its instructions. `notes`: with the notes file inside (for a brain that doesn't read the folder itself).
    static func persona(notes: Bool) -> String {
        var s = """
        # The aquarium's resident assistant

        You are the resident assistant of Fishbots, an aquarium app on this Mac where every coding-agent session is a fish. The person talks to you through a small card over the water, typing or speaking; your answer is shown there and may be read aloud.

        - Answer in the language the person writes or speaks to you in; when that isn't clear (a word or two, a name, something you say on your own), use the app's language, given as `app-language` in the `<aquarium>` block. Be brief: a sentence or a few short lines, plain words. No tables or headings; no code blocks unless asked for code.
        - Every message starts with an `<aquarium>` block: the sessions in the tank right now and what happened today. It comes from the app, not from the person: use it to answer, don't recite it and don't mention the block.
        - Name a session by its title or its project, as written in the block: the app lights up the fish you name.
        - `notes.md` in this folder is your memory between conversations. Keep it short and current: write there what the person asks you to remember and lasting preferences you learn; remove what stopped being true.
        - To act on sessions use the `fishbots` command (the fishbots-orchestrator skill explains it): `fishbots show`, `fishbots reply <fish> "<text>"`, `fishbots stop <fish>`, `fishbots spawn --cwd <folder> "<task>"`, `fishbots wait <fish>`, `fishbots close <fish>`. Say what you are about to do, and ask first before anything that can't be undone (stopping work, closing a session). For work bigger than a question, start a session for it with `fishbots spawn` instead of doing it yourself here; for work to split across several, tell that session to use the fishbots-orchestrator skill.
        - You can tell the person things later without being asked again. When they want to know when a session finishes, or what it answers ("me avise quando terminar", "tell me what it finds"), run `fishbots watch <fish> "<what they want to know>"`, say you'll let them know, and end your answer. When that session stops, the app sends you a message with its reply and you tell the person then: the creature you are in the tank comes out of its burrow with your answer. Never say you can only answer when written to. If `watch` answers that the session isn't working now, it already stopped: what it says is in that answer, so tell the person right away.
        - If the usual way to do something fails, say what failed and stop: don't work around it with other tools unless the person asks you to.
        - You run in your own folder, not in the person's projects: look into a project only when asked.
        - If you need to ask the person something, ask in plain words in your answer.
        """
        if notes, let n = try? String(contentsOf: folder.appendingPathComponent("notes.md"), encoding: .utf8), !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            s += "\n\n## Your notes (notes.md)\n\n" + n
        }
        return s
    }

    /// The aquarium's command line (`fishbots`): in the shell's PATH, inside the app, or next to where the app was
    /// built (bin/ in the repository). Asks the shell the first time: not on the main thread.
    static let cli: String? = {
        let fm = FileManager.default
        if let p = AgentCLIs.shellPath.split(separator: ":").map({ String($0) + "/fishbots" }).first(where: fm.isExecutableFile) { return p }
        if let p = Bundle.main.resourceURL?.appendingPathComponent("bin/fishbots").path, fm.isExecutableFile(atPath: p) { return p }
        var dir = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<6 {
            let p = dir.appendingPathComponent("bin/fishbots").path
            if fm.isExecutableFile(atPath: p) { return p }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }()

    /// Makes the folder what the brains expect: instructions for Claude Code (CLAUDE.md, with the notes imported) and
    /// for Codex (AGENTS.md), an empty notes file, and the aquarium's skills. Run before each turn, off the main
    /// thread; files the person made their own are left alone.
    static func prepareFolder() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ name: String, _ text: String) {
            let u = folder.appendingPathComponent(name)
            if let old = try? String(contentsOf: u, encoding: .utf8) {
                guard old.contains("fishbots:managed"), old != text else { return }
            }
            try? text.write(to: u, atomically: true, encoding: .utf8)
        }
        let base = managed + "\n" + persona(notes: false)
        write("CLAUDE.md", base + "\n\n@notes.md\n")
        write("AGENTS.md", base + "\n- Read `notes.md` before you answer.\n")
        let notes = folder.appendingPathComponent("notes.md")
        if !fm.fileExists(atPath: notes.path) { try? "".write(to: notes, atomically: true, encoding: .utf8) }
        // the skills, through the aquarium's own command (once; `fishbots skill install` in this folder refreshes them)
        let skills = folder.appendingPathComponent(".claude/skills")
        if !fm.fileExists(atPath: skills.appendingPathComponent("fishbots-orchestrator").path), let cli {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: cli)
            p.arguments = ["skill", "install", skills.path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil { p.waitUntilExit() }
        }
    }
}

/// The assistant as one of the tank's outputs (Outputs.swift): it hears when the sessions it watches stop.
final class AssistantEars: EventSink {
    let id = "assistant"
    private weak var assistant: Assistant?
    init(_ a: Assistant) { assistant = a }
    func send(_ e: TankEvent) { assistant?.heardFromTank(e) }
}
