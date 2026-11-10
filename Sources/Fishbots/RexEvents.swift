import Foundation

/// What the program in a Rex pane last said about itself (it reports to the terminal with OSC 7501).
struct RexRecord {
    /// idle, working, done, blocked (waiting for you) or error.
    var state: String
    /// The program's name, as it gave it ("claude-code", "cargo"…).
    var app: String?
    /// One line about what it's doing, and a short label for it.
    var msg: String?
    var title: String?
    /// What a blocked program waits for: permission, question or auth.
    var kind: String?
}

/// Something Rex said happened.
enum RexEvent {
    /// A pane's program reported its status (nil: it took it back, or stopped saying).
    case status(session: String, block: String, RexRecord?)
    /// A pane's title changed.
    case title(session: String, block: String, String)
    /// A pane's program exited, or the pane was closed.
    case ended(session: String, block: String)
    /// Tabs or panes were made, closed, moved or renamed: where things are may read differently now.
    case layout(session: String)
    case sessionGone(String)
}

/// Listens to Rex instead of asking it again and again: `rex events --json` for the sessions that come and go, and
/// one `rex events -s SESSION --json` for each session, where its panes' own events arrive. A stream that ends (the
/// server restarted) is opened again at the next `check`.
final class RexEvents {
    var onEvent: ((RexEvent) -> Void)?

    private var bin: String?
    private var server: Process?
    private var streams: [String: Process] = [:]        // by Rex session
    private let queue = DispatchQueue(label: "fishbots.rex-events")

    /// The sessions being listened to.
    func isFollowing(_ session: String) -> Bool { streams[session]?.isRunning == true }

    func start(bin: String) {
        self.bin = bin
        check()
    }

    /// Opens what isn't open: the server's stream (and, with it, the list of sessions) and each session's.
    func check() {
        guard let bin else { return }
        if server?.isRunning != true {
            server = stream(bin, ["--autostart=false", "events", "--json"]) { [weak self] line in self?.serverLine(line) }
            // the sessions that are already there
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let listed = Whereabouts.json(Whereabouts.run(bin, ["--autostart=false", "--timeout", "3s", "ls", "--json"]))?["sessions"] as? [[String: Any]] ?? []
                let ids = listed.compactMap { $0["session_id"] as? String }
                DispatchQueue.main.async { for id in ids { self?.follow(id) } }
            }
        }
        for (s, p) in streams where !p.isRunning { streams[s] = nil; follow(s) }
    }

    func stop() {
        if server?.isRunning == true { server?.terminate() }
        server = nil
        for p in streams.values where p.isRunning { p.terminate() }
        streams = [:]
    }

    private func follow(_ session: String) {
        guard let bin, streams[session]?.isRunning != true else { return }
        streams[session] = stream(bin, ["--autostart=false", "events", "-s", session, "--json"]) { [weak self] line in
            guard let e = Self.event(in: line) else { return }
            DispatchQueue.main.async { self?.onEvent?(e) }
        }
        // what its panes had already said before this started listening (a program running since before the app
        // opened, or one that reported as its session was being made): asked once, a moment after the stream is open (so nothing falls between the two)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let blocks = Whereabouts.json(Whereabouts.run(bin, ["--autostart=false", "--timeout", "3s", "block", "ls", "-s", session, "--json"]))?["blocks"] as? [[String: Any]] ?? []
            for b in blocks where (b["creator_name"] as? String ?? "").hasSuffix(".terminal") {
                guard let id = b["block_id"] as? String,
                      let records = Whereabouts.json(Whereabouts.run(bin, ["--autostart=false", "--timeout", "3s", "block", "call", "-b", id, "program_status"]))?["records"] as? [[String: Any]],
                      let root = records.first(where: { ($0["id"] as? String ?? "").isEmpty }), let r = Self.record(root) else { continue }
                DispatchQueue.main.async { self?.onEvent?(.status(session: session, block: id, r)) }
            }
        }
    }

    /// A status record as Rex gives it (in an event or in the answer to `program_status`).
    static func record(_ r: [String: Any]) -> RexRecord? {
        guard let state = r["state"] as? String else { return nil }
        func text(_ k: String) -> String? {
            (r[k] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        return RexRecord(state: state, app: text("effective_app") ?? text("app"), msg: text("msg"), title: text("title"), kind: text("kind"))
    }

    private func unfollow(_ session: String) {
        if let p = streams[session], p.isRunning { p.terminate() }
        streams[session] = nil
        onEvent?(.sessionGone(session))
    }

    /// A session was made or destroyed.
    private func serverLine(_ line: Data) {
        guard line.firstRange(of: Data("session_created".utf8)) != nil || line.firstRange(of: Data("session_destroyed".utf8)) != nil,
              let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], let p = o["payload"] as? [String: Any] else { return }
        let type = o["type"] as? String
        let id = (p["session"] as? [String: Any])?["session_id"] as? String ?? p["session_id"] as? String
        guard let id else { return }
        DispatchQueue.main.async { [weak self] in
            if type == "session_created" { self?.follow(id) } else if type == "session_destroyed" { self?.unfollow(id) }
        }
    }

    /// Runs `rex` and hands over each line it writes, on this type's queue.
    private func stream(_ bin: String, _ args: [String], _ each: @escaping (Data) -> Void) -> Process? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        var pending = Data()
        let queue = self.queue
        out.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty else { h.readabilityHandler = nil; return }       // the stream ended
            queue.async {
                pending.append(d)
                while let nl = pending.firstIndex(of: UInt8(ascii: "\n")) {
                    let line = Data(pending[pending.startIndex..<nl])
                    pending.removeSubrange(pending.startIndex...nl)
                    each(line)
                }
            }
        }
        do { try p.run() } catch { return nil }
        return p
    }

    private static let layoutEvents: Set<String> = ["window_created", "window_closed", "window_label_changed", "session_label_changed",
                                                     "session_view_changed", "block_created"]

    /// What a line of a session's stream says, if it's something the aquarium cares about.
    static func event(in line: Data) -> RexEvent? {
        // most of what a session says is about its clients coming and going: not worth decoding
        if line.firstRange(of: Data("\"client_".utf8)) != nil { return nil }
        guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], o["type"] as? String == "session_event",
              let outer = o["payload"] as? [String: Any], let session = outer["session_id"] as? String,
              let event = outer["event"] as? [String: Any], let type = event["type"] as? String else { return nil }
        let p = event["payload"] as? [String: Any] ?? [:]
        if layoutEvents.contains(type) { return .layout(session: session) }
        if type == "block_closed", let b = p["block_id"] as? String { return .ended(session: session, block: b) }
        guard type == "block_event", let block = p["block_id"] as? String, let name = p["name"] as? String else { return nil }
        let inner = p["payload"] as? [String: Any] ?? [:]
        switch name {
        case "program_status_changed":
            // only the pane's own record (the one without an id), not a task inside it
            guard (inner["id"] as? String ?? "").isEmpty, let r = (inner["record"] as? [String: Any]).flatMap(record) else { return nil }
            return .status(session: session, block: block, r)
        case "program_status_removed":
            let ids = inner["ids"] as? [String] ?? [""]
            return ids.contains("") || ids.isEmpty ? .status(session: session, block: block, nil) : nil
        case "title_changed":
            return (inner["title"] as? String).map { .title(session: session, block: block, $0) }
        case "child_exited":
            return .ended(session: session, block: block)
        default:
            return nil
        }
    }
}
