import Foundation

/// What a program last said about itself to its terminal (the Program Status Protocol, OSC 7501). Rex and Herdr
/// both pass it on, word for word.
struct ProgramStatus {
    /// idle, working, done, blocked (waiting for you) or error.
    var state: String
    /// The program's name, as it gave it ("claude-code", "cargo"…).
    var app: String?
    /// One line about what it's doing, and a short label for it.
    var msg: String?
    var title: String?
    /// What a blocked program waits for: permission, question or auth.
    var kind: String?

    /// From a record as Rex or Herdr give it.
    init?(_ r: [String: Any]) {
        guard let state = r["state"] as? String else { return nil }
        func text(_ k: String) -> String? {
            (r[k] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        self.state = state
        app = text("effective_app") ?? text("app")
        msg = text("msg")
        title = text("title")
        kind = text("kind")
    }
}

/// What a terminal's own reports do in the tank, whichever multiplexer passes them on (RexFish, HerdrFish).
///
/// A session that already has a fish (its agent's hooks made it) gets, from its terminal, what it says it's doing
/// and its title. A program with no hooks at all that reports its status (a build, a deploy, a script of yours)
/// becomes a fish by itself, named after the program: busy while it works, waiting when it's blocked on you, done,
/// error; it leaves when the program takes its status back, exits, or the terminal closes.
/// `config.json` picks which ones, per multiplexer: `{"rex": {"only": ["cargo"], "ignore": ["terraform"]}}`, or
/// `"herdr": false` for none.
final class TerminalPrograms {
    /// A terminal: the multiplexer it's in (the source of a program's own fish), the whereabouts key that names it
    /// there and its id, and the whereabouts a fish in it carries (so a click goes to it).
    struct Place {
        let source: String
        let key: String
        let id: String
        let whereabouts: [String: String]
    }

    private let tank: Tank
    init(tank: Tank) { self.tank = tank }

    /// Terminals whose program said it stopped working, and when (see `rested`).
    private var resting: [String: Date] = [:]

    // MARK: - which programs become fish (config.json)

    private struct Rule { var enabled = true; var only: Set<String>?; var ignore: Set<String> = [] }
    private static var rules: [String: Rule] = [:]

    /// Reads `"rex"` and `"herdr"` from config.json (called with the attention rules).
    static func reload(_ config: [String: Any]) {
        rules = [:]
        for source in ["rex", "herdr"] {
            var r = Rule()
            r.enabled = (config[source] as? Bool) ?? true
            let c = config[source] as? [String: Any] ?? [:]
            r.only = (c["only"] as? [String]).map { Set($0.map { $0.lowercased() }) }
            r.ignore = Set((c["ignore"] as? [String] ?? []).map { $0.lowercased() })
            rules[source] = r
        }
    }

    /// A program that makes its own fish: not an agent the aquarium already knows by its hooks (that would be the
    /// same session twice), not a shell, and let in by config.json.
    private static func accepts(_ app: String, in source: String) -> Bool {
        let a = app.lowercased(), r = rules[source] ?? Rule()
        guard r.enabled, Providers.all[app] == nil, Providers.all[a] == nil, !r.ignore.contains(a) else { return false }
        return r.only?.contains(a) ?? true
    }

    // MARK: - what a terminal said

    private func hooked(_ at: Place) -> [Fish] {
        tank.fish.filter { !$0.decor && !$0.leaving && $0.source != at.source && $0.whereabouts[at.key] == at.id }
    }

    /// The terminal's program reported its status (nil: it took it back, or stopped saying).
    func status(_ at: Place, _ record: ProgramStatus?) {
        // a session with hooks: its terminal only adds what it says it's doing
        if !hooked(at).isEmpty {
            tank.doing(at: at.key, at.id, record?.state == "working" ? record?.msg : nil)
            rested(at, record)
            return
        }
        guard let r = record, let app = r.app, Self.accepts(app, in: at.source) else { ended(at); return }
        let state: State
        switch r.state {
        case "working": state = .busy
        case "blocked": state = .waiting
        case "done": state = .done
        case "error": state = .error
        default: state = .idle
        }
        tank.upsert(source: at.source, entity: at.id, state: state, label: app)
        guard let f = tank.fish(source: at.source, entity: at.id) else { return }
        Whereabouts.update(f, with: at.whereabouts)
        if let t = r.title { f.title = t }
        // blocked: its line is the question; otherwise it's what it's doing
        f.asked = state == .waiting ? (r.msg ?? r.kind.map { tr("✋ esperando você") + " (" + $0 + ")" }) : nil
        tank.doing(at: at.key, at.id, state == .busy ? r.msg : nil)
        if state == .done || state == .error, let m = r.msg { f.lastReply = m }
    }

    /// A session interrupted with Esc has no hook to say so: its fish would stay busy for good. Its terminal knows,
    /// though (the program says it's idle). When a turn ends by itself the hook says so right after, so the terminal
    /// is only believed if the fish is still busy a moment later.
    private func rested(_ at: Place, _ record: ProgramStatus?) {
        let key = at.key + ":" + at.id
        guard let r = record, r.state == "idle" || r.state == "done" else { resting[key] = nil; return }
        let said = Date()
        resting[key] = said
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.resting[key] == said else { return }
            self.resting[key] = nil
            for f in self.hooked(at) where f.state == .busy && f.compactingSince == nil {
                self.tank.upsert(source: f.source, entity: String(f.id.dropFirst(f.source.count + 1)), state: .idle, label: nil)
            }
        }
    }

    /// A session told to stop (Esc) in a terminal that doesn't say when its program goes idle (tmux, iTerm,
    /// Ghostty…): nothing would ever say it stopped, so its fish would stay busy for good, refusing replies and
    /// keeping `fishbots wait` waiting. If nothing more is heard from it a moment after the Esc, it's idle.
    static func interrupted(_ f: Fish, in tank: Tank, tries: Int = 3) {
        guard f.state == .busy, f.whereabouts["rex_block"] == nil, f.whereabouts["herdr"] == nil, Background.of(f) == nil else { return }
        let heard = f.seen
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak f, weak tank] in
            guard let f, let tank, !f.leaving, f.state == .busy, f.compactingSince == nil else { return }
            // it said something after the Esc (the end of a tool it was running): look again a moment later
            guard f.seen == heard else { if tries > 1 { interrupted(f, in: tank, tries: tries - 1) }; return }
            tank.upsert(source: f.source, entity: String(f.id.dropFirst(f.source.count + 1)), state: .idle, label: nil)
        }
    }

    /// The terminal's title changed: the conversation's title, for a session with hooks.
    func title(_ at: Place, _ title: String) {
        let clean = Whereabouts.cleanTitle(title)
        guard !clean.isEmpty else { return }
        for f in hooked(at) { f.title = clean }
    }

    /// The program exited or the terminal closed: a program's own fish leaves (a session's is its hooks' business).
    func ended(_ at: Place) {
        tank.remove(source: at.source, entity: at.id)
    }

    /// Everything of this multiplexer's whose whereabouts say so is gone (a Rex session destroyed).
    func gone(source: String, key: String, _ value: String) {
        for f in tank.fish where f.source == source && f.whereabouts[key] == value { f.leaving = true }
    }
}
