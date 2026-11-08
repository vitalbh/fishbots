import AppKit

/// xbar-style script plugins, in ~/Library/Application Support/Fishbots/plugins/.
///
/// - `name.5m.sh` (interval in the name: 10s, 5m, 1h…) runs from time to time. Each stdout line
///   is a protocol JSON. Entities that disappear from one run to the next leave the aquarium.
/// - `name.sh` (no interval) keeps running. Each line is applied right away, and if the plugin exits it is restarted.
/// Only executable files run. The folder is rescanned every 20 s.
final class Plugins {
    struct RunState {
        var lastRun: Date?
        var ok = true
        var error: String?
    }

    unowned let tank: Tank
    private(set) var states: [String: RunState] = [:]
    private var periodic: [String: Timer] = [:]
    private var running: [String: Process] = [:]
    private var entities: [String: Set<String>] = [:]   // plugin → "source\tentity" (or "@presence\tsource\tid") from the last run
    private var scan: Timer?

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fishbots/plugins", isDirectory: true)
    }

    init(tank: Tank) {
        self.tank = tank
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        sync()
        scan = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in self?.sync() }
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// "github.5m.sh" → 300 s; "something.sh" → nil (continuous).
    static func interval(_ name: String) -> TimeInterval? {
        let parts = name.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let p = parts[parts.count - 2]
        guard let u = p.last, let n = Double(p.dropLast()), n > 0 else { return nil }
        switch u {
        case "s": return max(5, n)
        case "m": return n * 60
        case "h": return n * 3600
        case "d": return n * 86400
        default: return nil
        }
    }

    private func executables() -> [String] {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(atPath: Self.folder.path)) ?? []
        return items.filter { n in
            guard !n.hasPrefix("."), !n.hasSuffix(".md"), !n.hasSuffix(".json"), !n.hasSuffix(".txt") else { return false }
            return fm.isExecutableFile(atPath: Self.folder.appendingPathComponent(n).path)
        }.sorted()
    }

    func sync() {
        let current = Set(executables())
        // removed
        for name in Set(periodic.keys).union(running.keys) where !current.contains(name) {
            periodic[name]?.invalidate(); periodic[name] = nil
            running[name]?.terminate(); running[name] = nil
            for e in entities[name] ?? [] { remove(e) }
            entities[name] = nil
            states[name] = nil
        }
        // new
        for name in current where periodic[name] == nil && running[name] == nil {
            states[name] = RunState()
            if let iv = Self.interval(name) {
                runOnce(name)
                let t = Timer(timeInterval: iv, repeats: true) { [weak self] _ in self?.runOnce(name) }
                RunLoop.main.add(t, forMode: .common)
                periodic[name] = t
            } else {
                startContinuous(name, wait: 0)
            }
        }
    }

    private func process(_ name: String) -> Process {
        let p = Process()
        p.executableURL = Self.folder.appendingPathComponent(name)
        p.currentDirectoryURL = Self.folder
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        let port = Env.value("PORT") ?? "7777"
        env["FISHBOTS_PORT"] = port; env["AQUARIO_PORT"] = port   // the old name too, for older plugins
        p.environment = env
        return p
    }

    // MARK: periodic

    private var inProgress = Set<String>()

    private func runOnce(_ name: String) {
        guard !inProgress.contains(name) else { return }
        inProgress.insert(name)
        let p = process(name)
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var data = Data(), stderrData = Data()
            do {
                try p.run()
                // don't let a plugin hang forever
                let limit = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + min(120, (Self.interval(name) ?? 60))) { limit.perform() }
                data = out.fileHandleForReading.readDataToEndOfFile()
                stderrData = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                limit.cancel()
            } catch {
                stderrData = Data("\(error)".utf8)
            }
            let status = p.isRunning ? -1 : p.terminationStatus
            DispatchQueue.main.async {
                guard let self else { return }
                self.inProgress.remove(name)
                let seen = self.apply(lines: data)
                // only remove the entities that disappeared if the run succeeded (otherwise a network failure would empty the aquarium)
                if status == 0 {
                    for e in (self.entities[name] ?? []).subtracting(seen) { self.remove(e) }
                    self.entities[name] = seen
                }
                let msg = String(decoding: stderrData, as: UTF8.self).split(separator: "\n").last.map(String.init)
                self.states[name] = RunState(lastRun: Date(), ok: status == 0, error: status == 0 ? nil : (msg ?? tr("saiu com %d", Int(status))))
            }
        }
    }

    // MARK: continuous

    private func startContinuous(_ name: String, wait: TimeInterval) {
        let p = process(name)
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        var rest = Data()
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            guard !d.isEmpty else { return }
            rest.append(d)
            guard let last = rest.lastIndex(of: UInt8(ascii: "\n")) else { return }
            let ready = rest[rest.startIndex...last]
            rest = Data(rest[rest.index(after: last)...])
            let copy = Data(ready)
            DispatchQueue.main.async { _ = self?.apply(lines: copy) }
        }
        p.terminationHandler = { [weak self] proc in
            out.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                guard let self, self.running[name] === proc else { return }
                self.running[name] = nil
                self.states[name] = RunState(lastRun: Date(), ok: false, error: tr("saiu com %d; reinicio em breve", Int(proc.terminationStatus)))
                let next = min(60, max(5, wait * 2))
                DispatchQueue.main.asyncAfter(deadline: .now() + next) {
                    if FileManager.default.isExecutableFile(atPath: Self.folder.appendingPathComponent(name).path), self.running[name] == nil {
                        self.startContinuous(name, wait: next)
                    }
                }
            }
        }
        do {
            try p.run()
            running[name] = p
            states[name] = RunState(lastRun: Date(), ok: true, error: nil)
        } catch {
            states[name] = RunState(lastRun: Date(), ok: false, error: "\(error)")
        }
    }

    func stop() {
        for p in running.values { p.terminate() }
    }

    // MARK: apply

    /// Applies each JSON line and returns the entities seen (that didn't leave).
    private func apply(lines d: Data) -> Set<String> {
        var seen = Set<String>()
        for line in d.split(separator: UInt8(ascii: "\n")) where !line.isEmpty {
            let l = Data(line)
            _ = TankProtocol.apply(l, at: tank)
            if let raw = (try? JSONSerialization.jsonObject(with: l)) as? [String: Any],
               case let m = TankProtocol.normalized(raw),
               let f = m["source"] as? String, !State.isEnd(m["state"] as? String ?? "") {
                if let e = m["entity"] as? String { seen.insert("\(f)\t\(e)") }
                if let p = m["presence"] as? String { seen.insert("@presence\t\(f)\t\(p)") }
            }
        }
        return seen
    }

    private func remove(_ projectKey: String) {
        if projectKey.hasPrefix("@presence\t") {
            let p = projectKey.split(separator: "\t", maxSplits: 2).map(String.init)
            if p.count == 3 { tank.scene.remove(source: p[1], id: p[2], party: false, tank) }
            return
        }
        let p = projectKey.split(separator: "\t", maxSplits: 1).map(String.init)
        if p.count == 2 { tank.remove(source: p[0], entity: p[1]) }
    }
}
