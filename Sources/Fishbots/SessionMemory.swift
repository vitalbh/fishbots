import Foundation

/// Remembers the agent sessions across app restarts: they're saved to fish.json now and then and when the app quits,
/// and come back quietly when it opens, but only the ones still alive (a session that closed while the app was off never
/// sent its SessionEnd, and a "zombie" fish is worse than one that waits for the next event to come back).
enum SessionMemory {
    /// What we keep of each session.
    struct Saved: Codable {
        var source: String
        var entity: String
        var label: String
        var state: String
        var whereabouts: [String: String]
        var title: String?
        var logTitle: String?
        var fixedTitle: String?
        var branch: String?
        var context: Float?
        var lastReply: String?
        var asked: String?
        var link: String?
        var transcriptPath: String?
        /// Last sign of life (wall clock).
        var lastSeen: Date
    }

    private static var lastWritten: Data?
    private static var lastWriteAt: Date?

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fishbots/fish.json")
    }

    /// Sessions silent for longer than this don't come back.
    private static let maxSilence: TimeInterval = 12 * 3600
    /// Without a process or a Rex pane to check, the transcript must have changed this recently.
    private static let maxTranscriptAge: TimeInterval = 6 * 3600

    static func save(_ tank: Tank) {
        let now = Date()
        let saved = tank.fish.filter { $0.isAgent && !$0.decor && !$0.leaving && Providers.of($0.source) is TerminalAgentProvider }.map { f in
            Saved(source: f.source, entity: String(f.id.dropFirst(f.source.count + 1)), label: f.label, state: f.state.rawValue,
                  whereabouts: f.whereabouts, title: f.title, logTitle: f.logTitle, fixedTitle: f.fixedTitle, branch: f.branch,
                  context: f.context, lastReply: f.lastReply, asked: f.asked, link: f.link, transcriptPath: f.transcriptPath,
                  lastSeen: now.addingTimeInterval(-(tank.time - f.seen)))
        }
        // lastSeen moves on every save: compare without it, and only write when something else changed
        let key = try? JSONEncoder().encode(saved.map { var s = $0; s.lastSeen = .distantPast; return s })
        if key == lastWritten, let at = lastWriteAt, now.timeIntervalSince(at) < 600 { return }
        guard let d = try? JSONEncoder().encode(saved) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? d.write(to: url, options: .atomic)
        lastWritten = key
        lastWriteAt = now
    }

    /// Reads fish.json, checks which sessions are still alive (in the background: it asks ps and Rex) and hands those
    /// back on the main thread.
    static func restore(_ done: @escaping ([Saved]) -> Void) {
        guard let d = try? Data(contentsOf: url), let all = try? JSONDecoder().decode([Saved].self, from: d) else { return }
        // which process names each source's agent has (the registry is read here, on the main thread)
        let names = Dictionary(Set(all.map(\.source)).map { ($0, Providers.processNames($0)) }) { a, _ in a }
        DispatchQueue.global(qos: .userInitiated).async {
            let alive = all.filter { isAlive($0, names: names[$0.source] ?? []) }
            DispatchQueue.main.async { done(alive) }
        }
    }

    private static func isAlive(_ s: Saved, names: [String]) -> Bool {
        guard Date().timeIntervalSince(s.lastSeen) < maxSilence else { return false }
        let o = s.whereabouts
        // the agent's process (sent by the hook outside Rex/iTerm/tmux…)
        if let p = o["pid"].flatMap(Int32.init) {
            return processIsAgent(p, names: names)
        }
        // the Rex pane, still with the agent in front
        if let b = o["rex_block"], let bin = rexBin(o) {
            guard let pr = json(run(bin, ["--timeout", "3s", "block", "call", "-b", b, "process"])),
                  let fg = pr["foreground"] as? [String: Any] else { return false }
            let all = [fg["path"], fg["argv0"], fg["name"]].compactMap { $0 as? String }.joined(separator: " ")
            return Providers.isAgentProcess(all, names: names)
        }
        // otherwise: the conversation was written recently
        if let t = s.transcriptPath,
           let m = (try? FileManager.default.attributesOfItem(atPath: t))?[.modificationDate] as? Date {
            return Date().timeIntervalSince(m) < maxTranscriptAge
        }
        return false
    }

    /// The process exists and is the session's agent (not another program that got the same pid).
    private static func processIsAgent(_ pid: Int32, names: [String]) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        let out = String(decoding: run("/bin/ps", ["-o", "command=", "-p", String(pid)]), as: UTF8.self)
        return Providers.isAgentProcess(out, names: names)
    }

    private static func rexBin(_ o: [String: String]) -> String? {
        let candidates = [o["rex_bin"], NSString("~/.local/bin/rex").expandingTildeInPath, "/opt/homebrew/bin/rex", "/usr/local/bin/rex"]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ bin: String, _ args: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return Data() }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return d
    }

    private static func json(_ d: Data) -> [String: Any]? { (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] }
}
