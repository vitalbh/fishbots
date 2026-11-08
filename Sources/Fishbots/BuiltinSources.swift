import Foundation

/// Built-in source: the Mac itself. For now, the disk (when it fills up, the water gets murky).
final class MacSource {
    private var timer: Timer?
    unowned let tank: Tank

    init(tank: Tank) {
        self.tank = tank
        read()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.read() }
    }

    private func read() {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let freeSlot = v.volumeAvailableCapacityForImportantUsage, let total = v.volumeTotalCapacity, total > 0 else { return }
        let used = 1 - Double(freeSlot) / Double(total)
        tank.gauge(source: "mac", name: "disk", value: Float(used))
    }
}

/// Demo mode: fake sessions changing state, to see and hear it without plugging anything in.
final class Demo {
    private struct Session {
        let id: String
        let label: String
        var state: State
        var until: Double
    }

    unowned let tank: Tank
    private var timer: Timer?
    private var sessions: [Session] = []
    private var nextDeploy: Double = 0
    private(set) var on = false
    private let tools = ["Bash", "Read", "Edit", "Grep", "Bash", "Write", "Glob", "Agent", "WebSearch"]

    init(tank: Tank) { self.tank = tank }

    func toggle() { on ? turnOff() : turnOn() }

    func turnOn() {
        guard !on else { return }
        on = true
        let now = Date().timeIntervalSince1970
        sessions = [
            Session(id: "demo-1", label: "meu-site", state: .busy, until: now + 6),
            Session(id: "demo-2", label: "elan", state: .busy, until: now + 3),
            Session(id: "demo-3", label: "ads-data-pipeline", state: .idle, until: now + 8),
            Session(id: "demo-4", label: "meu-site", state: .busy, until: now + 5),
        ]
        // one session from each app, to see the species
        let sampleWhereabouts: [[String: String]] = [["term": "rex"], ["term": "iTerm.app", "tty": "ttys004"],
                                         ["app": "/Applications/ClaudeCode.app"], ["term": "vscode"]]
        for (i, s) in sessions.enumerated() {
            tank.upsert(source: "demo", entity: s.id, state: s.state, label: s.label)
            if let f = tank.fish(source: "demo", entity: s.id) { f.whereabouts = sampleWhereabouts[i % sampleWhereabouts.count]; Providers.refresh(f); f.sub = Whereabouts.terminalName(sampleWhereabouts[i % sampleWhereabouts.count]["term"] ?? "ClaudeCode") }
        }
        nextDeploy = now + 20
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.step() }
    }

    func turnOff() {
        guard on else { return }
        on = false
        timer?.invalidate()
        timer = nil
        for s in sessions { tank.remove(source: "demo", entity: s.id) }
        sessions = []
    }

    private func step() {
        let now = Date().timeIntervalSince1970
        for i in sessions.indices {
            var s = sessions[i]
            if s.state == .busy && Double.random(in: 0...1) < 0.3 {
                let tool = tools.randomElement()!
                tank.tool(source: "demo", entity: s.id, name: tool)
                if tool == "Agent" { tank.fry(source: "demo", entity: s.id) }
            }
            if Double.random(in: 0...1) < 0.04 { tank.removeFry(source: "demo", entity: s.id) }
            if now > s.until {
                let (new, dur): (State, Double)
                switch s.state {
                case .busy:
                    let r = Double.random(in: 0...1)
                    if r < 0.3 { (new, dur) = (.waiting, .random(in: 6...10)) }
                    else if r < 0.42 { (new, dur) = (.error, .random(in: 5...8)) }
                    else { (new, dur) = (.done, .random(in: 5...7)) }
                case .done: (new, dur) = (.idle, .random(in: 6...14))
                default: (new, dur) = (.busy, .random(in: 6...14))
                }
                s.state = new
                s.until = now + dur
                tank.upsert(source: "demo", entity: s.id, state: new, label: s.label)
            }
            sessions[i] = s
        }
        if now > nextDeploy {
            nextDeploy = now + .random(in: 25...45)
            tank.event(source: "demo", name: "deploy", label: "deploy meu-site")
        }
    }
}
