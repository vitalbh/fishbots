import Foundation

/// What the program in a Rex pane says it's doing right now: programs report it to the terminal (OSC 7501) and Rex
/// sends it on as an event. One `rex events -s SESSION --json` stays open for each Rex session that has a fish in it,
/// so nothing is asked again and again; a stream that ends is opened again at the next `follow`.
final class RexStatus {
    /// A pane's report: the line of text while the program is working, nil once it stops (or says nothing).
    var onStatus: ((_ block: String, _ doing: String?) -> Void)?

    private var streams: [String: Process] = [:]        // by Rex session
    private let queue = DispatchQueue(label: "fishbots.rex-status")

    /// Keeps a stream open for each of these Rex sessions, and closes the others.
    func follow(_ sessions: Set<String>, bin: String) {
        for (s, p) in streams where !sessions.contains(s) || !p.isRunning {
            if p.isRunning { p.terminate() }
            streams[s] = nil
        }
        for s in sessions where streams[s] == nil { streams[s] = open(s, bin: bin) }
    }

    func stop() {
        for p in streams.values where p.isRunning { p.terminate() }
        streams = [:]
    }

    private func open(_ session: String, bin: String) -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = ["--autostart=false", "events", "-s", session, "--json"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        var pending = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { h.readabilityHandler = nil; return }       // the stream ended
            self?.queue.async {
                pending.append(d)
                while let nl = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = pending[pending.startIndex..<nl]
                    pending.removeSubrange(pending.startIndex...nl)
                    // cheap filter before decoding: most of what a session says is about its clients
                    guard line.firstRange(of: Data("program_status_".utf8)) != nil, let (block, doing) = Self.report(in: Data(line)) else { continue }
                    DispatchQueue.main.async { self?.onStatus?(block, doing) }
                }
            }
        }
        do { try p.run() } catch { return nil }
        return p
    }

    /// The pane and its line of text in a `program_status_changed` (or `…_removed`) event, if that's what the line
    /// is. Only the pane's own record counts (the one without an id), not a task inside it.
    static func report(in line: Data) -> (block: String, doing: String?)? {
        guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let event = (o["payload"] as? [String: Any])?["event"] as? [String: Any], event["type"] as? String == "block_event",
              let p = event["payload"] as? [String: Any], let block = p["block_id"] as? String,
              let name = p["name"] as? String, let inner = p["payload"] as? [String: Any] else { return nil }
        switch name {
        case "program_status_changed":
            guard (inner["id"] as? String ?? "").isEmpty, let r = inner["record"] as? [String: Any] else { return nil }
            let msg = (r["msg"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (block, r["state"] as? String == "working" && msg?.isEmpty == false ? msg : nil)
        case "program_status_removed":
            return (block, nil)
        default:
            return nil
        }
    }
}
