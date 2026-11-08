import Foundation
import QuartzCore
import simd

/// Closed vocabulary of protocol states (+ "end", which takes the entity out of the tank).
enum State: String, CaseIterable {
    case born, busy, idle, waiting, ok, alert, error, done

    /// The original Portuguese names, still accepted on the wire and in saved settings.
    static let legacy: [String: State] = [
        "nasceu": .born, "ocupado": .busy, "ocioso": .idle, "esperando": .waiting,
        "alerta": .alert, "erro": .error, "terminou": .done,
    ]

    /// Parses a state from the protocol: the current name or the legacy one.
    init?(wire s: String) {
        guard let v = State(rawValue: s) ?? State.legacy[s] else { return nil }
        self = v
    }

    /// "end" (or the legacy "fim") takes the entity out of the tank.
    static func isEnd(_ s: String) -> Bool { s == "end" || s == "fim" }

    var label: String {
        switch self {
        case .born: return tr("chegou")
        case .busy: return tr("trabalhando")
        case .idle: return tr("parado")
        case .waiting: return tr("✋ esperando você")
        case .ok: return "ok"
        case .alert: return tr("⚠︎ alerta")
        case .error: return tr("✗ erro")
        case .done: return tr("✓ terminou")
        }
    }
}

/// What the fish is doing because of a tool.
enum Action: Equatable {
    case nibble(SIMD2<Float>)   // Edit/Write: nibbles the seaweed
    case bubbles                    // Bash: puff of bubbles
    case forage                     // Read/Grep/Glob: forages in the sand
    case peek                    // WebFetch/WebSearch: peeks at the surface
    case mail                   // MCP: goes to meet the seahorse

    func sameKind(_ o: Action) -> Bool {
        switch (self, o) {
        case (.nibble, .nibble), (.bubbles, .bubbles), (.forage, .forage), (.peek, .peek), (.mail, .mail): return true
        default: return false
        }
    }
}

/// What a source's fish are like. Session providers describe their sources (Providers.swift); a source nobody
/// describes gets a plain fish. The screen saver gets these values from the app's /state instead.
struct SourceProfile {
    /// Agent sessions earn pearls, sleep, animate with tools and can be replied to.
    var isAgent = false
    var timbre: Timbre?
    /// Show the conversation name from the log before the live terminal title.
    var prefersLogTitle = false
    /// The fish kind's id (see FishKinds), which may depend on where the session runs.
    var fishKind: (Fish) -> String = { _ in "oval" }
    /// A singer (the music that's playing): while busy it dances near the top and lets out notes; idle, it fades and sinks.
    var sings = false

    func apply(to f: Fish) {
        f.isAgent = isAgent
        f.sings = sings
        f.prefersLogTitle = prefersLogTitle
        f.species = FishKinds.index(of: FishKinds.override(for: f.projectKey) ?? fishKind(f))
    }
}

final class Fish {
    let id: String
    let source: String
    var label: String
    var state: State = .born
    var since: Double
    var seen: Double
    var pos: SIMD2<Float>
    var vel: SIMD2<Float> = .zero
    let baseSize: Float
    var scale: Float = 1
    let color: SIMD3<Float>
    let stripes: Bool
    var motif: Int
    let timbre: Timbre
    let phase: Int
    let decor: Bool
    var glow: Float = 0
    var tail: Float = 0
    var wander: SIMD2<Float> = .zero
    var wanderAt: Double = 0
    var leaving = false
    var intro = true
    var resolve = false
    var ticks: [Timbre] = []
    var tickIdx = 0
    var lastTick = -1000
    /// Changed state and hasn't played the cue for it yet.
    var changed = false
    var reminder: Double = 0
    var step = 0
    var tool: String?
    var shake: Float = 0
    /// Where the thing is (terminal, Rex session…), so a click can take you there.
    var whereabouts: [String: String] = [:]
    /// Link to open on click (e.g. the build page).
    var link: String?
    /// Second line of the label: session, tab or terminal name.
    var sub: String?
    /// Terminal title (Claude Code puts the conversation topic there).
    var title: String?
    /// From Claude's transcript: conversation title and branch (works for any terminal).
    var logTitle: String?
    var branch: String?
    var transcriptReadAt: Double = 0
    /// Fry of a subagent: follows its parent.
    weak var parent: Fish?
    /// Leaving with a party (merged PR): rises and exits through the surface.
    var party = false
    /// A lingering error has already notified (urgent).
    var escalated = false
    /// Little spin when it recovers (1 → 0).
    var spin: Float = 0
    /// Tools from the last minute (pace).
    var toolTimes: [Double] = []
    var inkAt: Double = 0
    /// Context used by the session (0…1 of the limit), read from the transcript; the fish fattens with it.
    var context: Float?
    var fat: Float = 0
    var action: Action?
    var actionSince: Double = 0
    var actionUntil: Double = 0
    var actionEffectAt: Double = 0
    var actionSide: Float = 1
    /// For the dots and the hover card.
    let createdAt = Date()
    var history: [(when: Date, name: String)] = []      // latest tools
    var finished: [(when: Date, title: String)] = []   // finished tasks
    var lastError: Date?
    /// Depth (0 near … 1 far): far away is smaller, bluer and behind.
    var depth: Float = 0
    /// Pattern (0 plain, 1 stripes, 2 spots, 3 gradient, 4 scales, 5 mask) and cut (0 normal, 1 veil tail,
    /// 2 tall dorsal, 3 long fins): fixed per project, so each one has its own look.
    var pattern = 0
    var cut = 0
    // animations
    var jumpPhase = 0                 // 0 none, 1 rising, 2 in the air
    var jumpT0: Double = 0
    var jumpX0: Float = 0
    var jumpDir: Float = 1
    var workingSince: Double?
    var toolSinceStart = 0
    var fearUntil: Double = 0
    var fearFrom: SIMD2<Float> = .zero
    var awakeUntil: Double = 0
    /// A decorative fish's own depth; the schools step back from it when the tank is crowded.
    var restDepth: Float = 0
    /// Where the eye looks (world direction, smoothed): the cursor nearby, or the nearest food.
    var look: SIMD2<Float> = .zero
    var chattingWith: String?
    var chatUntil: Double = 0
    var ringAt: Double = 0
    /// What just happened, for the minimal label to show for a few seconds.
    var moment: (text: String, until: Double)?
    /// Its own way of saying how it is, in place of the state's name (the music fish: "🎶 na vibe" rather than "working").
    var mood: String?
    var stateLabel: String { mood ?? state.label }
    /// How far along it is (seconds), for the card's bar: the music fish's song.
    var progress: (() -> (pos: Double, dur: Double, playing: Bool)?)?
    /// The agent's last reply (clean text, no markdown), for the card.
    var lastReply: String?
    /// The reply ended with a question for you (the final part).
    var asked: String?
    /// TodoWrite: the list becomes pebbles in the sand (the done ones glow in the fish's color).
    var todos: (total: Int, done: Int)?
    var todoU: Float?
    /// Compacting the conversation (from PreCompact until the compact SessionStart).
    var compactingSince: Double?
    var zzzAt: Double = 0
    /// Which way it faces, -1…1: it doesn't flip at once, it turns through 0 (squeezed sideways, as if seen mid-turn).
    var facingX: Float = 1
    /// Smoothed tilt (nose up/down), so turns and climbs bend instead of snapping.
    var lean: Float = 0
    /// Speed in the last frame (for the push of the tail when it accelerates).
    var lastSpeed: Float = 0
    /// The fish kind, as an index into `FishKinds.all` (that's what the shader gets). Set from the source's profile
    /// (see `SourceProfile`) or the project's choice in the fish menu.
    var species = 0
    var kindID: String { FishKinds.id(at: species) }

    /// 0 for a project's first session, 1, 2… for the others (same motif, different hue and size).
    var variant = 0

    /// Nickname you gave the fish (stored in the app, per session).
    var nickname: String? {
        get { (UserDefaults.standard.dictionary(forKey: "nicknames") as? [String: String])?[id] }
        set {
            var d = UserDefaults.standard.dictionary(forKey: "nicknames") as? [String: String] ?? [:]
            d[id] = newValue.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
            UserDefaults.standard.set(d, forKey: "nicknames")
        }
    }

    /// The title to show: the conversation name from the log (e.g. Codex's thread_name) or the live terminal title,
    /// whichever the source prefers.
    var displayTitle: String? { fixedTitle ?? (prefersLogTitle ? (logTitle ?? title) : (title ?? logTitle)) }
    /// The conversation file (Claude Code, Codex), to remember the session across restarts.
    var transcriptPath: String?
    var prefersLogTitle = false
    /// Name given to the conversation (Claude's /rename, the tank's rename): takes precedence over automatic titles.
    var fixedTitle: String?

    /// Agent session (Claude Code, Codex, demo): earns pearls, sleeps, animates with tools. Set from the source's profile.
    var isAgent = false
    /// The music fish (see SourceProfile.sings).
    var sings = false
    var noteAt: Double = 0

    /// Sound identity: the motif is stored under this key.
    var projectKey: String { "\(source):\(label)" }

    init(id: String, source: String, label: String, pos: SIMD2<Float>, size: Float, color: SIMD3<Float>,
         stripes: Bool, motif: Int, timbre: Timbre, phase: Int, decor: Bool, now: Double) {
        self.id = id; self.source = source; self.label = label; self.pos = pos; self.baseSize = size
        self.color = color; self.stripes = stripes; self.motif = motif; self.timbre = timbre
        self.phase = phase; self.decor = decor; self.since = now; self.seen = now; self.bornAt = now
    }

    /// When it arrived in the tank (a long session ages: longer fins, more marked scales).
    var bornAt: Double
    /// Being pulled by the mouse: where it's pulled to.
    var grabbedTo: SIMD2<Float>?
    /// How old its project is in the tank: 0 new, 1 over two weeks (a little scar), 2 over two months (gold-edged fins).
    var veteran = 0

    var size: Float { baseSize * scale }
}

struct Particle {
    var pos: SIMD2<Float>
    var vel: SIMD2<Float>
    var life: Float
    var maxLife: Float
    var size: Float
    var grow: Float
    var kind: Float   // 1 bubble, 2 ring, 3 food, 4 sparkle, 24 music note
    var color: SIMD4<Float>
}

/// The world: fish, particles and gauges. Everything runs on the main thread.
final class Tank {
    var size: SIMD2<Float> = [960, 600]
    private(set) var fish: [Fish] = []
    private(set) var particles: [Particle] = []
    private(set) var gauges: [String: Float] = [:]
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
    private var cursorRestingAt: Double = 0
    /// Night-time tag: who chases, who runs, until when.
    private var game: (chaser: String, runner: String, until: Double)?
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
    private var focusCenter: SIMD2<Float> = .zero
    /// Summary parade: the highlighted fish comes to the front of the glass.
    var highlighted: String?
    private var jellyPos: SIMD2<Float> = [700, 380]
    private var jellyPhase: Float = 0
    private var later: [(Double, () -> Void)] = []
    private var bubblerAt: Double = 0
    private(set) var time: Double = CACurrentMediaTime()

    /// Pearls of the day: each finished task leaves one on the bottom (they vanish when the day changes).
    struct Pearl: Codable {
        var u: Float
        var color: [Float]
        var title: String
        var project: String
        var hour: Double
    }
    private(set) var pearls: [Pearl] = []
    private var pearlsDay = ""
    private var bornAt: [Double] = []        // new-pearl glow (this run only)
    var keepPearls = true                   // the screensaver doesn't save
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

    init() {
        loadPearls()
        // decorative schools (no sound, no label), so the tank is alive even with few sessions. The phase says the school
        // (phase / 100) and the place in it (phase % 100 == 0: the leader): blue neons in the middle, orange tetras up high,
        // silversides deep in the back (slender, blurred by the distance)
        let schools: [(n: Int, size: ClosedRange<Float>, color: SIMD3<Float>, pattern: Int, depth: ClosedRange<Float>, kind: String)] = [
            (10, 9.5...11, [0.35, 0.75, 1.0], 1, 0.2...0.6, "oval"),
            (8, 8...9.5, [1.0, 0.62, 0.25], 3, 0.25...0.5, "oval"),
            (6, 14...17, [0.72, 0.8, 0.88], 0, 0.6...0.8, "slender"),
        ]
        for (s, sc) in schools.enumerated() {
            for i in 0..<sc.n {
                let f = Fish(id: "decor:\(s * 100 + i)", source: "decor", label: "",
                             pos: [Float.random(in: 200...700), Float.random(in: 250...450)], size: Float.random(in: sc.size),
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
                stir(at: p, radius: 60, strength: 14)
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
        stir(at: p, radius: 170, strength: 90)
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
                    pearl(color: f.color, title: f.displayTitle ?? f.label, project: f.label)
                }
            }
            if state == .error {
                f.shake = 1
                if f.kindID == "octopus" { ink(at: f.pos, n: 7, color: [0.06, 0.03, 0.1]) }   // the octopus releases ink
            }
            if before == .error && state != .error { f.spin = 1 }                       // recovered: does a little spin
            if state != .busy { f.tool = nil }
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

    private static let pearlsKey = "pearls"
    private static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    private func loadPearls() {
        pearlsDay = Self.today()
        guard let d = UserDefaults.standard.data(forKey: Self.pearlsKey),
              let saved = try? JSONDecoder().decode([String: [Pearl]].self, from: d) else { return }
        pearls = saved[pearlsDay] ?? []
        bornAt = pearls.map { _ in 0 }
    }

    private func savePearls() {
        guard keepPearls, let d = try? JSONEncoder().encode([pearlsDay: pearls]) else { return }
        UserDefaults.standard.set(d, forKey: Self.pearlsKey)
    }

    func pearl(color: SIMD3<Float>, title: String, project: String) {
        if Self.today() != pearlsDay { pearls = []; bornAt = []; pearlsDay = Self.today() }
        guard pearls.count < 80 else { return }
        // scattered over the sand, away from the battery and the bubbler
        var u = Float.random(in: 0.16...0.74)
        for _ in 0..<8 where pearls.contains(where: { abs($0.u - u) < 0.012 }) { u = Float.random(in: 0.16...0.74) }
        pearls.append(Pearl(u: u, color: [color.x, color.y, color.z], title: title, project: project, hour: Date().timeIntervalSince1970))
        bornAt.append(time)
        savePearls()
    }

    /// The pearls of a period light up one after another.
    func highlightPearls(since: Date, until: Date) {
        var k = 0
        for (i, p) in pearls.enumerated() where p.hour >= since.timeIntervalSince1970 && p.hour <= until.timeIntervalSince1970 {
            let delay = Double(k) * 0.35
            k += 1
            after(delay) { [weak self] in
                guard let self, i < self.bornAt.count else { return }
                self.bornAt[i] = self.time
                self.sparkle(at: self.pearlPos(self.pearls[i]) + [0, 6], color: [1, 0.95, 0.8])
            }
        }
    }

    /// The day's pearls are a timeline on the sand: from the left (the first one, or 8:00) to the right (now),
    /// sliding left slowly as the day goes on. Pearls close in time pile up a little.
    func pearlPos(_ p: Pearl) -> SIMD2<Float> {
        if let i = pearls.firstIndex(where: { $0.hour == p.hour && $0.title == p.title }), i < timeline.count { return timeline[i] }
        return [size.x * p.u, size.y * sand(p.u) + 4]
    }

    private var timeline: [SIMD2<Float>] = []

    private func layoutTimeline() {
        let now = Date().timeIntervalSince1970
        let eight = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())?.timeIntervalSince1970 ?? now - 4 * 3600
        let t0 = min(pearls.map(\.hour).min() ?? eight, eight)
        let t1 = max(now, t0 + 4 * 3600)
        var out = [SIMD2<Float>](repeating: .zero, count: pearls.count)
        // pearls close in time gather in a little heap (the first ones at the bottom), clear of the rocks and the chest
        var heaps: [(x: Float, members: [Int])] = []
        var lastX: Float = -100
        for i in pearls.indices.sorted(by: { pearls[$0].hour < pearls[$1].hour }) {
            let x = size.x * (0.06 + 0.88 * Float((pearls[i].hour - t0) / (t1 - t0)))
            if x - lastX < 9, !heaps.isEmpty { heaps[heaps.count - 1].members.append(i) } else { heaps.append((x, [i])) }
            lastX = x
        }
        let gap: Float = 8
        for h in heaps {
            var b = 1
            while b * (b + 1) / 2 < h.members.count { b += 1 }      // the bottom row of a heap that holds them all
            let x0 = clearOfScenery(h.x + Float(b - 1) * gap / 2) - Float(b - 1) * gap / 2
            var k = 0
            for row in 0..<b {
                for col in 0..<(b - row) where k < h.members.count {
                    let x = x0 + (Float(col) + Float(row) * 0.5) * gap
                    out[h.members[k]] = [x, size.y * sand(x / max(1, size.x)) + 4 + Float(row) * gap * 0.8]
                    k += 1
                }
            }
        }
        timeline = out
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

    /// The chest under the point (clicking it opens the summary of the last hours).
    func chest(at p: SIMD2<Float>) -> Bool {
        guard let s = scenery.first(where: { $0.id == "chest" }) else { return false }
        let (c, sz) = place(s)
        return abs(p.x - c.x) < sz * 0.95 && p.y > c.y - sz * 0.75 && p.y < c.y + sz * 0.55
    }

    /// A spot on the sand moved out of the scenery's way (pearls and pebbles would float in front of a rock or the chest).
    func clearOfScenery(_ x: Float) -> Float {
        for s in sandScenery {
            let (c, sz) = place(s)
            let half = sz * 1.35 + 8
            if abs(x - c.x) < half { return c.x + (x < c.x ? -half : half) }
        }
        return x
    }

    /// The pearl under the point (to show its title).
    func pearl(at q: SIMD2<Float>) -> Pearl? {
        pearls.min { simd_distance(pearlPos($0), q) < simd_distance(pearlPos($1), q) }
            .flatMap { simd_distance(pearlPos($0), q) < 12 ? $0 : nil }
    }

    func tool(source: String, entity: String, name: String) {
        guard let f = fish.first(where: { $0.id == id(source, entity) }) else { return }
        f.tool = name
        f.seen = time
        f.toolTimes.append(time)
        f.history.append((Date(), name))
        f.moment = (ToolBehaviors.of(name).label(name), time + 4)
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

    /// Scenery on the sand that the fish swim around: rocks, a big shell, a chest, corals (the theme picks which).
    struct SceneryItem {
        let id: String           // "rock", "shell", "chest"
        let kind: Float          // sprite kind (21 rock, 22 shell, 23 chest)
        let u: Float             // x position, 0…1
        let scale: Float         // size, as a fraction of the height
        let color: SIMD3<Float>
        let seed: Float
        /// From a pack: its index in SceneryKinds (the sprite is kind 35).
        var pack: Int? = nil
        var anchor: SceneryKind.Anchor = .sand
        var extent: SIMD2<Float> = [1, 1]
        var height: Float = 0.5
        var drift = false
        var solid = true
        var glowAtNight = false
    }
    static let allScenery: [SceneryItem] = [
        SceneryItem(id: "rock", kind: 21, u: 0.17, scale: 0.075, color: [0.42, 0.4, 0.36], seed: 0.3),
        SceneryItem(id: "rock", kind: 21, u: 0.235, scale: 0.042, color: [0.36, 0.38, 0.41], seed: 1.7),
        SceneryItem(id: "chest", kind: 23, u: 0.335, scale: 0.06, color: [0.5, 0.31, 0.16], seed: 0),
        SceneryItem(id: "shell", kind: 22, u: 0.66, scale: 0.04, color: [0.66, 0.6, 0.56], seed: 0),   // the oyster
        SceneryItem(id: "rock", kind: 21, u: 0.8, scale: 0.058, color: [0.4, 0.37, 0.35], seed: 2.9),
        // corals (seed: 0 branching, 1 sea fan, 2 brain), muted by the water
        SceneryItem(id: "coral", kind: 34, u: 0.47, scale: 0.085, color: [0.95, 0.45, 0.55], seed: 0.2),
        SceneryItem(id: "coral", kind: 34, u: 0.565, scale: 0.05, color: [0.62, 0.5, 0.85], seed: 2.6),
        SceneryItem(id: "coral", kind: 34, u: 0.735, scale: 0.06, color: [0.35, 0.78, 0.75], seed: 0.8),
        SceneryItem(id: "coral", kind: 34, u: 0.905, scale: 0.1, color: [0.98, 0.58, 0.3], seed: 1.4),
    ]
    /// The theme's list (nil: all the built-in scenery; a pack's scenery only shows up where a theme lists it).
    var sceneryKinds: [String]? = nil { didSet { scenery = Self.scenery(for: sceneryKinds) } }
    private(set) var scenery: [SceneryItem] = Tank.scenery(for: nil)

    private static func scenery(for ids: [String]?) -> [SceneryItem] {
        var out = allScenery.filter { ids?.contains($0.id) ?? true }
        for (i, k) in SceneryKinds.all.enumerated() where ids?.contains(k.id) == true {
            for (j, u) in k.at.enumerated() {
                out.append(SceneryItem(id: k.id, kind: 35, u: u, scale: k.size, color: k.color,
                                       seed: Float(j) * 0.618 - floor(Float(j) * 0.618) + 0.05, pack: i, anchor: k.anchor,
                                       extent: k.extent, height: k.height, drift: k.drift, solid: k.solid, glowAtNight: k.glowAtNight))
            }
        }
        return out
    }
    /// Scenery on the sand (what crabs, pearls and pebbles keep clear of).
    private var sandScenery: [SceneryItem] { scenery.filter { $0.anchor == .sand } }
    private var chestBubblesAt: Double = 0

    /// Where an item sits and how much room the fish give it.
    func place(_ s: SceneryItem) -> (center: SIMD2<Float>, size: Float) {
        let sz = s.scale * size.y
        switch s.anchor {
        case .sand:
            // a pack's piece stands on the sand with the bottom of its drawing (c.y = -1) a little buried
            return ([s.u * size.x, size.y * sand(s.u) + (s.pack != nil ? sz * s.extent.y * 0.9 : sz * 0.3)], sz)
        case .surface:
            // floating: drifting slowly back and forth, riding the waves
            let x = s.u * size.x + (s.drift ? sinf(Float(time) * 0.035 + s.seed * 6.3) * size.x * 0.03 : 0)
            return ([x, surfaceY(x) - sz * 0.12], sz)
        case .float:
            return ([s.u * size.x, size.y * s.height + sinf(Float(time) * 0.5 + s.seed * 6.3) * 3], sz)
        }
    }
    /// The stretch of sand an item takes (for the crabs, who turn around instead of walking over it).
    func sceneryBlocks(_ x: Float) -> Bool {
        sandScenery.contains { s in let (c, sz) = place(s); return abs(x - c.x) < sz * 1.25 }
    }

    /// How many seaweeds the theme draws (the shader uses the same formula for their positions).
    var weedCount = 9 { didSet { weeds = Self.weeds(weedCount) } }

    /// Seaweed bending away from whoever swims through it (springs), for the shader with the blades' positions.
    private var weedBend = [Float](repeating: 0, count: 16)
    private var weedBendVel = [Float](repeating: 0, count: 16)

    func weedUniforms() -> [SIMD4<Float>] {
        (0..<16).map { k in k < weeds.count ? SIMD4(weeds[k].x, weeds[k].h, weedBend[k], Float(Self.weedKind(k))) : .zero }
    }

    /// Each blade's kind: 0 thin blade, 1 kelp, 2 leafy stem (mixed, so neighbors differ).
    static func weedKind(_ k: Int) -> Int { [0, 1, 2, 0, 2, 1, 0, 2, 1, 0, 1, 2, 0, 2, 0, 1][k % 16] }

    private var oxygenAt: Double = 0
    private var pearlGlintAt: Double = 0
    private var shapedAt: Double = 0
    /// How full of sessions the tank is (0: four or fewer, 1: ten or more), smoothed.
    private var crowd: Float = 0

    /// The treasure chest opens while the summary is open (the app sets it); the lid follows with a little spring.
    var chestOpen = false
    private(set) var chestLid: Float = 0
    private var chestLidVel: Float = 0
    private var chestSparkAt: Double = 0

    private func updateChest(dt: Float) {
        let goal: Float = chestOpen ? 1 : 0
        chestLidVel += ((goal - chestLid) * 40 - chestLidVel * 7) * dt
        chestLid = max(0, min(1.08, chestLid + chestLidVel * dt))
        guard chestLid > 0.5, time > chestSparkAt, let s = scenery.first(where: { $0.id == "chest" }) else { return }
        chestSparkAt = time + Double.random(in: 0.12...0.3)
        let (c, sz) = place(s)
        let p = c + [Float.random(in: -sz * 0.5...sz * 0.5), sz * 0.25]
        particles.append(Particle(pos: p, vel: [Float.random(in: -8...8), Float.random(in: 18...34)], life: 0, maxLife: Float.random(in: 1...1.8),
                                  size: Float.random(in: 4...7), grow: 1, kind: 4, color: [1, 0.82, 0.4, 1]))
        if Float.random(in: 0...1) < 0.3 { bubble(at: p, size: Float.random(in: 1.5...2.6)) }
    }

    /// A session's age (0…1 over six hours) plus 2 × its project's veteran level, for the shader (aux.w).
    private func aging(_ f: Fish) -> Float {
        guard f.isAgent && !f.decor else { return 0 }
        let age = min(0.999, Float((time - f.bornAt) / (6 * 3600 * Self.scale)))
        return age + Float(f.veteran) * 2
    }

    /// Fish swim in bursts and glides: a few strong strokes, then coasting. Averages 1, so the pace stays the same.
    private func burst(_ f: Fish) -> Float {
        let s = 0.5 + 0.5 * sinf(Float(time) * (0.8 + Float(f.phase % 5) * 0.07) + Float(f.phase) * 1.7)
        return (0.55 + 0.9 * s * s * s) * 1.2
    }

    /// By day, the seaweed lets out little oxygen bubbles now and then; still fish breathe out a bubble.
    private func breathe(dt: Float) {
        if light > 0.8, time > oxygenAt, !weeds.isEmpty {
            oxygenAt = time + Double.random(in: 1.2...3.5)
            let wd = weeds[Int.random(in: 0..<weeds.count)]
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
            let x = clearOfScenery(size.x * p.u), at: SIMD2<Float> = [x, size.y * sand(x / max(1, size.x)) + p.size * 0.6]
            if rayLight(at) > 0.06 { sparkle(at: at, color: [1, 0.96, 0.85]) }
        }
        // by day a pearl on the sand catches the light now and then
        if light > 0.8, time > pearlGlintAt, let p = pearls.randomElement() {
            pearlGlintAt = time + Double.random(in: 2.5...6)
            sparkle(at: pearlPos(p) + [1.5, 3], color: [1, 0.97, 0.9])
        }
        for f in fish where !f.decor && !f.leaving && (f.state == .idle || f.state == .ok) && !sleeping(f)
            && simd_length(f.vel) < 25 && Float.random(in: 0...1) < dt * 0.06 {
            bubble(at: f.pos + facing(f) * f.size * 0.9 + [0, 2], size: Float.random(in: 1.4...2.4))
        }
    }

    private func updateWeeds(dt: Float) {
        // what pushes: the fish and the presences that swim (position, size)
        var pushers: [(SIMD2<Float>, Float)] = fish.filter { !$0.leaving }.map { ($0.pos, $0.size * (1 - 0.35 * $0.depth)) }
        for p in scene.presences where !p.leaving && [.swim, .drift, .hover].contains(p.kind.motion) { pushers.append((p.pos, p.kind.size * 0.8)) }
        for k in weeds.indices where k < 16 {
            let x = weeds[k].x * size.x
            let base = size.y * sand(weeds[k].x)
            let top = base + weeds[k].h * size.y
            var target: Float = 0
            for (pos, r0) in pushers where pos.y > base - 10 && pos.y < top + r0 {
                let dx = x - pos.x, r = r0 * 1.3 + 10
                guard abs(dx) < r * 2.5 else { continue }
                // away from it, more the closer it is; the push is in widths (the shader's unit)
                target += (dx >= 0 ? 1 : -1) * expf(-(dx * dx) / (r * r)) * r0 * 0.9 / max(1, size.x)
            }
            // a current made by dragging through the water: the seaweed nearby leans with it
            if let fp = flowPush, time - fp.when < 0.6 {
                let dx = x - fp.at.x, r: Float = 140
                target += fp.flow.x / max(1, size.x) * 1.5 * expf(-(dx * dx) / (r * r)) * Float(1 - (time - fp.when) / 0.6)
            }
            // the whale passing in the distance: a slow pressure wave sways the seaweed it goes by
            if let wp = fauna.whalePosition {
                let dx = x - wp.x, r = size.x * 0.25
                target += (dx >= 0 ? 1 : -1) * expf(-(dx * dx) / (r * r)) * 0.022 * sinf(Float(time) * 0.9)
            }
            target = max(-0.05, min(0.05, target))
            weedBendVel[k] += ((target - weedBend[k]) * 30 - weedBendVel[k] * 5) * dt
            weedBend[k] += weedBendVel[k] * dt
        }
    }

    /// Marine snow: specks drifting down at different depths (far ones behind the fish, near ones in front).
    private struct Mote { var pos: SIMD2<Float>; var depth: Float; var size: Float; var phase: Float; var speed: Float; var vel: SIMD2<Float> = .zero }

    /// Pushes the marine snow away from a point (a click, the mouse, a quake). At night the plankton lights up.
    func stir(at p: SIMD2<Float>, radius r: Float, strength: Float) {
        var lit = 0
        for i in motes.indices {
            let d = motes[i].pos - p, l = simd_length(d)
            guard l < r, l > 0.1 else { continue }
            motes[i].vel += d / l * strength * (1 - l / r) * (1.2 - motes[i].depth)
            if isNight && lit < 14 && Float.random(in: 0...1) < 0.5 { glowPlankton(at: motes[i].pos); lit += 1 }
        }
        if isNight { for _ in 0..<Int(strength / 12) { glowPlankton(at: p + SIMD2(Float.random(in: -r...r), Float.random(in: -r...r)) * 0.5) } }
    }

    /// Night: the water is dark enough for the plankton to show (bioluminescence).
    var isNight: Bool { light < 0.75 }

    /// A blue-green spark where the plankton was disturbed.
    private func glowPlankton(at p: SIMD2<Float>) {
        particles.append(Particle(pos: p, vel: [Float.random(in: -6...6), Float.random(in: 2...10)], life: 0,
                                  maxLife: Float.random(in: 0.9...1.8), size: Float.random(in: 4...7), grow: 1.5, kind: 4,
                                  color: SIMD4(mix([0.25, 0.85, 1], [0.4, 1, 0.75], t: Float.random(in: 0...1)), 1)))
    }
    private var motes: [Mote] = []
    private var motesFor: SIMD2<Float> = .zero

    private func updateMotes(dt: Float) {
        if motes.isEmpty || abs(motesFor.x - size.x) > 200 || abs(motesFor.y - size.y) > 200 {
            motesFor = size
            let n = max(40, min(170, Int(size.x * size.y / 8000)))
            motes = (0..<n).map { _ in
                let depth = Float.random(in: 0...1)
                return Mote(pos: [Float.random(in: 0...size.x), Float.random(in: 0...size.y)], depth: depth,
                            size: depth < 0.3 ? Float.random(in: 2.8...4.2) : Float.random(in: 1.3...2.4),
                            phase: Float.random(in: 0...20), speed: Float.random(in: 2...7) * (1.2 - depth * 0.6))
            }
        }
        // fish swimming by leave a wake in the snow
        let movers = fish.filter { !$0.leaving && simd_length($0.vel) > 35 }
        for i in motes.indices {
            var m = motes[i]
            m.phase += dt
            for f in movers {
                let d = m.pos - f.pos, l = simd_length(d), r = f.size * 1.6
                if l < r && l > 0.1 {
                    m.vel += (d / l * 40 + f.vel * 0.5) * (1 - l / r) * dt * (1.2 - m.depth)
                    // at night, a fish swimming fast leaves a glowing wake
                    if isNight && simd_length(f.vel) > 60 && Float.random(in: 0...1) < dt * 3 { glowPlankton(at: m.pos) }
                }
            }
            m.pos += m.vel * dt
            m.vel *= expf(-dt * 1.6)
            m.pos.y -= m.speed * dt
            m.pos.x += (sinf(m.phase * 0.35) * 5 + current * 0.5 * (1.1 - m.depth)) * dt
            if m.pos.y < size.y * sand(m.pos.x / max(1, size.x)) { m.pos.y = size.y * 0.97; m.pos.x = Float.random(in: 0...size.x) }
            if m.pos.x < -10 { m.pos.x += size.x + 20 } else if m.pos.x > size.x + 10 { m.pos.x -= size.x + 20 }
            motes[i] = m
        }
    }

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

    /// The sun by day and the moon by night, seen through the surface: (x 0…1, strength, warmth, unused).
    /// The sun crosses from left (morning) to right (evening), warmer when low; the moon crosses at night.
    static func sky(hour h: Float) -> SIMD4<Float> {
        if h >= 6 && h <= 18.5 {
            let k = (h - 6) / 12.5
            let low = 1 - sinf(k * .pi)                                         // 1 at sunrise and sunset
            return [0.1 + 0.8 * k, 0.36 - 0.06 * low, min(1, low * 1.3), 0]
        }
        let n = (h > 18.5 ? h - 18.5 : h + 5.5) / 11.5                           // 18:30 → 6:00
        let fade = smoothstep(0, 0.08, n) * (1 - smoothstep(0.92, 1, n))
        return [0.1 + 0.8 * n, 0.32 * fade, 0, 0]
    }

    /// Pebbles and tiny shells scattered on the sand (fixed places, away from the big scenery).
    private lazy var pebbles: [(u: Float, size: Float, shell: Bool, tone: Float, seed: Float)] = (0..<26).map { i in
        let r = { (k: Float) -> Float in let v = sinf(Float(i) * 12.9898 + k * 78.233) * 43758.547; return v - floorf(v) }
        return (0.03 + r(1) * 0.94, 3.8 + r(2) * 4.6, r(3) < 0.22, r(4), r(5) * 6)
    }

    /// The color of the hour: warm at dawn, neutral by day, golden late afternoon, violet at dusk, blue at night.
    /// rgb multiplies the image; w is moonlight (0…1).
    static func grade(hour h: Float) -> SIMD4<Float> {
        let keys: [(Float, SIMD4<Float>)] = [
            (0, [0.72, 0.8, 1.05, 1]), (4.8, [0.72, 0.8, 1.05, 1]), (6.3, [1.12, 0.9, 0.78, 0.2]), (8.5, [1, 1, 1, 0]),
            (16, [1, 1, 1, 0]), (18.2, [1.22, 0.98, 0.7, 0]), (19.6, [0.98, 0.8, 0.96, 0.3]), (21, [0.72, 0.8, 1.05, 1]),
            (24, [0.72, 0.8, 1.05, 1]),
        ]
        for i in 1..<keys.count where h <= keys[i].0 {
            let (h0, a) = keys[i - 1], (h1, b) = keys[i]
            let k = smoothstep(0, 1, (h - h0) / max(0.001, h1 - h0))
            return a + (b - a) * k
        }
        return keys[0].1
    }

    /// Marine snow on or off (Preferências → Aparência).
    var showMotes = true

    /// `front`: the near ones (in front of the fish). They move more with the parallax, and light up inside the sun rays.
    private func moteSprites(front: Bool) -> [Sprite] {
        guard showMotes else { return [] }
        let tint: SIMD3<Float> = SIMD3<Float>(0.78, 0.9, 0.95) * (0.55 + 0.45 * light)
        return motes.filter { ($0.depth < 0.3) == front }.map { m in
            let shift = gaze * (-12 * (1 - m.depth))
            let twinkle = 0.75 + 0.25 * sinf(m.phase * 1.7)
            let lit = min(2.5, rayLight(m.pos) * 7)
            return Sprite(pos: m.pos + shift, dir: [1, 0], size: m.size * (1 + lit * 0.25), kind: 33,
                          glow: min(1, (front ? 0.62 : 0.38) * twinkle * (1 + lit)),
                          phase: 0, color: SIMD4(tint * (1 + lit * 0.3), 1), extra: [1, 0, 0, 0])
        }
    }

    /// A soft shadow on the sand under something swimming: darker and smaller the closer it is to the bottom.
    private func shadow(under p: SIMD2<Float>, size s: Float, strength: Float) -> Sprite? {
        let sy = size.y * sand(p.x / max(1, size.x)) + 2
        let t = max(0, min(1, (p.y - sy) / (size.y * 0.55)))
        let a = (1 - t) * (1 - t) * 0.5 * strength * (0.45 + 0.55 * light)
        guard a > 0.01 else { return nil }
        return Sprite(pos: [p.x, sy], dir: [1, 0], size: s * (1.0 + t * 1.6), kind: 32, glow: a, phase: 0,
                      color: [0, 0, 0, 1], extra: [1, 0, 0, 0])
    }
    private lazy var weeds = Self.weeds(weedCount)

    /// The shader's seaweed (same formula): x position (0…1) and height (fraction of the screen), rising from y = 0.055.
    private static func weeds(_ n: Int) -> [(x: Float, h: Float)] { (0..<n).map { k in
        let fk = Float(k)
        let fr: (Float) -> Float = { $0 - floorf($0) }
        // spread over the whole width: each blade in its own slice, at a random place within it (so it doesn't look lined up)
        let slice = 0.9 / Float(max(1, n))
        return (0.05 + (fk + 0.1 + 0.8 * fr(sinf(fk * 91.7) * 437.1)) * slice, 0.16 + fr(sinf(fk * 13.1) * 91.3) * 0.28)
    } }

    private func nearestWeed(_ p: SIMD2<Float>) -> SIMD2<Float> {
        let pts = weeds.map { a -> SIMD2<Float> in
            [a.x * size.x, size.y * (0.055 + a.h * Float.random(in: 0.35...0.75))]
        }
        return pts.min { simd_distance($0, p) < simd_distance($1, p) } ?? p
    }

    private func startAction(_ f: Fish, _ name: String) {
        guard f.isAgent else { return }
        let new: Action
        switch ToolBehaviors.of(name).animation {
        case .nibble: new = .nibble(nearestWeed(f.pos))
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

    /// Gauge names from older plugins, in Portuguese.
    private static let legacyGauges = ["disco": "disk", "bateria": "battery", "carregando": "charging"]

    /// A scene control (docs/scene.md): the highest value among gauges with this name, from any source ("weather:rain").
    func sceneGauge(_ name: String) -> Float? {
        gauges.filter { $0.key.hasSuffix(":" + name) }.map(\.value).max()
    }

    private var rainAt: Double = 0

    /// The water's surface height at x, as the background shader draws it (waves included).
    func surfaceY(_ x: Float) -> Float {
        let u = x / max(1, size.x), t = shaderTime, waves = sceneGauge("waves") ?? 0
        let s = 0.965 + (0.006 * sinf(u * 30 + t * 1.5) + 0.004 * sinf(u * 71 - t * 2.3)) * (1 + 2.5 * waves)
              + 0.007 * waves * sinf(u * 13 - t * 3.1) - 0.004 * waves
        return size.y * s
    }

    /// Rain: drops hitting the surface (little rings) and, once in a while, a bubble pushed under.
    private func rainOnSurface() {
        guard let rain = sceneGauge("rain"), rain > 0.01, time > rainAt else { return }
        rainAt = time + Double(0.5 / (1 + rain * 30))
        let x = Float.random(in: 0...size.x), surf = surfaceY(x)
        particles.append(Particle(pos: [x, surf], vel: .zero, life: 0, maxLife: 0.8, size: 2, grow: 18 + rain * 14, kind: 8,
                                  color: [0.8, 0.92, 1, 1]))
        if Float.random(in: 0...1) < 0.2 { bubble(at: [x, surf - Float.random(in: 4...20)], size: Float.random(in: 1...1.8)) }
    }

    func gauge(source: String, name: String, value: Float) {
        let key = "\(source):\(Self.legacyGauges[name] ?? name)"
        gauges[key] = max(0, min(1, value))
        gaugeAt[key] = time
    }

    /// When each gauge was last sent: one silent for over an hour goes away (a plugin that stopped).
    private var gaugeAt: [String: Double] = [:]
    static let gaugeLifetime: Double = 3600

    func removeGauge(source: String, name: String) {
        let key = "\(source):\(Self.legacyGauges[name] ?? name)"
        gauges[key] = nil
        gaugeAt[key] = nil
    }

    private func expireGauges() {
        for (k, at) in gaugeAt where time - at > Self.gaugeLifetime { gauges[k] = nil; gaugeAt[k] = nil }
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
        for i in motes.indices {
            let d = simd_distance(motes[i].pos, b)
            if d < 140 { motes[i].vel += flow * 2.2 * (1 - d / 140) }
        }
        for f in fish where !f.leaving && simd_distance(f.pos, b) < 120 { f.vel += flow * 1.6 }
        flowPush = (b, flow, time)
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

    /// The last bit of current made by dragging through the water (the seaweed sways with it).
    private var flowPush: (at: SIMD2<Float>, flow: SIMD2<Float>, when: Double)?

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
        stir(at: p, radius: 150, strength: 70)
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
    private let batteryU: Float = 0.8
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
    private var frameDt: Float = 1 / 60

    func update(dt rawDt: Float) {
        let dt = min(rawDt, 0.05)
        frameDt = dt
        time = CACurrentMediaTime()
        // the chest lets out a few bubbles now and then
        if time > chestBubblesAt, let chest = scenery.first(where: { $0.id == "chest" }) {
            chestBubblesAt = time + Double.random(in: 7...16)
            let (c, sz) = place(chest)
            for i in 0..<Int.random(in: 3...6) {
                after(Double(i) * 0.12) { [weak self] in
                    self?.bubble(at: c + [Float.random(in: -sz * 0.4...sz * 0.4), sz * 0.15], size: Float.random(in: 1.5...3))
                }
            }
        }

        // scheduled effects
        if !later.isEmpty {
            var keep: [(Double, () -> Void)] = []
            keep.reserveCapacity(later.count)
            for item in later {
                if item.0 <= time { item.1() } else { keep.append(item) }
            }
            later = keep
        }

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

        scene.update(self, dt: dt)
        updateWeeds(dt: dt)
        let agents = Float(fish.filter { $0.isAgent && !$0.decor && !$0.leaving }.count)
        crowd += (max(0, min(1, (agents - 4) / 6)) - crowd) * min(1, dt * 0.5)
        if Int(time * 10) % 50 == 0 { expireGauges() }
        breathe(dt: dt)
        updateChest(dt: dt)
        layoutTimeline()
        rainOnSurface()
        updateMotes(dt: dt)

        // current: high CPU gently pushes everything to one side
        let cpu = gauges["mac:cpu"] ?? 0
        let currentTarget = smoothstep(0.55, 0.95, cpu) * 26 * (0.7 + 0.3 * sinf(Float(time) * 0.05))
        current += (currentTarget - current) * min(1, dt * 0.3)

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
        if Int(time) % 60 == 0 && Self.today() != pearlsDay { pearls = []; bornAt = []; pearlsDay = Self.today() }

        fauna.update(self, dt: dt)
        // parallax: slowly follows the mouse; without a mouse, returns to center
        let gazeTarget: SIMD2<Float> = cursor.map { c in time - cursorAt < 6 ? (c / SIMD2(max(1, size.x), max(1, size.y))) * 2 - 1 : .zero } ?? .zero
        gaze += (gazeTarget - gaze) * min(1, dt * 1.5)

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

        // bubble ring from the idle ones
        for f in fish where !f.decor && !f.leaving && (f.state == .idle || f.state == .ok) && !sleeping(f) && time > f.ringAt {
            if f.ringAt > 0 && Float.random(in: 0...1) < 0.6 {
                particles.append(Particle(pos: f.pos + facing(f) * f.size * 0.9, vel: [0, 22], life: 0, maxLife: 3.2, size: 4, grow: 7,
                                          kind: 2, color: [0.85, 0.95, 1, 1]))
            }
            f.ringAt = time + Double.random(in: 18...45)
        }

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

        // forgotten sessions leave on their own after 2 h without news
        for f in fish where !f.decor && !f.leaving && time - f.seen > 7200 { f.leaving = true }

        let food = particles.indices.filter { particles[$0].kind == 3 }
        // queue at the glass in order of arrival
        let waiting = fish.filter { $0.state == .waiting && !$0.leaving && !$0.decor }.sorted { $0.since < $1.since }

        for f in fish { steer(f, dt: dt, food: food, waiting: waiting) }

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
        let disk = gauges.filter { $0.key.hasSuffix(":disk") }.values.max() ?? 0
        let goal = smoothstep(0.85, 0.97, disk)
        turbidity += (goal - turbidity) * min(1, dt * 0.5)
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

    private func steer(_ f: Fish, dt: Float, food: [Int], waiting: [Fish]) {
        if let to = f.grabbedTo {
            // pulled by the mouse: follows it with a little lag, tail beating fast
            f.vel += ((to - f.pos) * 7 - f.vel) * min(1, dt * 8)
            f.pos += f.vel * dt
            f.tail += dt * 14
            return
        }
        let w = size.x, h = size.y
        var target: SIMD2<Float>
        var speed: Float
        var scaleTarget: Float = 1

        // jump: rises to the surface and arcs through the air, splashing on the way out and back
        if f.jumpPhase > 0 && !f.leaving && !f.decor {
            let surf = h * 0.965
            if f.jumpPhase == 1 {
                let goal: SIMD2<Float> = [f.pos.x + f.jumpDir * 40, surf]
                let d = goal - f.pos, l = simd_length(d)
                f.vel += ((l > 1 ? d / l * 430 : .zero) - f.vel) * min(1, dt * 6)
                f.pos += f.vel * dt
                if f.pos.y > surf - 28 { f.jumpPhase = 2; f.jumpT0 = time; f.jumpX0 = f.pos.x; splash(at: [f.pos.x, surf]) }
            } else {
                let u = Float(time - f.jumpT0) / 0.95
                if u >= 1 {
                    f.jumpPhase = 0
                    splash(at: [f.pos.x, surf])
                    f.vel = [f.jumpDir * 60, -170]
                } else {
                    let new: SIMD2<Float> = [f.jumpX0 + f.jumpDir * 120 * u, surf - 8 + 80 * sinf(.pi * u)]
                    f.vel = (new - f.pos) / max(dt, 0.001)
                    f.pos = new
                }
            }
            f.tail += dt * 16
            f.glow *= expf(-dt * 2.5)
            return
        }

        // in focus (mouse over it or card open): small circle in place
        if f.id == focused && !f.leaving && f.jumpPhase == 0 {
            let ang = Float(time) * 1.6
            let goal = focusCenter + SIMD2(cosf(ang), sinf(ang) * 0.6) * 14
            let d = goal - f.pos
            f.vel += ((simd_length(d) > 0.5 ? d * 3 : .zero) - f.vel) * min(1, dt * 4)
            f.pos += f.vel * dt
            f.scale += (1.08 - f.scale) * min(1, dt * 3)
            f.tail += dt * (4 + simd_length(f.vel) * 0.1)
            f.glow = max(f.glow * expf(-dt * 2.5), 0.25)
            return
        }

        // scare: flees from the click
        let curious = !f.leaving && f.action == nil && !sleeping(f) && time - cursorAt < 8 && time - cursorRestingAt > 0.8
            && (f.decor ? f.parent == nil : (f.state == .idle || f.state == .ok || f.state == .done))
        if time < f.fearUntil && !f.leaving {
            let d = f.pos - f.fearFrom
            target = f.pos + (simd_length(d) > 1 ? simd_normalize(d) : [1, 0]) * 220
            speed = 280
        } else if let b = game, b.chaser == f.id || b.runner == f.id,
                  let other = fish.first(where: { $0.id == (b.chaser == f.id ? b.runner : b.chaser) }) {
            // tag
            if b.chaser == f.id { target = other.pos; speed = 115 }
            else {
                let d = f.pos - other.pos
                var escape = f.pos + (simd_length(d) > 1 ? simd_normalize(d) : [1, 0]) * 160
                escape = [max(w * 0.08, min(w * 0.92, escape.x)), max(h * 0.15, min(h * 0.85, escape.y))]
                target = escape; speed = 125
            }
        } else if let c = cursor, curious, simd_distance(c, f.pos) < 360 {
            // the curious ones come close to the mouse, around it
            let ang = Float(f.phase) * 1.7 + Float(time) * 0.4
            target = c + SIMD2(cosf(ang), sinf(ang) * 0.6) * (f.size * 2 + 20)
            speed = 60
        } else if let id = f.chattingWith, time < f.chatUntil, let o = fish.first(where: { $0.id == id }) {
            // chat: they meet snout to snout halfway
            let middle = (f.pos + o.pos) / 2
            target = middle + [f.pos.x < o.pos.x ? -f.size * 0.95 : f.size * 0.95, 0]
            speed = 50
        } else if f.id == highlighted && !f.leaving {
            // parade: comes to the middle, in front, glowing
            target = [w * 0.5, h * 0.5]
            speed = 220
            scaleTarget = 1.7
            f.glow = max(f.glow, 0.6)
        } else if f.leaving && f.party {
            // party: rises and exits through the surface
            target = [f.pos.x + sinf(Float(time) * 3) * 30, h + 200]
            speed = 120
        } else if f.leaving {
            target = [f.pos.x < w / 2 ? -200 : w + 200, f.pos.y]
            speed = 140
        } else if let parent = f.parent {
            // fry: swims behind the parent, around it
            if parent.leaving || !fish.contains(where: { $0 === parent }) { f.leaving = true }
            let ang = Float(f.phase) * 2.1 + Float(time) * 1.4
            let behind = parent.pos - (simd_length(parent.vel) > 1 ? simd_normalize(parent.vel) : [1, 0]) * parent.size * 1.2
            target = behind + SIMD2(cosf(ang), sinf(ang)) * parent.size * 0.7
            speed = 160
        } else if f.sings {
            if f.state == .busy {
                // playing: it dances up high, bobbing to a beat, and lets out notes now and then
                target = wanderPoint(f, yRange: (h * 0.58, h * 0.8), every: 3...6)
                target.y += sinf(Float(time) * 4.2) * 14
                speed = 55
                scaleTarget = 1.55                     // the special fish: bigger
                if time > f.noteAt {
                    f.noteAt = time + Double.random(in: 0.5...1.1)
                    notes(from: f, n: 1)
                }
            } else {
                // paused: it sinks slowly and rests
                target = [f.pos.x, h * 0.3]
                speed = 12
                scaleTarget = 1.3
            }
        } else if f.decor {
            // the school follows the neons' center, wandering
            let school = f.phase / 100
            let leads = f.phase % 100 == 0
            // many sessions in the tank: the schools step back (further, fainter), and come forward again when it empties
            f.depth += (min(0.92, f.restDepth + crowd * 0.3) - f.depth) * min(1, dt * 0.25)
            if leads && (time > f.wanderAt || simd_distance(f.pos, f.wander) < 30) {
                // each school keeps to its own height: neons in the middle, tetras up high, silversides low in the back
                let band: ClosedRange<Float> = school == 1 ? 0.55...0.88 : school == 2 ? 0.18...0.48 : 0.3...0.8
                f.wander = [Float.random(in: w * 0.12...w * 0.88), h * Float.random(in: band)]
                f.wanderAt = time + Double.random(in: school == 2 ? 7...14 : 4...9)
            }
            let leader = fish.first { $0.decor && $0.parent == nil && $0.phase == school * 100 } ?? f
            if leads {
                target = f.wander
            } else {
                // a school: toward the group's center, heading where the group heads, following the leader from a distance
                var center = SIMD2<Float>.zero, heading = SIMD2<Float>.zero, n: Float = 0
                for o in fish where o.decor && o.parent == nil && o !== f && o.phase / 100 == school { center += o.pos; heading += o.vel; n += 1 }
                if n > 0 { center /= n; heading /= n }
                let wobble = SIMD2(sinf(Float(time) * 0.7 + Float(f.phase) * 1.9), cosf(Float(time) * 0.5 + Float(f.phase))) * 9
                target = f.pos + (center - f.pos) * 0.35 + (leader.pos - f.pos) * 0.3 + heading * 0.8 + wobble
            }
            speed = (leads ? 45 : 75) * (school == 2 ? 0.7 : 1)
            // a real school: they part around a big fish passing through and close up again behind it,
            // and keep a little room between each other
            var away: SIMD2<Float> = .zero
            for o in fish where !o.decor && !o.leaving && o.parent == nil {
                let d = f.pos - o.pos, r = o.size * 2.4, l = simd_length(d)
                if l < r && l > 0.1 { away += d / l * (r - l) / r }
            }
            // a shark (a presence) going by: the school scatters, and comes back together after
            for p in scene.presences where p.kind.id == "shark" && !p.leaving {
                let d = f.pos - p.pos, r = p.kind.size * 3.2, l = simd_length(d)
                if l < r && l > 0.1 { away += d / l * (r - l) / r * 2.2 }
            }
            for o in fish where o.decor && o !== f && o.parent == nil {
                let d = f.pos - o.pos, l = simd_length(d)
                if l < 16 && l > 0.1 { away += d / l * (16 - l) / 16 * 0.6 }
            }
            if simd_length(away) > 0.01 {
                target = f.pos + simd_normalize(away) * 90 + (target - f.pos) * 0.3
                speed = 120
            }
        } else {
            switch f.state {
            case .waiting:
                // queue at the glass: whoever arrived first stays in the middle; whoever waits longer gets bigger
                let i = Float(waiting.firstIndex { $0 === f } ?? 0)
                let n = Float(waiting.count)
                target = [w * 0.5 + (i - (n - 1) / 2) * 130, h * 0.42 + sinf(Float(time) * 2 + i) * 6]
                speed = 120
                scaleTarget = 1.55 + min(0.35, Float(time - f.since) / 60 * 0.06)
            case .busy where f.action != nil:
                switch f.action! {
                case .nibble(let goal):
                    // puts its snout against the seaweed and takes little nibbles
                    target = goal + [f.actionSide * (f.size * 0.85 + sinf(Float(time) * 10) * 3), 0]
                    speed = simd_distance(f.pos, goal) > f.size * 3 ? 200 : 90
                case .forage:
                    target = [f.pos.x + sinf(Float(time) * 0.8 + Float(f.phase)) * 25, size.y * sand(f.pos.x / max(1, w)) + f.size * 0.85]
                    speed = 170
                case .peek:
                    target = [f.pos.x, h * 0.93]
                    speed = 190
                case .bubbles:
                    target = f.pos + [f.vel.x >= 0 ? 4 : -4, 0]   // stops to release the bubbles
                    speed = 10
                case .mail:
                    // goes to meet the seahorse
                    if let c = mails.first(where: { $0.goal == f.id && $0.stage < 2 }) {
                        target = c.pos + [-c.side * f.size * 1.2, 0]
                        speed = 110
                    } else {
                        target = f.pos
                        speed = 20
                    }
                }
            case .busy:
                target = wanderPoint(f, yRange: (h * 0.4, h * 0.85), every: 2.5...5)
                speed = 75 * (1 + min(1, Float(f.toolTimes.count) / 15)) * (1 - f.fat * 0.35)   // pace; a fat fish swims slowly
                speed *= burst(f)
            case .error:
                // sick: sinks slowly, almost still
                let background = size.y * sand(f.pos.x / max(1, w)) + f.size * 1.9   // near the bottom, with room for the label
                target = [f.pos.x + sinf(Float(time) * 0.4 + Float(f.phase)) * 10, max(background, f.pos.y - 18)]
                speed = 10
            case .alert:
                target = wanderPoint(f, yRange: (h * 0.25, h * 0.8), every: 1.5...3)
                speed = 55
            case .done where time - f.since < 2.5:
                // comes a bit closer to the glass to knock: almost stops in place and grows a tiny bit
                target = f.pos + [f.vel.x >= 0 ? 6 : -6, 0]
                speed = 12
                scaleTarget = 1.25
            default: // idle, ok, born, done (after rising)
                if sleeping(f) {
                    // lies on the sand
                    target = [f.pos.x, size.y * sand(f.pos.x / max(1, w)) + f.size * 1.7]
                    speed = 8
                } else if f.kindID == "octopus" && time - f.since > 45 * Self.scale {
                    // an octopus whose PR sits still settles on the sand and blends in (camouflage, below)
                    target = [f.pos.x + sinf(Float(time) * 0.2 + Float(f.phase)) * 6, size.y * sand(f.pos.x / max(1, w)) + f.size * 0.85]
                    speed = 14
                } else {
                    target = wanderPoint(f, yRange: (h * 0.14, h * 0.36), every: 5...10)
                    speed = 24 * burst(f)
                    // a sibling from the same project also idle: they swim side by side (the newer one alongside the older)
                    if let mate = fish.first(where: { $0 !== f && !$0.decor && !$0.leaving && $0.projectKey == f.projectKey
                                                      && ($0.state == .idle || $0.state == .ok) && $0.variant < f.variant }) {
                        let side: Float = f.variant % 2 == 0 ? 1 : -1
                        target = mate.pos + [-(mate.vel.x >= 0 ? 1 : -1) * mate.size * 1.4, side * mate.size * 1.1]
                        speed = 40
                    }
                }
            }
            // those from the same project go take care of the sick one
            if f.state != .error && f.state != .waiting,
               let sick = fish.first(where: { $0 !== f && !$0.decor && !$0.leaving && $0.state == .error && $0.source == f.source && $0.label == f.label }) {
                let ang = Float(time) * 0.8 + Float(f.phase)
                target = sick.pos + SIMD2(cosf(ang), sinf(ang) * 0.6) * (sick.size * 2.2)
                speed = 60
            }
            // food attracts
            if f.state != .waiting, let idx = food.min(by: { simd_distance(particles[$0].pos, f.pos) < simd_distance(particles[$1].pos, f.pos) }),
               simd_distance(particles[idx].pos, f.pos) < 380 {
                target = particles[idx].pos
                speed = 150
            }
        }

        // the scenery: they go around it instead of through it
        if !f.leaving && f.jumpPhase == 0 {
            for s in scenery where s.solid {
                let (c, sz) = place(s)
                let r = sz * 1.15 + f.size * 0.5
                let away = f.pos - c, la = simd_length(away)
                if la < r {
                    target = c + (la > 0.1 ? away / la : [0, 1]) * (r + 24)
                    speed = max(speed, 70)
                } else {
                    let to = target - c, lt = simd_length(to)
                    if lt < r { target = c + (lt > 0.1 ? to / lt : [0, 1]) * r }
                }
            }
        }

        let d = target - f.pos
        let l = simd_length(d)
        var desired: SIMD2<Float> = l > 1 ? d / l * min(speed, l * 2.2) : .zero
        if f.state == .waiting && l < 12 { desired = [f.vel.x > 0 ? 6 : -6, 0] } // faces forward, swimming in place
        f.vel += (desired - f.vel) * min(1, dt * (f.decor ? 3 : f.action != nil ? 3 : 1.8))
        if f.shake > 0 {
            f.vel += SIMD2(Float.random(in: -1...1), Float.random(in: -1...1)) * 220 * f.shake * dt
            f.shake = max(0, f.shake - dt * 0.6)
        }
        if f.state == .error && Float.random(in: 0...1) < dt * 0.15 { f.shake = 0.25 }
        f.pos += f.vel * dt
        f.pos.x += current * dt * (f.decor ? 0.9 : 0.5)
        if !f.leaving && f.pos.y < h + 40 {
            f.pos.y = max(40 + f.size * 0.3, min(h - 20, f.pos.y))
            f.pos.x = max(10, min(w - 10, f.pos.x))
        }
        f.scale += (scaleTarget - f.scale) * min(1, dt * 2)
        // the tail beats with speed, and harder while accelerating (a push)
        let speedNow = simd_length(f.vel)
        let push = max(0, (speedNow - f.lastSpeed) / max(dt, 0.001))
        f.lastSpeed = speedNow
        f.tail += dt * (4 + speedNow * 0.1 + min(push * 0.04, 10))
        f.glow *= expf(-dt * 2.5)
    }

    private func wanderPoint(_ f: Fish, yRange: (Float, Float), every: ClosedRange<Double>) -> SIMD2<Float> {
        let away = f.wander.y < yRange.0 - 10 || f.wander.y > yRange.1 + 10
        if time > f.wanderAt || simd_distance(f.pos, f.wander) < 25 || away {
            f.wander = [Float.random(in: size.x * 0.08...size.x * 0.92), Float.random(in: yRange.0...yRange.1)]
            f.wanderAt = time + Double.random(in: every)
        }
        return f.wander
    }

    // MARK: - For the renderer

    func sprites() -> [Sprite] {
        var out: [Sprite] = []
        out.reserveCapacity(fish.count + particles.count + 1)

        // the whale in the distance, behind everything
        out += fauna.background(self)
        // jellyfish (pad)
        out.append(Sprite(pos: jellyPos, dir: [1, 0], size: 30, kind: 5, glow: 0.25 + jellyGlow + (isNight ? 0.35 : 0),
                          phase: jellyPhase, color: [0.85, 0.55, 1.0, 0.75], extra: [1, 0, 0, 0]))

        if let b = battery {
            let a = batteryAngle
            out.append(Sprite(pos: batteryPos, dir: [cosf(a), sinf(a)], size: 17, kind: 6, glow: b,
                              phase: jellyPhase, color: [1, 1, 1, 1], extra: [1, pluggedIn ? 1 : 0, 0, 0]))
        }

        // marine snow far away, and the shadows on the sand (under the fish and whatever swims)
        out += moteSprites(front: false)
        for f in fish where !isHidden(f) {
            if let s = shadow(under: f.pos, size: f.size * (1 - 0.35 * f.depth), strength: (f.leaving ? 0.4 : 1) * (1 - f.depth * 0.6)) { out.append(s) }
        }
        for p in scene.presences where [.swim, .drift, .hover].contains(p.kind.motion) {
            if let s = shadow(under: p.pos, size: p.kind.size, strength: p.alpha) { out.append(s) }
        }

        // the scenery: behind the pearls, the creatures and the fish, softened a little by the water
        let lit = 0.45 + 0.55 * light
        let water: SIMD3<Float> = SIMD3<Float>(0.12, 0.3, 0.4) * (0.5 + 0.5 * light)
        let night = max(0, min(1, (0.8 - light) / 0.6))
        for s in scenery {
            let (c, sz) = place(s)
            let color = mix(s.color * lit, water, t: 0.15)
            if let i = s.pack {
                // a pack's piece: its own drawing (kind 35, its index in extra.z), the quad from its extent
                out.append(Sprite(pos: c, dir: [1, 0], size: sz, kind: 35, glow: s.glowAtNight ? night : 0, phase: Float(time),
                                  color: SIMD4(color, 1), extra: [1, s.seed, Float(i), night], aux: [s.extent.x, s.extent.y, 0, 0]))
                continue
            }
            out.append(Sprite(pos: c, dir: [1, 0], size: sz, kind: s.kind, glow: s.id == "chest" ? 0.8 + chestLid * 0.6 : 0,
                              phase: s.id == "chest" || s.id == "shell" ? Float(time) : s.seed, color: SIMD4(color, 1),
                              extra: [1, s.id == "chest" ? min(1, chestLid) : s.id == "shell" ? 1 : 0, 0, 0]))
        }
        // pebbles and little shells on the sand
        for p in pebbles {
            let x = clearOfScenery(size.x * p.u)
            let y = size.y * sand(x / max(1, size.x)) + p.size * 0.25
            let base: SIMD3<Float> = p.shell ? [0.95, 0.82, 0.74] : mix([0.36, 0.33, 0.3], [0.58, 0.52, 0.44], t: p.tone)
            out.append(Sprite(pos: [x, y], dir: [1, 0], size: p.size * (p.shell ? 1.1 : 1), kind: p.shell ? 22 : 21, glow: 0,
                              phase: p.seed, color: SIMD4(mix(base * lit, water, t: 0.2), 1), extra: [1, 0, 0, 0]))
        }
        // pearls of the day, on the sand
        for (i, p) in pearls.enumerated() {
            let new = i < bornAt.count && bornAt[i] > 0 ? max(0, 1 - Float(time - bornAt[i]) / 3) : 0
            out.append(Sprite(pos: pearlPos(p), dir: [1, 0], size: 6, kind: 12, glow: new, phase: Float(i),
                              color: [p.color[0], p.color[1], p.color[2], 1], extra: [1, 0, 0, 0]))
        }
        // list pebbles (TodoWrite): the done ones glow in the fish's color
        for f in fish where !f.decor && !f.leaving {
            guard let t = f.todos, let u = f.todoU else { continue }
            let n = min(t.total, 12)
            for i in 0..<n {
                let x = clearOfScenery(size.x * u + (Float(i) - Float(n - 1) / 2) * 11)
                let pu = x / max(1, size.x)
                let isDone = i < t.done
                out.append(Sprite(pos: [x, size.y * sand(pu) + 3], dir: [1, 0], size: isDone ? 4.5 : 4, kind: 12,
                                  glow: isDone ? 0.45 : 0, phase: Float(i) * 1.7,
                                  color: isDone ? SIMD4(f.color, 1) : [0.45, 0.42, 0.38, 1], extra: [1, 0, 0, 0]))
            }
        }
        // starfish, crabs, turtle and lanternfish
        out += fauna.middle(self)
        // what plugins put in the tank (the ones waiting for you come after the fish)
        out += scene.sprites(self, front: false)
        // ink and murky water (behind the fish)
        for p in particles where p.kind == 10 {
            let k = 1 - p.life / p.maxLife
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: 10, glow: min(1, p.life * 2) * k, phase: 0,
                              color: p.color, extra: [1, 0, 0, 0]))
        }

        for p in particles where p.kind == 3 || p.kind == 1 {
            let a = p.kind == 3 ? min(1, (p.maxLife - p.life) / 2) : 1
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: p.kind, glow: a, phase: 0,
                              color: p.color, extra: [1, 0, 0, 0]))
        }

        // fish near the surface show upside down on its underside, faint
        let surfY = size.y * 0.965
        for f in fish where !f.leaving && !isHidden(f) && surfY - f.pos.y < f.size * 2.2 && f.pos.y < surfY {
            let gap = surfY - f.pos.y
            let a = (1 - gap / (f.size * 2.2)) * 0.28
            let l = simd_length(f.vel)
            let dx: Float = l > 0.01 && f.vel.x < 0 ? -1 : 1
            out.append(Sprite(pos: [f.pos.x, surfY + gap * 0.6], dir: [dx, 0], size: f.size * (1 - 0.35 * f.depth), kind: 0,
                              glow: 0, phase: f.tail, color: SIMD4(mix(f.color, [0.7, 0.9, 1], t: 0.4), a),
                              extra: [-dx * max(abs(f.facingX), 0.12), Float(f.pattern + f.cut * 8), Float(f.species), 0]))
        }

        // far ones first (they stay behind)
        for f in fish.sorted(by: { $0.depth > $1.depth }) where !isHidden(f) {
            let l = simd_length(f.vel)
            var dx = l > 0.01 ? f.vel.x / l : 1
            var dy = l > 0.01 ? f.vel.y / l : 0
            // during the action, the body follows what it's doing, not just the velocity
            if let a = f.action, f.state == .busy {
                switch a {
                case .nibble(let goal) where simd_distance(f.pos, goal) < f.size * 2.2:
                    dx = -f.actionSide; dy = 0
                case .forage where f.pos.y - size.y * sand(f.pos.x / max(1, size.x)) < f.size * 1.6:
                    dx = dx >= 0 ? 0.8 : -0.8; dy = -0.6
                case .peek where f.pos.y > size.y * 0.86:
                    dx = dx >= 0 ? 0.8 : -0.8; dy = 0.6
                default: break
                }
            }
            let octopus = f.kindID == "octopus"      // the octopus doesn't tilt or mirror: always stays upright
            let asleep = sleeping(f)
            var tilt = octopus ? 0 : max(-0.5, min(0.5, atan2f(dy, abs(dx))))
            if f.state == .error && !octopus && !f.decor { tilt = -0.6 + 0.08 * sinf(Float(time) * 0.7) }   // sick: nose down
            if asleep && !octopus { tilt = 0 }
            // chatting: facing each other
            if let id = f.chattingWith, time < f.chatUntil, let o = fish.first(where: { $0.id == id }),
               simd_distance(f.pos, o.pos) < (f.size + o.size) * 1.6 {
                dx = o.pos.x > f.pos.x ? 1 : -1; tilt = 0
            }
            // natural turns: the facing glides through 0 instead of flipping, and the tilt eases in
            let wantFacing: Float = octopus ? 1 : (dx >= 0 ? 1 : -1)
            if abs(wantFacing - f.facingX) > 0.001 {
                let turnRate: Float = f.decor ? 9 : 5.5                       // about a quarter of a second
                f.facingX += (wantFacing > f.facingX ? 1 : -1) * min(abs(wantFacing - f.facingX), turnRate * frameDt)
            }
            f.lean += (tilt - f.lean) * min(1, frameDt * 5)
            // mid-turn it arcs: the nose rises a little
            tilt = f.lean + (octopus ? 0 : 0.22 * (1 - abs(f.facingX)))
            tilt += f.spin * f.spin * 2 * .pi                                                          // little spin when it recovers
            let theta = f.facingX >= 0 ? tilt : Float.pi - tilt
            var c = f.color
            var alpha: Float = 1
            switch f.state {
            case .error:
                // sick: fades, pulled toward a grayish green
                let gray = (c.x + c.y + c.z) / 3
                c = mix(SIMD3(repeating: gray), [0.55, 0.62, 0.5], t: 0.4) * 0.85
                if octopus { c = mix(f.color, [1, 0.18, 0.15], t: 0.6) }
            case .alert: c = mix(c, [1, 0.75, 0.2], t: 0.5)
            case .idle, .ok:
                if f.sings { c = mix(SIMD3(repeating: (c.x + c.y + c.z) / 3), c, t: 0.25) * 0.6 }   // paused: almost gray
                else { c *= 0.75 }
            case .done: if time - f.since > 3 { c *= 0.75 }
            default: break
            }
            if f.decor { alpha = 0.85 }
            if asleep { c *= 0.8 }
            // camouflage: an octopus resting on the sand takes the sand's color, little by little (back in color when its state changes)
            if octopus && (f.state == .idle || f.state == .ok) && !f.leaving {
                let camo = smoothstep(45, 80, Float((time - f.since) / Self.scale))
                c = mix(c, SIMD3<Float>(0.5, 0.44, 0.33) * (0.45 + 0.55 * light), t: camo * 0.85)
            }
            var glow = f.glow
            if f.state == .waiting { glow = max(glow, 0.35 + 0.35 * sinf(Float(time) * 4)) }
            // waking up: stretches (grows and shrinks back)
            var len = f.size * (1 - 0.35 * f.depth)
            let water: SIMD3<Float> = SIMD3<Float>(0.12, 0.3, 0.4) * (0.5 + 0.5 * light)
            c = mix(c, water, t: f.depth * 0.55)
            if time < f.awakeUntil { len *= 1 + 0.16 * sinf(Float(1 - (f.awakeUntil - time) / 1.8) * .pi) }
            // the octopus moves by jets: its body squeezes and stretches in pulses, more the faster it goes
            var squeeze: Float = 1
            if octopus {
                let pace = min(1, l / 80), pulse = max(0, sinf(f.tail * 0.35))
                squeeze = 1 - 0.14 * pace * pulse
                len *= 1 + 0.09 * pace * pulse
            }
            // the eye: from world to the fish's own axes (rotated by theta, mirrored when it faces left)
            var lookTo: SIMD2<Float> = .zero
            if let cur = cursor, time - cursorAt < 4, simd_distance(cur, f.pos) < 320 { lookTo = simd_normalize(cur - f.pos + [0.01, 0]) }
            else if let fd = particles.lazy.filter({ $0.kind == 3 && simd_distance($0.pos, f.pos) < 320 }).first { lookTo = simd_normalize(fd.pos - f.pos + [0.01, 0]) }
            f.look += (lookTo - f.look) * min(1, frameDt * 5)
            let ct = cosf(theta), st = sinf(theta)
            var lookLocal: SIMD2<Float> = [f.look.x * ct + f.look.y * st, -f.look.x * st + f.look.y * ct]
            if f.facingX < 0 { lookLocal.y = -lookLocal.y }
            let blur = f.decor ? min(1, f.depth * 1.2) : max(0, (f.depth - 0.15) * 2.2)
            out.append(Sprite(pos: f.pos, dir: [cosf(theta), sinf(theta)], size: len, kind: 0,
                              glow: glow, phase: f.tail, color: SIMD4(c, alpha),
                              extra: [(f.facingX >= 0 ? max(abs(f.facingX), 0.12) : -max(abs(f.facingX), 0.12)) * squeeze,
                                      Float(f.pattern + f.cut * 8), Float(f.species), min(0.99, f.fat) + (asleep ? 2 : 0)],
                              aux: [lookLocal.x, lookLocal.y, blur, aging(f)]))
        }

        out += scene.sprites(self, front: true)
        // marine snow up close, in front of the fish
        out += moteSprites(front: true)
        // the snail on the glass
        out += fauna.front(self)
        // mail seahorses (facing the way they're going)
        for c in mails {
            let looks: Float = c.stage == 2 ? c.side : -c.side
            out.append(Sprite(pos: c.pos, dir: [looks >= 0 ? 1 : -1, 0], size: 20, kind: 13, glow: 0.2, phase: c.phase,
                              color: SIMD4(mix(c.color, [1, 0.85, 0.5], t: 0.5), 1), extra: [looks >= 0 ? 1 : -1, c.letter ? 1 : 0, 0, 0]))
        }

        // glass fogging up in front of whoever has been waiting more than 3 min
        for f in fish where f.state == .waiting && !f.leaving && !f.decor && time - f.since > 180 * Self.scale {
            let t = Float(time - f.since - 180 * Self.scale) / Float(Self.scale)
            out.append(Sprite(pos: f.pos + [0, -4], dir: [1, 0], size: f.size * (1.4 + min(1.4, t / 120)), kind: 11,
                              glow: min(1, t / 40), phase: Float(f.phase), color: [0.85, 0.9, 0.95, 1], extra: [1, 0, 0, 0]))
        }

        for p in particles where p.kind == 24 {
            let k = min(1, p.life / 0.4) * (1 - p.life / p.maxLife)
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: 24, glow: k, phase: 0, color: p.color, extra: [1, 0, 0, 0]))
        }
        // rings on the surface (bubbles popping)
        for p in particles where p.kind == 8 {
            let k = 1 - p.life / p.maxLife
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: 8, glow: k * 0.8, phase: 0, color: p.color, extra: [1, 0, 0, 0]))
        }
        for p in particles where p.kind == 2 || p.kind == 4 {
            let k = 1 - p.life / p.maxLife
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: p.kind, glow: k, phase: 0,
                              color: p.color, extra: [1, 0, 0, 0]))
        }
        // foreground: dark, blurred seaweed tufts in the corners, moving more with the parallax
        let shift = gaze * -14
        let tuft = size.y * 0.32
        out.append(Sprite(pos: [size.x * 0.03 + shift.x, tuft * 0.62 + shift.y * 0.3], dir: [1, 0], size: tuft, kind: 20, glow: 0.92,
                          phase: Float(time), color: SIMD4(SIMD3<Float>(0.02, 0.07, 0.06) * (0.6 + 0.4 * light), 1), extra: [1, 0, 0, 0]))
        out.append(Sprite(pos: [size.x * 0.97 + shift.x, tuft * 0.5 + shift.y * 0.3], dir: [1, 0], size: tuft * 0.85, kind: 20, glow: 0.92,
                          phase: Float(time) + 3, color: SIMD4(SIMD3<Float>(0.03, 0.06, 0.07) * (0.6 + 0.4 * light), 1), extra: [1, 0, 0, 0]))

        // quake: everything shakes together
        if scene.shakeOffset != .zero { for i in out.indices { out[i].pos += scene.shakeOffset } }
        // widget mode: a small window, so everything is drawn a little smaller
        if compact { for i in out.indices { out[i].size *= 0.75 } }
        return out
    }
}

// MARK: - utilities

func hsv(_ h: Float, _ s: Float, _ v: Float) -> SIMD3<Float> {
    let i = floorf(h * 6)
    let f = h * 6 - i
    let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
    switch Int(i) % 6 {
    case 0: return [v, t, p]
    case 1: return [q, v, p]
    case 2: return [p, v, t]
    case 3: return [p, q, v]
    case 4: return [t, p, v]
    default: return [v, p, q]
    }
}

func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> { a + (b - a) * t }

func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = max(0, min(1, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
}
