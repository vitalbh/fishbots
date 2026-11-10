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
        // picked by hand: for the project (fish menu), or for the whole agent (Preferences → Agents)
        let picked = FishKinds.override(for: f.projectKey) ?? (isAgent ? FishKinds.agentKind(f.source) : nil)
        f.baseKind = picked ?? fishKind(f)
        f.pickedKind = picked != nil
        f.species = FishKinds.index(of: FishKinds.dressed(f.baseKind, picked: f.pickedKind))
    }
}

final class Fish {
    /// Its kind before the theme dresses it (the provider's, or the one picked by hand in the fish menu).
    var baseKind = "oval"
    var pickedKind = false
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
    /// You were looking at its session when it last called (InView): it calls without sound.
    var inView = false
    /// Asking InView now (its call waits for the answer), and when it last answered.
    var looking = false
    var lookedAt = Date.distantPast
    /// The state change (its `since`) that answer was for: a new call waits for an answer about itself.
    var lookedSince: Double = -1
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
    /// The album art of what it's playing (the music fish), for its card.
    var art: CGImage?
    var stateLabel: String { mood ?? state.label }
    /// How far along it is (seconds), for the card's bar: the music fish's song.
    var progress: (() -> (pos: Double, dur: Double, playing: Bool)?)?
    /// The agent's last reply (clean text, no markdown), for the card.
    var lastReply: String?
    /// The reply ended with a question for you (the final part).
    var asked: String?
    /// A quiet question that needs no attention (no notification, nothing read aloud): the music fish offering the
    /// aquarium's music when yours pauses. Shown like an agent's question; a click answers it.
    var offer: String?
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
