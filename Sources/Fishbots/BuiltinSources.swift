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
        tank.gauges.set(source: "mac", name: "disk", value: Float(used))
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
        // the scene too (docs/scene.md): presences that change state, and a "moment" now and then
        let t = tank
        for (id, kind, state, label, detail, x) in [
            ("prod", "pilot", "ok", "prod", "312 pods ok", 0.08), ("staging", "pilot", "busy", "staging", "Flux reconciliando", 0.92),
            ("edge", "pilot", "ok", "edge", "48 pods ok", 0.5), ("ship", "helm", "ok", "navio", "rumo certo", 0.27),
            ("issue", "bottle", "waiting", "TypeError", "checkout · 12 eventos", 0.62),
            ("deploy", "hourglass", "busy", "deploy", "faltam 4 min", 0.45), ("site", "flag", "ok", "meu-site", "99,98% · 120 ms", 0.78),
        ] as [(String, String, String, String, String, Double)] {
            _ = t.scene.upsert(t, source: "demo", id: id, kind: kind, state: State(rawValue: state), label: label, detail: detail,
                               link: nil, value: kind == "hourglass" ? 1 : nil, color: nil, x: Float(x))
        }
        nextMoment = now + 12
        moment = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in self?.step() }
    }

    private var nextMoment: Double = 0
    private var moment = 0
    private var endShark: Double = 0
    private var endRain: Double = 0

    /// A moment of the scene, in turns: a shark, a rain shower, fireworks, a school, lightning, a shooting star;
    /// and the presences change state.
    private func sceneMoment(_ now: Double) {
        let t = tank
        switch moment % 6 {
        case 0:
            _ = t.scene.upsert(t, source: "demo", id: "shark", kind: "shark", state: .error, label: "prod",
                               detail: "3 pods em CrashLoop", link: nil, value: nil, color: nil, x: nil)
            _ = t.scene.upsert(t, source: "demo", id: "prod", kind: nil, state: .error, label: nil, detail: "3 pods em CrashLoop",
                               link: nil, value: nil, color: nil, x: nil)
            endShark = now + 18
        case 1:
            t.gauges.set(source: "demo", name: "rain", value: 0.8)
            t.gauges.set(source: "demo", name: "waves", value: 0.7)
            endRain = now + 16
        case 2: _ = t.scene.effect("fireworks", t, source: "demo", label: "deploy meu-site", x: 0.5, y: nil, color: nil)
        case 3:
            _ = t.scene.effect("school", t, source: "demo", label: nil, x: nil, y: nil, color: nil)
            _ = t.scene.upsert(t, source: "demo", id: "staging", kind: nil, state: .alert, label: nil, detail: "2 CrashLoop",
                               link: nil, value: nil, color: nil, x: nil)
        case 4:
            _ = t.scene.effect("lightning", t, source: "demo", label: "pico de erros", x: nil, y: nil, color: nil)
            _ = t.scene.upsert(t, source: "demo", id: "staging", kind: nil, state: .busy, label: nil, detail: "Flux reconciliando",
                               link: nil, value: nil, color: nil, x: nil)
        default:
            _ = t.scene.effect("shooting-star", t, source: "demo", label: nil, x: nil, y: nil, color: nil)
            _ = t.scene.upsert(t, source: "demo", id: "issue", kind: nil, state: .waiting, label: nil, detail: "checkout · 12 eventos",
                               link: nil, value: nil, color: nil, x: nil)
        }
        moment += 1
    }

    func turnOff() {
        guard on else { return }
        on = false
        timer?.invalidate()
        timer = nil
        for s in sessions { tank.remove(source: "demo", entity: s.id) }
        sessions = []
        for p in tank.scene.presences where p.source == "demo" {
            tank.scene.remove(source: "demo", id: String(p.id.dropFirst("demo:".count)), party: false, tank)
        }
        tank.gauges.remove(source: "demo", name: "rain")
        tank.gauges.remove(source: "demo", name: "waves")
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
        // the scene's moments, the hourglass running down, the shark leaving, the rain stopping
        if now > nextMoment { nextMoment = now + .random(in: 20...35); sceneMoment(now) }
        if let h = tank.scene.presence(source: "demo", id: "deploy") {
            let v = max(0, (h.value ?? 1) - 0.35 / 240)
            let left = Int((v * 4 * 60).rounded())
            _ = tank.scene.upsert(tank, source: "demo", id: "deploy", kind: nil, state: v > 0 ? .busy : .done, label: nil,
                                  detail: v > 0 ? "faltam \(left / 60):\(String(format: "%02d", left % 60))" : "no ar",
                                  link: nil, value: v > 0 ? v : 1, color: nil, x: nil)
        }
        if endShark > 0 && now > endShark {
            endShark = 0
            tank.scene.remove(source: "demo", id: "shark", party: false, tank)
            _ = tank.scene.upsert(tank, source: "demo", id: "prod", kind: nil, state: .ok, label: nil, detail: "312 pods ok",
                                  link: nil, value: nil, color: nil, x: nil)
        }
        if endRain > 0 && now > endRain {
            endRain = 0
            tank.gauges.remove(source: "demo", name: "rain")
            tank.gauges.remove(source: "demo", name: "waves")
        }
        if now > nextDeploy {
            nextDeploy = now + .random(in: 25...45)
            tank.event(source: "demo", name: "deploy", label: "deploy meu-site")
        }
    }
}
