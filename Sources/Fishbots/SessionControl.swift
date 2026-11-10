import Foundation

/// Sessions commanding other sessions through the aquarium (docs/extensions.md, 11): the routes under /control.
/// An orchestrator is just a session that calls them (`fishbots reply | stop | wait`); what a session takes is
/// still its provider's to say, so nothing here types where the card wouldn't. Off until turned on in Preferences.
///
///   POST /control/reply  {"fish": "claude-code:abc", "text": "…"}
///   POST /control/stop   {"fish": "claude-code:abc"}
///   POST /control/wait   {"fish": ["…", "…"], "states": ["done", "waiting", "error"], "timeout": 600}
///
/// `wait` holds the answer until one of the fish is in one of the states, and says which, with its last reply.
/// A fish that was just sent a line doesn't count as it stands (it's still "done" from the turn before): only
/// what it says next does.
final class SessionControl: EventSink {
    let id = "session-control"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "sessionControl") }
    static let routes = ["POST /control/reply", "POST /control/stop", "POST /control/wait"]

    private struct Waiter {
        let id: Int
        let fish: [String]
        let states: Set<String>
        let reply: (Int, Data) -> Void
    }

    private let tank: Tank
    private let can: (Capability, Fish) -> Bool
    private var waiters: [Waiter] = []
    private var next = 1
    /// Fish that were sent a line and haven't changed state since.
    private var sent: Set<String> = []
    private var ticker: Timer?
    /// The last reply is read from the transcript a moment after the turn ends.
    private let settle: TimeInterval = 1.5

    init(tank: Tank, can: @escaping (Capability, Fish) -> Bool) {
        self.tank = tank
        self.can = can
    }

    /// A deferred route of the server: true if the request is one of these (answered through `reply`).
    func handle(_ method: String, _ path: String, _ headers: [String: String], _ body: Data, _ reply: @escaping (Int, Data) -> Void) -> Bool {
        let route = path.split(separator: "?").first.map(String.init) ?? path
        guard route.hasPrefix("/control/") else { return false }
        guard method == "POST" else { reply(404, Self.error("unknown route")); return true }
        guard Self.enabled else { reply(403, Self.error("session control is off: turn it on in Preferences → General")); return true }
        let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
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
        case "/control/wait":
            let asked = (m["states"] as? [String] ?? ["done", "waiting", "error"]).compactMap { State(wire: $0)?.rawValue }
            guard !asked.isEmpty else { reply(400, Self.error("no known state in \"states\"")); return true }
            let states = Set(asked)
            // already there (and not just sent a line)?
            if let f = found.first(where: { !sent.contains($0.id) && states.contains($0.state.rawValue) }) {
                reply(200, Self.snapshot(f)); return true
            }
            let timeout = min(max((m["timeout"] as? NSNumber)?.doubleValue ?? 600, 1), 3600)
            let w = Waiter(id: next, fish: found.map(\.id), states: states, reply: reply)
            next += 1
            waiters.append(w)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(w.id) { _ in Data(#"{"timeout":true}"#.utf8) }
            }
            watch()
        default:
            reply(404, Self.error("unknown route"))
        }
        return true
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
                    me.tank.fish.first { $0.id == fishId && !$0.leaving }.map(Self.snapshot) ?? Self.gone(fishId)
                }
            }
        }
    }

    /// Answers a waiter once; later calls for the same one do nothing.
    private func finish(_ id: Int, _ body: (SessionControl) -> Data) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        let w = waiters.remove(at: i)
        w.reply(200, body(self))
        if waiters.isEmpty { ticker?.invalidate(); ticker = nil }
    }

    /// While someone waits: a fish that left (its session ended) says nothing more, so it's looked for.
    private func watch() {
        guard ticker == nil else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let alive = Set(self.tank.fish.filter { !$0.leaving }.map(\.id))
            for w in self.waiters {
                if let lost = w.fish.first(where: { !alive.contains($0) }) { self.finish(w.id) { _ in Self.gone(lost) } }
            }
            self.sent.formIntersection(alive)
        }
    }

    // MARK: - fish and answers

    /// By its whole id ("source:entity"), or by the start of its entity if only one fish has it.
    private func fish(_ name: String) -> Fish? {
        let all = tank.fish.filter { !$0.decor && !$0.leaving }
        if let f = all.first(where: { $0.id == name }) { return f }
        let like = all.filter { $0.id.dropFirst($0.source.count + 1).hasPrefix(name) }
        return like.count == 1 ? like[0] : nil
    }

    private static func snapshot(_ f: Fish) -> Data {
        var d: [String: Any] = ["fish": f.id, "state": f.state.rawValue, "label": f.label]
        if let t = f.displayTitle { d["title"] = t }
        if let r = f.lastReplyMarkdown ?? f.lastReply { d["reply"] = r }
        if f.state == .waiting, let q = f.asked { d["asked"] = q }
        return (try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    private static func gone(_ id: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["fish": id, "gone": true])) ?? Data()
    }

    private static func error(_ text: String) -> Data {
        (try? JSONSerialization.data(withJSONObject: ["error": text])) ?? Data()
    }
}
