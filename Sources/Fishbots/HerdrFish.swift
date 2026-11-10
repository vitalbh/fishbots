import Foundation

/// Herdr's events in the tank, the same way as Rex's: `herdr-core events --json` starts with every terminal as it
/// is, then says each change as it happens (status, title, labels, finished, removed…). What a terminal's program
/// reports goes to TerminalPrograms; a terminal's title and its place ("space › tab") reach the fish in it directly,
/// so Herdr isn't asked again and again either.
final class HerdrFish {
    static let source = "herdr"

    private let tank: Tank
    private let programs: TerminalPrograms
    private var stream: Process?
    private let queue = DispatchQueue(label: "fishbots.herdr-events")
    private var checking = false

    init(tank: Tank, programs: TerminalPrograms) {
        self.tank = tank
        self.programs = programs
    }

    var listening: Bool { stream?.isRunning == true }

    /// Opens the stream if it isn't open and Herdr's core is running (it's never started from here).
    func check() {
        guard !listening, !checking, let core = Whereabouts.herdrCorePath else { return }
        checking = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let running = Whereabouts.json(Whereabouts.run(core, ["server", "status", "--json"]))?["core"] != nil
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                if running, !self.listening { self.open(core) }
            }
        }
    }

    func stop() {
        if stream?.isRunning == true { stream?.terminate() }
        stream = nil
    }

    private func open(_ core: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: core)
        p.arguments = ["events", "--json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        var pending = Data()
        let queue = self.queue
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { h.readabilityHandler = nil; return }       // the stream ended
            queue.async {
                pending.append(d)
                while let nl = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = Data(pending[pending.startIndex..<nl])
                    pending.removeSubrange(pending.startIndex...nl)
                    guard line.firstRange(of: Data("\"heartbeat\"".utf8)) == nil,
                          let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
                    DispatchQueue.main.async { self?.handle(o) }
                }
            }
        }
        do { try p.run(); stream = p } catch { stream = nil }
    }

    private func place(_ terminal: String) -> TerminalPrograms.Place {
        .init(source: Self.source, key: "herdr", id: terminal, whereabouts: ["term": "herdr", "herdr": terminal])
    }

    private func handle(_ o: [String: Any]) {
        // the first line (and again after falling behind): every terminal as it is
        if let all = o["terminals"] as? [[String: Any]] {
            for t in all where t["state"] as? String == "live" {
                guard let address = t["address"] as? String else { continue }
                if let s = t["status"] as? [String: Any] { programs.status(place(address), ProgramStatus(s)) }
                if let title = t["title"] as? String { programs.title(place(address), title) }
                located(address, t["labels"])
            }
            return
        }
        guard o["method"] as? String == "event", let p = o["params"] as? [String: Any],
              let terminal = p["terminal"] as? String, let type = p["type"] as? String else { return }
        let data = p["data"] as? [String: Any] ?? [:]
        switch type {
        case "status":
            programs.status(place(terminal), (data["status"] as? [String: Any]).flatMap { ProgramStatus($0) })
        case "title":
            if let t = data["title"] as? String { programs.title(place(terminal), t) }
        case "labels", "created":
            located(terminal, data["labels"])
        case "finished", "removed", "lost":
            programs.ended(place(terminal))
        default:
            break
        }
    }

    /// Where the terminal is ("space / tab", in its labels): the second line of the fish in it.
    private func located(_ terminal: String, _ labels: Any?) {
        guard let place = (labels as? [String: Any])?["where"] as? String, !place.isEmpty else { return }
        for f in tank.fish where !f.decor && !f.leaving && f.whereabouts["herdr"] == terminal {
            f.sub = "Herdr · " + place.replacingOccurrences(of: " / ", with: " › ")
        }
    }
}
