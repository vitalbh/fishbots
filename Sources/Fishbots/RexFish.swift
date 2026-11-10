import Foundation

/// What Rex's events do in the tank.
///
/// A session that already has a fish (its agent's hooks made it) gets, from its pane: what it says it's doing, its
/// title, and its place again whenever tabs and panes move. Nothing of that is asked again and again any more.
///
/// A program with no hooks at all that reports its status in a Rex pane (OSC 7501: a build, a deploy, a script of
/// yours) becomes a fish by itself, source "rex": busy while it works, waiting when it's blocked on you, done, error;
/// it leaves when the program takes its status back, exits, or the pane closes. `config.json` picks which ones:
/// `{"rex": {"only": ["cargo"], "ignore": ["terraform"]}}`, or `"rex": false` for none.
final class RexFish {
    static let source = "rex"

    private let tank: Tank
    let events = RexEvents()
    /// Sessions whose places are due a fresh look (tabs moved), and when.
    private var layoutDue: [String: DispatchWorkItem] = [:]

    init(tank: Tank) {
        self.tank = tank
        events.onEvent = { [weak self] e in self?.handle(e) }
    }

    /// Starts listening, if there's a `rex` on this Mac.
    func start() {
        guard let bin = Whereabouts.rexBin([:]) else { return }
        events.start(bin: bin)
    }

    // MARK: - which programs become fish (config.json)

    private static var enabled = true
    private static var only: Set<String>?
    private static var ignore: Set<String> = []

    /// Reads `"rex"` from config.json (called with the attention rules).
    static func reload(_ config: [String: Any]) {
        enabled = (config["rex"] as? Bool) ?? true
        let c = config["rex"] as? [String: Any] ?? [:]
        only = (c["only"] as? [String]).map { Set($0.map { $0.lowercased() }) }
        ignore = Set((c["ignore"] as? [String] ?? []).map { $0.lowercased() })
    }

    /// A program that makes its own fish: not an agent the aquarium already knows by its hooks (that would be the
    /// same session twice), and let in by config.json.
    private static func accepts(_ app: String) -> Bool {
        let a = app.lowercased()
        guard enabled, Providers.all[app] == nil, Providers.all[a] == nil, !ignore.contains(a) else { return false }
        return only?.contains(a) ?? true
    }

    // MARK: - events

    private func handle(_ e: RexEvent) {
        switch e {
        case .status(let session, let block, let record):
            // a session with hooks: its pane only adds what it says it's doing
            if tank.fish.contains(where: { !$0.decor && !$0.leaving && $0.source != Self.source && $0.whereabouts["rex_block"] == block }) {
                tank.doing(rexBlock: block, record?.state == "working" ? record?.msg : nil)
                return
            }
            guard let r = record, let app = r.app, Self.accepts(app) else { leave(block); return }
            let state: State
            switch r.state {
            case "working": state = .busy
            case "blocked": state = .waiting
            case "done": state = .done
            case "error": state = .error
            default: state = .idle
            }
            let entity = Self.entity(block)
            tank.upsert(source: Self.source, entity: entity, state: state, label: app)
            guard let f = tank.fish(source: Self.source, entity: entity) else { return }
            Whereabouts.update(f, with: ["term": "rex", "rex_session": session, "rex_block": block])
            if let t = r.title { f.title = t }
            // blocked: its line is the question; otherwise it's what it's doing
            f.asked = state == .waiting ? (r.msg ?? r.kind.map { tr("✋ esperando você") + " (" + $0 + ")" }) : nil
            tank.doing(rexBlock: block, state == .busy ? r.msg : nil)
            if state == .done || state == .error, let m = r.msg { f.lastReply = m }
        case .title(_, let block, let title):
            let clean = Whereabouts.cleanTitle(title)
            guard !clean.isEmpty else { return }
            for f in tank.fish where !f.decor && !f.leaving && f.source != Self.source && f.whereabouts["rex_block"] == block { f.title = clean }
        case .ended(_, let block):
            leave(block)
        case .layout(let session):
            // tabs and panes often change several at a time: one look, a moment later
            layoutDue[session]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.layoutDue[session] = nil
                for f in self.tank.fish where !f.decor && !f.leaving && f.whereabouts["rex_session"] == session { Whereabouts.detail(f) }
            }
            layoutDue[session] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        case .sessionGone(let session):
            for f in tank.fish where f.source == Self.source && f.whereabouts["rex_session"] == session { f.leaving = true }
        }
    }

    /// The program in that pane is gone: its fish leaves.
    private func leave(_ block: String) {
        tank.remove(source: Self.source, entity: Self.entity(block))
    }

    private static func entity(_ block: String) -> String { block.hasPrefix("block:") ? String(block.dropFirst(6)) : block }
}
