import Foundation
import QuartzCore
import simd

/// The world: fish, particles and gauges. Everything runs on the main thread.
final class Tank {
    var size: SIMD2<Float> = [960, 600]
    private(set) var fish: [Fish] = []
    private(set) var particles: [Particle] = []
    let gauges = Gauges()
    var light: Float = 1
    var turbidity: Float = 0
    var jellyGlow: Float = 0
    var pendingArp = 0
    /// Called when a fish changes state (or arrives): (fish, previous state).
    /// Describes each source's fish (set by the app from the session providers).
    var profile: (String) -> SourceProfile = { _ in SourceProfile() }
    var onState: ((Fish, State?) -> Void)?
    /// Called when food drops (event or click), with the location.
    var onEvent: ((SIMD2<Float>) -> Void)?
    /// Merged PR / fry leaving with a party (for the journal).
    var onParty: ((Fish) -> Void)?
    /// Splash at the surface (jump): for the visualizer to make the wave.
    var onSplash: ((Float) -> Void)?
    /// Parallax: where you "look" (-1…1), smoothed.
    private(set) var gaze: SIMD2<Float> = .zero
    /// Where the mouse is (the curious ones come close) and when it last moved.
    var cursor: SIMD2<Float>?
    var cursorAt: Double = 0
    private(set) var cursorRestingAt: Double = 0
    /// Night-time tag: who chases, who runs, until when.
    private(set) var game: (chaser: String, runner: String, until: Double)?
    private var nextGame: Double = 0
    private var nextChat: Double = 0
    /// Ambient creatures: crabs, turtle, snail, starfish, lanternfish and the whale.
    let fauna = Fauna()
    /// What plugins put in the scene: presences (creatures and objects with a state and text) and effects. See docs/scene.md.
    let scene = Scene()
    /// The fish under the mouse (or with its card open): swims in a circle in place, so it doesn't escape the hover.
    var focused: String? {
        didSet { if focused != oldValue, let f = fish.first(where: { $0.id == focused }) { focusCenter = f.pos } }
    }
    private(set) var focusCenter: SIMD2<Float> = .zero
    /// Summary parade: the highlighted fish comes to the front of the glass.
    var highlighted: String?
    private(set) var jellyPos: SIMD2<Float> = [700, 380]
    private(set) var jellyPhase: Float = 0
    private var later: [(Double, () -> Void)] = []
    private var bubblerAt: Double = 0
    private(set) var time: Double = CACurrentMediaTime()

    /// Pearls of the day, on the sand.
    let pearls = Pearls()
    /// For testing: FISHBOTS_FAST=1 shortens the timings (sleeping, fogged glass, lingering error).
    static let scale: Double = Env.value("FAST") == "1" || ProcessInfo.processInfo.environment["AQUARIO_RAPIDO"] == "1" ? 0.04 : 1
    /// Mail seahorses (MCP tools): bring a little letter in the server's color.
    struct Mail {
        var pos: SIMD2<Float>
        var goal: String
        var color: SIMD3<Float>
        var side: Float
        var stage = 0           // 0 going, 1 meeting, 2 returning
        var since: Double
        var letter = true
        var phase: Float = 0
    }
    private(set) var mails: [Mail] = []
    /// Current (high CPU), in px/s.
    private(set) var current: Float = 0
    /// A current from the music (the storm visualizer, when it's heavy): it has to be kept up, or it fades.
    private var musicCurrent: (value: Float, at: Double) = (0, -100)
    func musicStream(_ v: Float) { musicCurrent = (v, time) }

    init() {
        setSchools(School.usual)
    }

    /// The decorative schools (no sound, no label), so the tank is alive even with few sessions; the theme picks them.
    /// The phase says the school (phase / 100) and the place in it (phase % 100 == 0: the leader). The first swims in
    /// the middle, the second up high, the third low in the back.
    func setSchools(_ schools: [School]) {
        let old = fish.filter(\.decor)
        fish.removeAll { $0.decor }
        for (s, sc) in schools.enumerated() {
            for i in 0..<sc.count {
                // a new school starts where the old fish were (no jump when the theme changes)
                let from = old.isEmpty ? SIMD2<Float>(Float.random(in: 200...700), Float.random(in: 250...450)) : old.randomElement()!.pos
                let f = Fish(id: "decor:\(s * 100 + i)", source: "decor", label: "",
                             pos: from, size: Float.random(in: sc.size),
                             color: sc.color, stripes: true, motif: 0, timbre: .pluck, phase: s * 100 + i, decor: true, now: time)
                f.state = .idle
                f.pattern = sc.pattern
                f.depth = Float.random(in: sc.depth)
                f.restDepth = f.depth
                f.species = FishKinds.index(of: sc.kind)
                fish.append(f)
            }
        }
    }

    /// The mouse moved (or left the tank, with nil).
    private var rippleFrom: SIMD2<Float>?
    private var rippleAt: Double = 0

    func moveCursor(_ p: SIMD2<Float>?) {
        if let p, let c = cursor, simd_distance(p, c) > 3 { cursorRestingAt = time }
        // the mouse moving through the water leaves a trail of faint rings
        if let p, p.y < size.y * 0.95, p.y > size.y * sand(p.x / max(1, size.x)) + 8 {
            if let r = rippleFrom, simd_distance(p, r) > 46, time - rippleAt > 0.07 {
                particles.append(Particle(pos: p, vel: .zero, life: 0, maxLife: 0.9, size: 3, grow: 34, kind: 2,
                                          color: [0.42, 0.58, 0.66, 1]))
                rippleFrom = p
                rippleAt = time
                motes.stir(self, at: p, radius: 60, strength: 14)
            } else if rippleFrom == nil { rippleFrom = p }
        } else {
            rippleFrom = nil
        }
        cursor = p
        cursorAt = time
    }

    /// Click near (but not on) fish: they get scared and flee. Returns true if it scared anyone.
    @discardableResult
    func scare(_ p: SIMD2<Float>) -> Bool {
        motes.stir(self, at: p, radius: 170, strength: 90)
        var some = false
        for f in fish where !f.leaving && simd_distance(f.pos, p) < 150 {
            f.fearUntil = time + 1.1
            f.fearFrom = p
            let d = f.pos - p
            f.vel += (simd_length(d) > 1 ? simd_normalize(d) : [1, 0]) * 260
            // was asleep: wakes with a start (jumps up, a burst of bubbles) and stays awake a while
            if sleeping(f) {
                f.vel += [0, 220]
                f.since = time - 60
                f.awakeUntil = time + 1.8
                burst(at: f.pos, n: 8)
            }
            some = true
        }
        if some { burst(at: p, n: 5) }
        return some
    }

    func splash(at p: SIMD2<Float>) {
        onSplash?(p.x)
        for _ in 0..<10 {
            particles.append(Particle(pos: p, vel: [Float.random(in: -60...60), Float.random(in: 40...120)], life: 0,
                                      maxLife: Float.random(in: 0.4...0.7), size: Float.random(in: 3...5), grow: 0, kind: 4,
                                      color: [0.85, 0.95, 1, 1]))
        }
        burst(at: [p.x, p.y - 20], n: 6)
    }

    // MARK: - Protocol

    func id(_ source: String, _ entity: String) -> String { "\(source):\(entity)" }

    func upsert(source: String, entity: String, state: State, label: String?) {
        let key = id(source, entity)
        if let f = fish.first(where: { $0.id == key }) {
            f.seen = time
            if let r = label, !r.isEmpty { f.label = r }
            if f.leaving { f.leaving = false }
            guard f.state != state else { return }
            let before = f.state
            if sleeping(f) {                                          // was sleeping: yawns and stretches
                f.awakeUntil = time + 1.8
                particles.append(Particle(pos: f.pos + facing(f) * f.size * 0.9, vel: [0, 18], life: 0, maxLife: 2.5, size: 5, grow: 6,
                                          kind: 2, color: [0.9, 0.95, 1, 1]))
            }
            if state == .busy && before != .busy && f.workingSince == nil { f.workingSince = time; f.toolSinceStart = 0 }
            f.state = state
            f.changed = true
            defer { onState?(f, before) }
            f.since = time
            f.escalated = false
            if state == .error { f.lastError = Date() }
            if state == .done { f.moment = (tr("✓ terminou"), time + 4) }
            if state == .done {
                // big task (over 5 min or many tools): jumps out of the water
                if let t0 = f.workingSince, f.isAgent, time - t0 > 300 || f.toolSinceStart >= 25 {
                    after(2.2) { [weak self, weak f] in
                        guard let self, let f, f.jumpPhase == 0, !f.leaving else { return }
                        f.jumpPhase = 1
                        f.jumpDir = f.vel.x >= 0 ? 1 : -1
                        _ = self
                    }
                }
                f.workingSince = nil
                f.finished.append((Date(), f.displayTitle ?? f.label))
                if f.finished.count > 30 { f.finished.removeFirst() }
                f.resolve = true
                burst(at: f.pos, n: 3)
                if f.isAgent || f.source == "test" {
                    pearls.add(color: f.color, title: f.displayTitle ?? f.label, project: f.label, in: self)
                }
            }
            if state == .error {
                f.shake = 1
                if f.kindID == "octopus" { ink(at: f.pos, n: 7, color: [0.06, 0.03, 0.1]) }   // the octopus releases ink
            }
            if before == .error && state != .error { f.spin = 1 }                       // recovered: does a little spin
            if state != .busy { f.tool = nil; f.doing = nil }
            if state != .waiting { f.asked = nil }
            return
        }
        let name = (label?.isEmpty == false ? label! : entity)
        let present = Set(fish.filter { !$0.decor }.map(\.motif))
        let motif = Motifs.motif(for: "\(source):\(name)", present: present)
        let h = fnv(name)
        let variant = fish.filter { !$0.decor && !$0.leaving && $0.source == source && $0.label == name }.map(\.variant).max().map { $0 + 1 } ?? 0
        let hue = Float(h % 360) / 360
        // siblings (same project): the hue shifts a bit and the color gets lighter or darker
        let vh = Float(variant) * 0.07
        let color = hsv((hue + vh).truncatingRemainder(dividingBy: 1), variant % 2 == 1 ? 0.45 : 0.62, variant == 0 ? 0.95 : 0.85)
        let profile = self.profile(source)
        let timbre = profile.timbre ?? ((h >> 12) & 1 == 0 ? .pluck : .bell)
        let start: SIMD2<Float> = [Float.random(in: size.x * 0.2...size.x * 0.8), size.y + 30]
        let f = Fish(id: key, source: source, label: name, pos: start, size: Float(30 + (h >> 20) % 12) * (variant == 0 ? 1 : 0.82),
                     color: color, stripes: (h >> 8) & 1 == 1, motif: motif, timbre: timbre,
                     phase: fish.filter { !$0.decor }.count, decor: false, now: time)
        f.vel = [0, -120]
        f.variant = variant
        profile.apply(to: f)
        if f.isAgent { f.veteran = Self.veteranLevel(f.projectKey) }
        if state == .busy { f.workingSince = time }      // born already working
        // sessions stay near (readable); PRs and other sources, a bit further back
        f.depth = f.isAgent ? Float.random(in: 0...0.15) : Float.random(in: 0.15...0.4)
        f.pattern = Int((h >> 24) % 6)
        f.cut = Int((h >> 28) % 4)
        f.state = state
        f.intro = true
        fish.append(f)
        burst(at: [start.x, size.y - 10], n: 12)
        onState?(f, nil)
    }

    func fish(source: String, entity: String) -> Fish? {
        fish.first { $0.id == id(source, entity) }
    }

    /// The (non-decorative) fish under the point, nearest first.
    func fish(at p: SIMD2<Float>) -> Fish? {
        fish.filter { !$0.decor && !$0.leaving && !isHidden($0) && simd_distance($0.pos, p) < max(26, $0.size * 1.3) }
            .min { simd_distance($0.pos, p) < simd_distance($1.pos, p) }
    }

    func remove(source: String, entity: String, party: Bool = false) {
        guard let f = fish.first(where: { $0.id == id(source, entity) }) else { return }
        if party && !f.leaving { f.party = true; onEvent?(f.pos); onParty?(f) }
        f.leaving = true
        for c in fish where c.parent === f { c.leaving = true }
    }

    // MARK: subagents

    /// Subagent started: a fry is born that follows the session.
    func fry(source: String, entity: String) {
        guard let parent = fish(source: source, entity: entity),
              fish.filter({ $0.parent === parent && !$0.leaving }).count < 6 else { return }
        let n = fish.count
        let c = Fish(id: "\(parent.id)#fry\(n)-\(Int(time * 1000) % 100000)", source: "fry", label: "", pos: parent.pos,
                     size: max(9, parent.baseSize * 0.36), color: mix(parent.color, [1, 1, 1], t: 0.15), stripes: parent.stripes,
                     motif: parent.motif, timbre: parent.timbre, phase: 1000 + n, decor: true, now: time)
        c.parent = parent
        c.depth = parent.depth
        c.pattern = parent.pattern
        c.cut = parent.cut
        c.state = .busy
        c.vel = parent.vel
        fish.append(c)
        sparkle(at: parent.pos, color: parent.color)
    }

    /// Subagent finished: the oldest fry rises and leaves.
    func removeFry(source: String, entity: String) {
        guard let parent = fish(source: source, entity: entity),
              let c = fish.first(where: { $0.parent === parent && !$0.leaving }) else { return }
        c.leaving = true
        c.party = true
    }

    // MARK: ink and pearls

    func ink(at p: SIMD2<Float>, n: Int, color: SIMD3<Float>) {
        for _ in 0..<n {
            let a = Float.random(in: 0...(2 * .pi))
            particles.append(Particle(pos: p + SIMD2(cosf(a), sinf(a)) * Float.random(in: 0...14),
                                      vel: SIMD2(cosf(a), sinf(a)) * Float.random(in: 10...30) + [0, 4], life: 0,
                                      maxLife: Float.random(in: 6...9), size: Float.random(in: 14...24), grow: Float.random(in: 6...12),
                                      kind: 10, color: SIMD4(color, 1)))
        }
    }

    /// The pearls of a period light up one after another.
    func highlightPearls(since: Date, until: Date) {
        for (k, i) in pearls.indices(since: since, until: until).enumerated() {
            after(Double(k) * 0.35) { [weak self] in
                guard let self, let at = self.pearls.light(i, now: self.time) else { return }
                self.sparkle(at: at + [0, 6], color: [1, 0.95, 0.8])
            }
        }
    }

    /// Music notes rising from a singing fish's head.
    func notes(from f: Fish, n: Int) {
        for i in 0..<n {
            let c = mix(f.color, [1, 1, 1], t: 0.35)
            particles.append(Particle(pos: f.pos + [Float.random(in: -f.size * 0.4...f.size * 0.4), f.size * 0.5 + Float(i) * 6],
                                      vel: [0, Float.random(in: 20...30)], life: 0, maxLife: Float.random(in: 2.8...4),
                                      size: Float.random(in: 11...15), grow: 0, kind: 24, color: SIMD4(c, 1)))
        }
    }

    /// The program in a terminal said what it's doing (nil: it stopped saying). The fish in that terminal (the
    /// whereabouts key that names it, and its id there: a Rex pane, a Herdr terminal) shows it for a few seconds,
    /// like the tool's name, and keeps it for the card.
    func doing(at key: String, _ id: String, _ text: String?) {
        for f in fish where !f.decor && !f.leaving && f.whereabouts[key] == id {
            f.doing = text
            f.doingAt = time
            if let text, f.state == .busy { f.moment = (text.count > 44 ? String(text.prefix(43)) + "…" : text, time + 6) }
            // …or just after it: they go with the tool it has just started
            if let text, let last = f.history.last, last.said == nil, Date().timeIntervalSince(last.when) < 3 {
                f.history[f.history.count - 1].said = text
            }
        }
    }

    func tool(source: String, entity: String, name: String) {
        guard let f = fish.first(where: { $0.id == id(source, entity) }) else { return }
        f.tool = name
        f.seen = time
        f.toolTimes.append(time)
        // its own words about this call, if they came just before it (and weren't about the call before)
        let said = f.doing != nil && time - f.doingAt <= 1.5 && f.history.last?.said != f.doing ? f.doing : nil
        f.history.append((Date(), name, said))
        // its own words about this tool, if they've just arrived, say more than the tool's name
        if f.doing == nil || time - f.doingAt > 1.5 { f.moment = (ToolBehaviors.of(name).label(name), time + 4) }
        f.toolSinceStart += 1
        if f.history.count > 12 { f.history.removeFirst() }
        startAction(f, name)
        if f.ticks.count < 6 { f.ticks.append(ToolBehaviors.of(name).timbre) }
    }

    // MARK: MCP, lists and skills

    func mail(source: String, entity: String, server: String) {
        guard let f = fish(source: source, entity: entity) else { return }
        if let i = mails.firstIndex(where: { $0.goal == f.id && $0.stage < 2 }) { mails[i].since = time; return }
        let side: Float = f.pos.x < size.x / 2 ? -1 : 1
        let color = hsv(Float(fnv(server) % 360) / 360, 0.55, 1)
        mails.append(Mail(pos: [side < 0 ? -40 : size.x + 40, f.pos.y + Float.random(in: -30...30)], goal: f.id, color: color,
                                side: side, since: time))
        f.action = .mail
        f.actionSince = time
        f.actionUntil = time + 8
    }

    func todos(source: String, entity: String, total: Int, done: Int) {
        guard let f = fish(source: source, entity: entity) else { return }
        let before = f.todos?.done ?? 0
        f.todos = total > 0 ? (total, min(total, done)) : nil
        if f.todoU == nil { f.todoU = max(0.15, min(0.85, f.pos.x / max(1, size.x))) }
        if done > before, let u = f.todoU { sparkle(at: [size.x * u, size.y * sand(u) + 10], color: f.color) }
    }

    /// Skill: a ring of sparkles around the fish.
    func shine(source: String, entity: String) {
        guard let f = fish(source: source, entity: entity) else { return }
        for i in 0..<10 {
            let a = Float(i) / 10 * 2 * .pi
            particles.append(Particle(pos: f.pos + SIMD2(cosf(a), sinf(a)) * f.size * 1.1, vel: SIMD2(cosf(a), sinf(a)) * 14 + [0, 6],
                                      life: 0, maxLife: 1.4, size: 8, grow: 2, kind: 4, color: SIMD4(mix(f.color, [1, 1, 0.85], t: 0.5), 1)))
        }
    }

    // MARK: per-tool animation

    /// Rocks, the shell, the chest, corals and the packs' pieces.
    let scenery = Scenery()

    /// The seaweed: where it stands and how it bends.
    let weeds = Weeds()

    private var oxygenAt: Double = 0
    private var pearlGlintAt: Double = 0
    private var shapedAt: Double = 0
    /// How full of sessions the tank is (0: four or fewer, 1: ten or more), smoothed.
    private(set) var crowd: Float = 0

    /// By day, the seaweed lets out little oxygen bubbles now and then; still fish breathe out a bubble.
    private func breathe(dt: Float) {
        if light > 0.8, time > oxygenAt, !weeds.spots.isEmpty {
            oxygenAt = time + Double.random(in: 1.2...3.5)
            let wd = weeds.spots[Int.random(in: 0..<weeds.spots.count)]
            let y = size.y * (sand(wd.x) + wd.h * Float.random(in: 0.4...0.95))
            for i in 0..<Int.random(in: 1...3) {
                after(Double(i) * 0.25) { [weak self] in
                    guard let self else { return }
                    self.bubble(at: [wd.x * self.size.x + Float.random(in: -4...4), y], size: Float.random(in: 1.1...2.2))
                }
            }
        }
        // a pebble or shell under a passing sun ray catches the light
        if light > 0.8, let p = pebbles.randomElement(), Float.random(in: 0...1) < dt * 2.5 {
            let x = scenery.clear(self, size.x * p.u), at: SIMD2<Float> = [x, size.y * sand(x / max(1, size.x)) + p.size * 0.6]
            if rayLight(at) > 0.06 { sparkle(at: at, color: [1, 0.96, 0.85]) }
        }
        // by day a pearl on the sand catches the light now and then
        if light > 0.8, time > pearlGlintAt, let p = pearls.all.randomElement() {
            pearlGlintAt = time + Double.random(in: 2.5...6)
            sparkle(at: pearls.pos(p) + [1.5, 3], color: [1, 0.97, 0.9])
        }
        for f in fish where !f.decor && !f.leaving && (f.state == .idle || f.state == .ok) && !sleeping(f)
            && simd_length(f.vel) < 25 && Float.random(in: 0...1) < dt * 0.06 {
            bubble(at: f.pos + facing(f) * f.size * 0.9 + [0, 2], size: Float.random(in: 1.4...2.4))
        }
    }

    /// Marine snow, stirred by whatever moves the water.
    let motes = Motes()

    /// Night: the water is dark enough for the plankton to show (bioluminescence).
    var isNight: Bool { light < 0.75 }

    /// The shader's clock and the theme's ray strength (set by the app each frame), to know where the sun rays are.
    var shaderTime: Float = 0
    var rayStrength: Float = 0.3

    /// How lit a point is by the sun rays: the same formula as the background shader (bg_fragment).
    func rayLight(_ p: SIMD2<Float>) -> Float {
        let uv = p / SIMD2(max(1, size.x), max(1, size.y))
        let q: SIMD2<Float> = [uv.x * size.x / max(1, size.y), uv.y]
        let t = shaderTime
        let r1 = sinf((q.x + q.y * 0.35) * 9 + t * 0.25) * 0.5 + 0.5
        let r2 = sinf((q.x - q.y * 0.2) * 15 - t * 0.17) * 0.5 + 0.5
        let broad = powf(sinf((q.x + q.y * 0.5) * 3.1 + t * 0.05) * 0.5 + 0.5, 6) * smoothstep(0.25, 1, uv.y)
        return (powf(r1 * r2, 3) * smoothstep(0.1, 1, uv.y) + broad * 0.45) * rayStrength
    }

    /// Pebbles and tiny shells scattered on the sand (fixed places, away from the big scenery).
    private(set) lazy var pebbles: [(u: Float, size: Float, shell: Bool, tone: Float, seed: Float)] = (0..<26).map { i in
        let r = { (k: Float) -> Float in let v = sinf(Float(i) * 12.9898 + k * 78.233) * 43758.547; return v - floorf(v) }
        return (0.03 + r(1) * 0.94, 3.8 + r(2) * 4.6, r(3) < 0.22, r(4), r(5) * 6)
    }

    /// A piece of the theme's pack scenery standing in for a built-in thing ("looks": {"mote": "petal"}), if dressing is on.
    func themeLook(_ id: String) -> (Int, SceneryKind)? {
        guard FishKinds.dressByTheme, let look = Themes.current.looks[id], let i = SceneryKinds.index(of: look) else { return nil }
        return (i, SceneryKinds.all[i])
    }

    private func startAction(_ f: Fish, _ name: String) {
        guard f.isAgent else { return }
        let new: Action
        switch ToolBehaviors.of(name).animation {
        case .nibble: new = .nibble(weeds.nearest(self, to: f.pos))
        case .bubbles: new = .bubbles
        case .forage: new = .forage
        case .peek: new = .peek
        case .none: return
        }
        // the same tool again only extends; another one only switches after 1.5 s
        if let a = f.action, time < f.actionUntil, a.sameKind(new) { f.actionUntil = time + (new == .bubbles ? 1.5 : 6); return }
        if f.action != nil && time < f.actionUntil && time - f.actionSince < 1.5 { return }
        f.action = new
        f.actionSince = time
        f.actionUntil = time + (new == .bubbles ? 1.5 : 6)
        if case .nibble(let goal) = new { f.actionSide = f.pos.x < goal.x ? -1 : 1 }
        if new == .bubbles {
            // puff: the bubbles come out of the mouth one after another
            for i in 0..<11 {
                after(Double(i) * 0.05) { [weak self, weak f] in
                    guard let self, let f else { return }
                    let mouth = f.pos + self.facing(f) * f.size * 0.95
                    self.bubble(at: mouth + SIMD2(Float.random(in: -3...3), Float.random(in: -2...4)), size: Float.random(in: 1.6...3.6))
                }
            }
        }
    }

    /// A tool's short text, for the minimal label.
    func event(source: String, name: String, label: String?) {
        let x = Float.random(in: size.x * 0.2...size.x * 0.8)
        for i in 0..<10 {
            particles.append(Particle(pos: [x + Float.random(in: -40...40), size.y + Float(i) * 6], vel: [0, -28],
                                      life: 0, maxLife: 14, size: 3.2, grow: 0, kind: 3,
                                      color: [0.75, 0.5, 0.28, 1]))
        }
        pendingArp += 1
        notice = (label ?? name, time)
        noticeIcon = "🍤"
        onEvent?([x, size.y - 40])
    }

    /// Last event, to show for a few seconds. Setting it clears the icon; whoever wants one sets `noticeIcon` after.
    var notice: (String, Double)? { didSet { noticeIcon = nil } }
    var noticeIcon: String?

    private var rainAt: Double = 0

    /// The water's surface height at x, as the background shader draws it (waves included).
    func surfaceY(_ x: Float) -> Float {
        let u = x / max(1, size.x), t = shaderTime, waves = gauges.highest("waves") ?? 0
        let s = 0.965 + (0.006 * sinf(u * 30 + t * 1.5) + 0.004 * sinf(u * 71 - t * 2.3)) * (1 + 2.5 * waves)
              + 0.007 * waves * sinf(u * 13 - t * 3.1) - 0.004 * waves
        return size.y * s
    }

    /// Rain: drops hitting the surface (little rings) and, once in a while, a bubble pushed under.
    private func rainOnSurface() {
        guard let rain = gauges.highest("rain"), rain > 0.01, time > rainAt else { return }
        rainAt = time + Double(0.5 / (1 + rain * 30))
        let x = Float.random(in: 0...size.x), surf = surfaceY(x)
        particles.append(Particle(pos: [x, surf], vel: .zero, life: 0, maxLife: 0.8, size: 2, grow: 18 + rain * 14, kind: 8,
                                  color: [0.8, 0.92, 1, 1]))
        if Float.random(in: 0...1) < 0.2 { bubble(at: [x, surf - Float.random(in: 4...20)], size: Float.random(in: 1...1.8)) }
    }

    /// When each project first showed up (kept in the settings), and how veteran that makes it.
    static func veteranLevel(_ key: String) -> Int {
        let d = UserDefaults.standard
        var since = d.dictionary(forKey: "projectsSince") as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        guard let first = since[key] else {
            since[key] = now
            d.set(since, forKey: "projectsSince")
            return 0
        }
        let days = (now - first) / 86400
        return days > 60 ? 2 : days > 14 ? 1 : 0
    }

    /// Widget mode: only who needs you shows (the rest keeps swimming, hidden).
    var compact = false

    func isHidden(_ f: Fish) -> Bool {
        compact && !f.decor && ![.waiting, .error, .alert].contains(f.state)
    }

    // MARK: - interaction

    private var grabbed: Fish?
    private var grabFrom: SIMD2<Float> = .zero
    private var lastDrag: SIMD2<Float>?
    private var sprinkled: Float = 0

    /// A drag: on a fish, it's pulled along (a little); on the water, a short current that pushes the snow, the seaweed
    /// and the fish nearby.
    func drag(from a: SIMD2<Float>, to b: SIMD2<Float>) {
        if grabbed == nil && lastDrag == nil {
            if let f = fish(at: a) { grabbed = f; grabFrom = f.pos } else { lastDrag = a }
        }
        if let f = grabbed {
            // it follows the mouse, but only so far: pulled, not carried
            let d = b - grabFrom, l = simd_length(d)
            f.grabbedTo = grabFrom + (l > 90 ? d / l * 90 : d)
            f.glow = max(f.glow, 0.4)
            return
        }
        guard let last = lastDrag else { return }
        let flow = b - last
        guard simd_length(flow) > 2 else { return }
        lastDrag = b
        current += flow.x * 0.25                         // a nudge to the current (it fades by itself)
        motes.push(flow, at: b)
        for f in fish where !f.leaving && simd_distance(f.pos, b) < 120 { f.vel += flow * 1.6 }
        weeds.lean(self, with: flow, at: b)
        if Float.random(in: 0...1) < 0.35 { bubble(at: b, size: Float.random(in: 1.2...2.4)) }
    }

    func endDrag() {
        if let f = grabbed {
            f.grabbedTo = nil
            f.vel += (grabFrom - f.pos) * 0.8             // let go: it heads back where it was
        }
        grabbed = nil
        lastDrag = nil
    }

    /// A knock on the glass: a ring where it knocked; idle fish and the schools come to look.
    func knock(at p: SIMD2<Float>) {
        ring(at: p, color: [0.9, 0.97, 1], size: 8, grow: 110, life: 0.7)
        after(0.18) { [weak self] in self?.ring(at: p, color: [0.9, 0.97, 1], size: 6, grow: 90, life: 0.6) }
        for f in fish where !f.leaving && simd_distance(f.pos, p) < 500 {
            if f.decor && f.parent == nil && f.phase % 100 == 0 {
                f.wander = p + [Float.random(in: -60...60), Float.random(in: -40...40)]
                f.wanderAt = time + 4
            } else if !f.decor && (f.state == .idle || f.state == .ok || f.state == .done) {
                f.wander = p + [Float.random(in: -90...90), Float.random(in: -50...50)]
                f.wanderAt = time + 5
                if sleeping(f) { f.since = time - 60; f.awakeUntil = time + 1.8 }
            }
        }
    }

    /// Scrolling over the water sprinkles food from the surface above the mouse.
    func sprinkle(at p: SIMD2<Float>, amount: Float) {
        sprinkled += amount
        guard sprinkled > 8 else { return }
        sprinkled = 0
        for _ in 0..<2 {
            particles.append(Particle(pos: [p.x + Float.random(in: -14...14), surfaceY(p.x) - 6], vel: [0, -26], life: 0, maxLife: 12,
                                      size: 3, grow: 0, kind: 3, color: [0.75, 0.5, 0.28, 1]))
        }
        if Float.random(in: 0...1) < 0.3 { pendingArp += 1 }
    }

    func feed(at p: SIMD2<Float>) {
        motes.stir(self, at: p, radius: 150, strength: 70)
        for _ in 0..<8 {
            particles.append(Particle(pos: [p.x + Float.random(in: -25...25), p.y + Float.random(in: -8...8)], vel: [0, -26],
                                      life: 0, maxLife: 12, size: 3.2, grow: 0, kind: 3,
                                      color: [0.75, 0.5, 0.28, 1]))
        }
        pendingArp += 1
        onEvent?(p)
    }

    // MARK: - Visual effects synced with the sound

    func after(_ delay: Double, _ fn: @escaping () -> Void) {
        later.append((time + max(0, delay), fn))
        if later.count > 2000 { later.removeFirst(later.count - 2000) }
    }

    /// For the scene (Scene.swift), which lives in another file.
    func addParticle(_ p: Particle) { particles.append(p) }

    func ring(at p: SIMD2<Float>, color: SIMD3<Float>, size: Float = 14, grow: Float = 70, life: Float = 0.9) {
        particles.append(Particle(pos: p, vel: [0, 12], life: 0, maxLife: life, size: size, grow: grow, kind: 2,
                                  color: SIMD4(color, 1)))
    }

    func bubble(at p: SIMD2<Float>, size s: Float) {
        particles.append(Particle(pos: p, vel: [Float.random(in: -6...6), Float.random(in: 40...70)], life: 0,
                                  maxLife: 30, size: s, grow: 0, kind: 1, color: [0.8, 0.95, 1, 1]))
    }

    func burst(at p: SIMD2<Float>, n: Int) {
        for _ in 0..<n { bubble(at: p + SIMD2(Float.random(in: -14...14), Float.random(in: -8...8)), size: Float.random(in: 2.5...6)) }
    }

    func sparkle(at p: SIMD2<Float>, color: SIMD3<Float>) {
        particles.append(Particle(pos: p, vel: [0, 18], life: 0, maxLife: 0.7, size: 10, grow: 6, kind: 4,
                                  color: SIMD4(color, 1)))
    }

    var bubblerX: Float { size.x * 0.1 }

    /// Old battery in the sand (only shows up if some plugin sends the "battery" gauge).
    var battery: Float? { gauges["mac:battery"] }
    var pluggedIn: Bool { (gauges["mac:charging"] ?? 0) > 0.5 }
    /// Near the right end of the sand, at the closest spot the scenery leaves free.
    private var batteryU: Float { scenery.free(self, near: size.x * 0.8, room: 24) / max(1, size.x) }
    func sand(_ u: Float) -> Float { 0.075 + 0.018 * sinf(u * 7 + 1.3) + 0.008 * sinf(u * 23) }
    /// Resting on the terrain (same sand curve as the shader), about 40% buried.
    var batteryPos: SIMD2<Float> { [size.x * batteryU, size.y * sand(batteryU) + 2] }
    /// Slope of the sand at that point, plus a slight tilt.
    var batteryAngle: Float {
        let u = batteryU
        let deriv = 0.018 * 7 * cosf(u * 7 + 1.3) + 0.008 * 23 * cosf(u * 23)
        return atanf(deriv * size.y / max(1, size.x)) - 0.08
    }
    private var batteryBubbleAt: Double = 0

    // MARK: - Simulation

    /// The last frame's dt (for smoothing done while drawing).
    private(set) var frameDt: Float = 1 / 60

    func update(dt rawDt: Float) {
        let dt = min(rawDt, 0.05)
        frameDt = dt
        time = CACurrentMediaTime()
        runScheduled()
        bubbler()

        scene.update(self, dt: dt)
        weeds.update(self, dt: dt)
        let agents = Float(fish.filter { $0.isAgent && !$0.decor && !$0.leaving }.count)
        crowd += (max(0, min(1, (agents - 4) / 6)) - crowd) * min(1, dt * 0.5)
        if Int(time * 10) % 50 == 0 { gauges.expire() }
        breathe(dt: dt)
        scenery.update(self, dt: dt)
        pearls.layout(self)
        rainOnSurface()
        motes.update(self, dt: dt)

        drift(dt: dt)
        tickSessions(dt: dt)
        if Int(time) % 60 == 0 { pearls.rollDay() }

        fauna.update(self, dt: dt)
        // parallax: slowly follows the mouse; without a mouse, returns to center
        let gazeTarget: SIMD2<Float> = cursor.map { c in time - cursorAt < 6 ? (c / SIMD2(max(1, size.x), max(1, size.y))) * 2 - 1 : .zero } ?? .zero
        gaze += (gazeTarget - gaze) * min(1, dt * 1.5)

        chats()
        tag()
        blowRings()
        deliverMail(dt: dt)

        // forgotten sessions leave on their own after 2 h without news
        for f in fish where !f.decor && !f.leaving && time - f.seen > 7200 { f.leaving = true }

        let food = particles.indices.filter { particles[$0].kind == 3 }
        // queue at the glass in order of arrival
        let waiting = fish.filter { $0.state == .waiting && !$0.leaving && !$0.decor }.sorted { $0.since < $1.since }

        for f in fish { steer(f, dt: dt, food: food, waiting: waiting) }

        keepApart(dt: dt)
        eat(food: food)
        moveParticles(dt: dt)

        // plugged-in battery releases little bubbles
        if battery != nil && pluggedIn && time > batteryBubbleAt {
            bubble(at: batteryPos + SIMD2(Float.random(in: -10...10), 6), size: Float.random(in: 1...2))
            batteryBubbleAt = time + Double.random(in: 0.3...0.9)
        }

        // jellyfish
        jellyPhase += dt
        jellyPos = [size.x * 0.72 + sinf(jellyPhase * 0.11) * size.x * 0.12,
                    size.y * 0.62 + sinf(jellyPhase * 0.23) * size.y * 0.1]
        jellyGlow *= expf(-dt * 0.8)

        // turbidity from the disk (or any "disk" gauge)
        let disk = gauges.highest("disk") ?? 0
        let goal = smoothstep(0.85, 0.97, disk)
        turbidity += (goal - turbidity) * min(1, dt * 0.5)
    }

    /// What `after` put off until now.
    private func runScheduled() {
        // scheduled effects
        if !later.isEmpty {
            var keep: [(Double, () -> Void)] = []
            keep.reserveCapacity(later.count)
            for item in later {
                if item.0 <= time { item.1() } else { keep.append(item) }
            }
            later = keep
        }
    }

    /// The bubbler's stream, and now and then something special.
    private func bubbler() {
        // now and then the bubbler lets out something special: a bubble ring, or a big bubble that splits in two
        if shapedAt == 0 { shapedAt = time + Double.random(in: 15...30) * Self.scale }
        if time > shapedAt {
            shapedAt = time + Double.random(in: 25...50) * Self.scale
            if Bool.random() {
                particles.append(Particle(pos: [bubblerX, 60], vel: [0, 34], life: 0, maxLife: 5.5, size: 6, grow: 3.5, kind: 2,
                                          color: [0.85, 0.95, 1, 1]))
            } else {
                // alpha 0.99 marks it: it splits halfway up (in the particles' update)
                particles.append(Particle(pos: [bubblerX, 60], vel: [0, 46], life: 0, maxLife: 30, size: 7.5, grow: 0, kind: 1,
                                          color: [0.8, 0.95, 1, 0.99]))
            }
        }
        // bubbler bubbles
        if time > bubblerAt {
            bubble(at: [bubblerX + Float.random(in: -4...4), 50], size: Float.random(in: 1.5...3.5))
            bubblerAt = time + Double.random(in: 0.08...0.25)
        }
    }

    /// The current: from the CPU and from the music.
    private func drift(dt: Float) {
        // current: high CPU gently pushes everything to one side
        let cpu = gauges["mac:cpu"] ?? 0
        var currentTarget = smoothstep(0.55, 0.95, cpu) * 26 * (0.7 + 0.3 * sinf(Float(time) * 0.05))
        if time - musicCurrent.at < 0.5 { currentTarget += musicCurrent.value }
        current += (currentTarget - current) * min(1, dt * 0.3)
    }

    /// Each session's own clocks: its pace, what it's doing with a tool, sleeping, compacting, growing fat.
    private func tickSessions(dt: Float) {
        for f in fish where !f.decor {
            f.toolTimes.removeAll { time - $0 > 60 }
            if f.spin > 0 { f.spin = max(0, f.spin - dt * 1.1) }
            if f.action != nil && time > f.actionUntil { f.action = nil }
            if let a = f.action, time > f.actionEffectAt {
                let mouth = f.pos + facing(f) * f.size * 0.95
                switch a {
                case .nibble(let goal) where simd_distance(mouth, goal) < f.size * 0.9:
                    // bits of seaweed
                    f.actionEffectAt = time + 0.22
                    particles.append(Particle(pos: goal + SIMD2(Float.random(in: -4...4), Float.random(in: -4...4)),
                                              vel: [Float.random(in: -8...8), Float.random(in: -10...4)], life: 0,
                                              maxLife: Float.random(in: 1...1.8), size: Float.random(in: 3...5), grow: 0, kind: 4,
                                              color: [0.35, 0.75, 0.35, 1]))
                case .forage where f.pos.y - size.y * sand(f.pos.x / max(1, size.x)) < f.size * 1.4:
                    // puff of sand dust
                    f.actionEffectAt = time + 0.35
                    particles.append(Particle(pos: mouth + [0, -4], vel: [Float.random(in: -10...10), Float.random(in: 4...12)], life: 0,
                                              maxLife: 2, size: 9, grow: 9, kind: 10, color: [0.5, 0.43, 0.3, 1]))
                case .peek where f.pos.y > size.y * 0.9:
                    f.actionEffectAt = time + 0.9
                    ring(at: [f.pos.x + facing(f).x * f.size * 0.8, size.y * 0.965], color: [0.85, 0.95, 1], size: 6, grow: 50, life: 0.9)
                default:
                    break
                }
            }
            if let c0 = f.compactingSince {
                // compacting: slowly shrinks and releases a trail of bubbles
                if time - c0 > 240 { f.compactingSince = nil }
                f.fat = max(0, f.fat - dt * 0.04)
                if Float.random(in: 0...1) < dt * 6 {
                    bubble(at: f.pos + facing(f) * f.size * 0.4 + [Float.random(in: -6...6), f.size * 0.3], size: Float.random(in: 1.5...3.5))
                }
            } else if let c = f.context {
                f.fat += (c - f.fat) * min(1, dt * 0.25)
            }
            // lingering error: the water around gets murky
            if f.state == .error && time - f.since > 720 * Self.scale && time > f.inkAt {
                f.inkAt = time + 1.4
                ink(at: f.pos, n: 1, color: [0.12, 0.14, 0.08])
            }
            // fast pace: trail of bubbles
            if f.state == .busy && f.toolTimes.count > 8 && Float.random(in: 0...1) < dt * Float(f.toolTimes.count) * 0.08 {
                bubble(at: f.pos - facing(f) * f.size * 0.9, size: Float.random(in: 1.2...2.4))
            }
            // sleeping: zzz
            if sleeping(f) && time > f.zzzAt {
                f.zzzAt = time + Double.random(in: 1.6...3)
                bubble(at: f.pos + facing(f) * f.size * 0.5 + [0, 6], size: Float.random(in: 1.5...2.5))
            }
        }
    }

    /// Two idle fish from the same project meet now and then.
    private func chats() {
        // chats: two fish from the same project, idle and awake, meet snout to snout
        if time > nextChat {
            nextChat = time + Double.random(in: 25...50)
            let freeSlots = fish.filter { !$0.decor && !$0.leaving && $0.isAgent && ($0.state == .idle || $0.state == .ok) && !sleeping($0) && $0.chattingWith == nil }
            for a in freeSlots {
                if let b = freeSlots.first(where: { $0 !== a && $0.label == a.label && $0.source == a.source && $0.chattingWith == nil }) {
                    a.chattingWith = b.id; b.chattingWith = a.id
                    a.chatUntil = time + 6; b.chatUntil = time + 6
                    break
                }
            }
        }
        for f in fish where f.chattingWith != nil && time > f.chatUntil { f.chattingWith = nil }
    }

    /// At night, two idle fish play tag.
    private func tag() {
        // night-time tag among those idle and awake
        if let b = game, time > b.until { game = nil }
        if game == nil && light < 0.75 && time > nextGame {
            nextGame = time + Double.random(in: 70...140)
            let freeSlots = fish.filter { !$0.leaving && !sleeping($0) && ($0.decor ? $0.parent == nil && $0.phase % 100 != 0 : ($0.state == .idle || $0.state == .ok)) }
            if freeSlots.count >= 2 {
                let stopFn = freeSlots.shuffled().prefix(2)
                game = (stopFn.first!.id, stopFn.last!.id, time + 18)
            }
        }
        if let b = game, let p = fish.first(where: { $0.id == b.chaser }), let q = fish.first(where: { $0.id == b.runner }),
           simd_distance(p.pos, q.pos) < (p.size + q.size) * 0.7 {
            sparkle(at: (p.pos + q.pos) / 2, color: [1, 1, 0.8])
            game = (b.runner, b.chaser, b.until)          // tagged! swap
        }
    }

    /// Idle fish blow a bubble ring now and then.
    private func blowRings() {
        // bubble ring from the idle ones
        for f in fish where !f.decor && !f.leaving && (f.state == .idle || f.state == .ok) && !sleeping(f) && time > f.ringAt {
            if f.ringAt > 0 && Float.random(in: 0...1) < 0.6 {
                particles.append(Particle(pos: f.pos + facing(f) * f.size * 0.9, vel: [0, 22], life: 0, maxLife: 3.2, size: 4, grow: 7,
                                          kind: 2, color: [0.85, 0.95, 1, 1]))
            }
            f.ringAt = time + Double.random(in: 18...45)
        }
    }

    /// The seahorses carrying mail (MCP calls) to their fish and back.
    private func deliverMail(dt: Float) {
        // mail seahorses
        for i in mails.indices {
            mails[i].phase += dt
            let goal = fish.first { $0.id == mails[i].goal && !$0.leaving }
            switch mails[i].stage {
            case 0:
                guard let f = goal else { mails[i].stage = 2; break }
                let d = f.pos - mails[i].pos
                if simd_length(d) < f.size * 1.7 { mails[i].stage = 1; mails[i].since = time }
                else { mails[i].pos += simd_normalize(d) * 120 * dt }
            case 1:
                if mails[i].letter && time - mails[i].since > 0.5 {
                    mails[i].letter = false
                    if let f = goal { sparkle(at: (f.pos + mails[i].pos) / 2, color: mails[i].color); f.glow = 0.7 }
                }
                if time - mails[i].since > 1.4 { mails[i].stage = 2 }
            default:
                mails[i].pos.x += mails[i].side * 100 * dt
            }
            mails[i].pos.y += sinf(mails[i].phase * 2.2) * 6 * dt
        }
        mails.removeAll { $0.stage == 2 && ($0.pos.x < -60 || $0.pos.x > size.x + 60) }
    }

    /// Fish don't swim through each other.
    private func keepApart(dt: Float) {
        // separation
        for i in fish.indices {
            for j in fish.indices where j > i {
                let a = fish[i], b = fish[j]
                let d = a.pos - b.pos
                let minD = (a.decor || b.decor) ? (a.size + b.size) * 0.9 : (a.size + b.size) * 1.6
                let l = simd_length(d)
                if l < minD && l > 0.01 {
                    let push = d / l * (minD - l) * 0.5 * min(1, dt * 8)
                    a.pos += push; b.pos -= push
                }
            }
        }
    }

    /// Whoever reaches a bit of food eats it.
    private func eat(food: [Int]) {
        // eating
        if !food.isEmpty {
            var eaten = Set<Int>()
            for f in fish where !f.decor {
                for idx in food where !eaten.contains(idx) {
                    if simd_distance(particles[idx].pos, f.pos + facing(f) * f.size * 0.6) < f.size * 0.5 {
                        eaten.insert(idx)
                        sparkle(at: particles[idx].pos, color: f.color)
                        f.glow = max(f.glow, 0.6)
                        // a gulp: swells for a moment and lets out a little bubble
                        f.scale = max(f.scale, 1.16)
                        bubble(at: f.pos + facing(f) * f.size * 0.8, size: 1.6)
                    }
                }
            }
            if !eaten.isEmpty {
                particles = particles.enumerated().filter { !eaten.contains($0.offset) }.map(\.element)
            }
        }

        fish.removeAll { f in
            f.leaving && (f.pos.x < -80 || f.pos.x > size.x + 80 || f.pos.y > size.y + 70)
        }
    }

    /// Bubbles, rings, food, sparks and ink: they move, fade, split and pop at the surface.
    private func moveParticles(dt: Float) {
        // particles
        for i in particles.indices {
            particles[i].life += dt
            var p = particles[i]
            switch p.kind {
            case 1:
                p.vel.x += Float.random(in: -30...30) * dt
                p.vel.x *= 0.98
                if p.size < 7 { p.size += dt * 0.18 }          // the pressure drops as it rises: it grows a little
            case 3:
                p.vel.x = sinf(Float(time) * 1.3 + p.pos.y * 0.05) * 8
                if p.pos.y < 46 { p.vel = .zero }
            case 10:
                p.vel *= expf(-dt * 0.7)
            case 24:
                p.vel.x = sinf(Float(time) * 2.2 + p.pos.y * 0.04) * 12      // notes sway as they rise
            default: break
            }
            p.pos += p.vel * dt
            if p.kind == 1 || p.kind == 10 { p.pos.x += current * dt * 0.6 }
            p.size += p.grow * dt
            particles[i] = p
        }
        // the big bubble splits in two halfway up
        var splits: [SIMD2<Float>] = []
        for i in particles.indices where particles[i].kind == 1 && particles[i].color.w < 0.995 && particles[i].pos.y > size.y * 0.55 {
            splits.append(particles[i].pos)
            particles[i].life = particles[i].maxLife + 1
        }
        for p in splits {
            for side: Float in [-1, 1] {
                particles.append(Particle(pos: p + [side * 3, 0], vel: [side * 26, 40], life: 0, maxLife: 30, size: 4.6, grow: 0, kind: 1,
                                          color: [0.8, 0.95, 1, 1]))
            }
        }
        // a bubble reaching the surface pops: a little ring spreads on the water
        var pops: [SIMD2<Float>] = []
        particles.removeAll { p in
            guard p.kind == 1, p.pos.y > surfaceY(p.pos.x) - 2 else { return p.life > p.maxLife }
            if p.size > 2.2 && pops.count < 6 && Float.random(in: 0...1) < 0.6 { pops.append([p.pos.x, surfaceY(p.pos.x)]) }
            return true
        }
        for p in pops {
            particles.append(Particle(pos: p, vel: .zero, life: 0, maxLife: 1.1, size: 4, grow: 26, kind: 8, color: [0.85, 0.95, 1, 1]))
        }
        if particles.count > 3000 { particles.removeFirst(particles.count - 3000) }
    }

    /// Idle for more than 10 min: lies on the sand and sleeps.
    func sleeping(_ f: Fish) -> Bool {
        !f.decor && !f.leaving && (f.state == .idle || f.state == .done || f.state == .ok)
            && (f.isAgent || f.source == "test") && time - f.since > 600 * Self.scale
    }

    private func facing(_ f: Fish) -> SIMD2<Float> {
        let l = simd_length(f.vel)
        return l > 0.01 ? f.vel / l : [1, 0]
    }
}
