import Foundation

/// Rex's events in the tank: what each pane's program reports (TerminalPrograms), each pane's title, and where
/// things are again whenever tabs and panes move. Nothing of that is asked again and again any more.
final class RexFish {
    static let source = "rex"

    private let tank: Tank
    private let programs: TerminalPrograms
    let events = RexEvents()
    /// Sessions whose places are due a fresh look (tabs moved).
    private var layoutDue: [String: DispatchWorkItem] = [:]

    init(tank: Tank, programs: TerminalPrograms) {
        self.tank = tank
        self.programs = programs
        events.onEvent = { [weak self] e in self?.handle(e) }
    }

    /// Starts listening, if there's a `rex` on this Mac.
    func start() {
        guard let bin = Whereabouts.rexBin([:]) else { return }
        events.start(bin: bin)
    }

    private func place(_ session: String, _ block: String) -> TerminalPrograms.Place {
        .init(source: Self.source, key: "rex_block", id: block, whereabouts: ["term": "rex", "rex_session": session, "rex_block": block])
    }

    private func handle(_ e: RexEvent) {
        switch e {
        case .status(let session, let block, let record): programs.status(place(session, block), record)
        case .title(let session, let block, let title): programs.title(place(session, block), title)
        case .ended(let session, let block): programs.ended(place(session, block))
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
            programs.gone(source: Self.source, key: "rex_session", session)
        }
    }
}
