import Foundation
import simd

/// The scene layer: presences that plugins control and one-off effects. The tank owns it; the app draws the labels.
final class Scene {
    private(set) var presences: [Presence] = []

    /// Every kind of presence, by id. Packs can add more.
    private(set) static var kinds: [String: PresenceKind] = {
        let list: [PresenceKind] = [
            PresenceKind(id: "shark", sprite: 25, motion: .swim, size: 58, color: [0.45, 0.53, 0.62], band: 0.32...0.62, sound: "bass"),
            PresenceKind(id: "submarine", sprite: 26, motion: .swim, size: 38, color: [0.95, 0.74, 0.2], band: 0.22...0.45, sound: "sonar"),
            PresenceKind(id: "turtle", sprite: 15, motion: .swim, size: 30, color: [0.45, 0.55, 0.32], band: 0.3...0.65, sound: "flute"),
            PresenceKind(id: "jellyfish", sprite: 5, motion: .drift, size: 24, color: [0.85, 0.55, 1.0], band: 0.4...0.78, sound: "pad"),
            PresenceKind(id: "seahorse", sprite: 13, motion: .hover, size: 20, color: [1.0, 0.68, 0.35], band: 0.35...0.65, sound: "kalimba"),
            PresenceKind(id: "crab", sprite: 14, motion: .walk, size: 20, color: [0.85, 0.35, 0.22], sound: "tap"),
            PresenceKind(id: "starfish", sprite: 17, motion: .sit, size: 18, color: [0.95, 0.5, 0.35], sound: "kalimba"),
            PresenceKind(id: "bottle", sprite: 27, motion: .float, size: 30, color: [0.45, 0.78, 0.6], sound: "glass"),
            PresenceKind(id: "hourglass", sprite: 28, motion: .sit, size: 28, color: [0.62, 0.42, 0.26], meter: true, sound: "tick"),
            PresenceKind(id: "anchor", sprite: 29, motion: .sit, size: 34, color: [0.42, 0.4, 0.38], drops: true, sound: "clang"),
            PresenceKind(id: "flag", sprite: 30, motion: .sit, size: 32, color: [0.35, 0.85, 0.5], sound: "soft"),
            PresenceKind(id: "helm", sprite: 31, motion: .sit, size: 34, color: [0.6, 0.4, 0.22], sound: "clang"),
            PresenceKind(id: "chest", sprite: 23, motion: .sit, size: 22, color: [0.5, 0.31, 0.16], sound: "bell"),
            PresenceKind(id: "pilot", sprite: 45, motion: .glass, size: 11, color: [0.72, 0.6, 0.38], sound: "soft"),
            // the resident assistant's (Assistant.swift): a moray in its burrow, out when it has something to say
            PresenceKind(id: "moray", sprite: 47, motion: .sit, size: 46, color: [0.6, 0.56, 0.3], sound: "kalimba"),
            PresenceKind(id: "battery", sprite: 6, motion: .sit, size: 20, color: [1, 1, 1], meter: true, sound: "bubble"),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()

    static func register(_ k: PresenceKind) { kinds[k.id] = k }
    /// Drops the kinds that came from packs (before the packs are read again).
    static func unregisterPacks() { kinds = kinds.filter { $0.value.pack == nil } }
    static func unregister(_ id: String) { if kinds[id]?.pack != nil { kinds[id] = nil } }

    /// After the packs are read again: the presences of a pack's kind take its new index (or vanish if it's gone).
    func refreshPackKinds() {
        for p in presences {
            if let w = p.wantedKind, let k = Self.kinds[w] {
                p.kind = k; p.wantedKind = nil                         // its pack is here now: the real drawing
            } else if p.kind.sprite == 37 {
                if let k = Self.kinds[p.kind.id] { p.kind = k }
                else {
                    // its pack left (removed or paused): a built-in kind that moves the same way stands in
                    let stand: [PresenceKind.Motion: String] = [.swim: "turtle", .drift: "jellyfish", .hover: "seahorse",
                                                                .walk: "crab", .sit: "flag", .float: "bottle", .glass: "pilot"]
                    p.wantedKind = p.kind.id
                    if let k = Self.kinds[stand[p.kind.motion] ?? "flag"] { p.kind = k }
                }
            }
        }
    }

    /// What the tank can't draw by itself: fireworks and shooting stars live in the visualizer, the whale's song in
    /// the music. (effect, where, color)
    var onEffect: ((String, SIMD2<Float>, SIMD3<Float>) -> Void)?
    /// A presence arrived in a state, or changed state (the app's journal keeps what's worth telling).
    var onPresenceState: ((Presence) -> Void)?

    /// Lightning: how bright the water is right now (0…1).
    private(set) var flash: Float = 0
    /// The lightning's color: a cold blue, or what the plugin or the theme asked for.
    var flashColor: SIMD3<Float> = [0.55, 0.65, 0.85]
    /// Flashes from the music (the storm visualizer): fades fast.
    private var musicFlash: Float = 0
    func flashNow(_ strength: Float, color: SIMD3<Float>) {
        musicFlash = max(musicFlash, min(1, strength))
        flashColor = color
    }
    var lightningAt: Double = -100
    /// Quake: how much the tank shakes right now (0…1).
    private(set) var quake: Float = 0
    var quakeUntil: Double = 0
    /// The shake as an offset, in points (applied to every sprite and to the background's parallax).
    private(set) var shakeOffset: SIMD2<Float> = .zero

    /// A school crossing the tank (the `school` effect).
    struct Swimmer { var pos: SIMD2<Float>; var vel: SIMD2<Float>; var size: Float; var phase: Float; var color: SIMD3<Float>; var y0: Float }
    var school: [Swimmer] = []

    static let effects = ["food", "fireworks", "whale", "splash", "ink", "bubbles", "sparkle", "ring", "scare", "pearl",
                          "lightning", "quake", "school", "shooting-star"]

    /// Voices a plugin can pick with "sound" (Music.sceneSound plays them); "none" is silent.
    static let voices = ["arpeggio", "whale", "bass", "sonar", "glass", "tick", "clang", "bell", "chime", "kalimba", "flute",
                         "pad", "soft", "pluck", "tap", "bubble", "thunder", "rumble", "run", "glissando", "none"]
    /// Each effect's own voice.
    static let effectSounds: [String: String] = [
        "food": "arpeggio", "fireworks": "arpeggio", "whale": "whale", "splash": "bubble", "ink": "bass", "bubbles": "bubble",
        "sparkle": "chime", "ring": "tap", "scare": "glass", "pearl": "chime", "lightning": "thunder", "quake": "rumble",
        "school": "run", "shooting-star": "glissando",
    ]

    /// Plays a voice (voice, cue, source, the state behind it, x 0…1). The app filters it (focus, attention) and plays it.
    var onSound: ((String, SceneCue, String, State?, Float) -> Void)?

    static func checkSound(_ s: String?) -> String? {
        guard let s, !voices.contains(s) else { return nil }
        return "unknown sound: \(s) (use \(voices.joined(separator: ", ")))"
    }

    private func playSound(_ p: Presence, _ cue: SceneCue, _ t: Tank) {
        let voice = p.sound ?? p.kind.sound
        guard voice != "none" else { return }
        onSound?(voice, cue, p.source, p.state, p.pos.x / max(1, t.size.x))
    }

    private static func cue(_ s: State) -> SceneCue? {
        switch s {
        case .waiting: return .waiting
        case .alert: return .alert
        case .error: return .error
        case .done: return .done
        default: return nil
        }
    }

    // MARK: - presences

    func presence(source: String, id: String) -> Presence? { presences.first { $0.id == "\(source):\(id)" } }

    /// The presence under the point (not the ones leaving).
    func presence(at p: SIMD2<Float>) -> Presence? {
        presences.filter { !$0.leaving && $0.alpha > 0.3 && simd_distance(hitCenter($0), p) < max(18, $0.kind.size * 1.05) }
            .min { simd_distance(hitCenter($0), p) < simd_distance(hitCenter($1), p) }
    }

    /// Where its text goes: above the objects on the sand, below the swimmers. (point, above)
    func labelAnchor(_ p: Presence) -> (SIMD2<Float>, above: Bool) {
        // (where there's no floor it rides at the surface: its text hangs under it, as a bottle's does)
        if p.kind.motion.grounded && !Themes.current.floor && p.kind.sprite != 47 { return (p.pos + p.shakeOffset - [0, 6], false) }
        if p.kind.motion.grounded {
            // dressed by the theme (the pond's water wheel for the helm): over that drawing, which has its own height
            if let k = dressed(p) { return (p.pos + p.shakeOffset + [0, k.size * k.extent.y * 1.9 + 4], true) }
            let top: Float = [47: 1.95, 27: 0.8, 28: 1.8, 29: 1.85, 30: 2.15, 31: 1.2, 17: 1.15, 23: 1.6, 6: 0.9, 14: 1.0][p.kind.sprite]
                ?? (p.kind.pack != nil ? p.kind.extent.y * 1.9 : 1.2)
            return (p.pos + p.shakeOffset + [0, p.kind.size * top + 4], true)
        }
        let below: Float = p.kind.motion == .float ? 0.55 : [5: 1.5, 25: 0.8, 26: 0.85, 13: 1.2, 15: 0.95][p.kind.sprite]
            ?? (p.kind.pack != nil ? p.kind.extent.y : 1)
        return (p.pos + p.shakeOffset - [0, p.kind.size * below + 2], false)
    }

    /// What an object on the sand covers on screen, roughly: from the floor up to where its text starts.
    func footprint(_ p: Presence) -> CGRect {
        let at = p.pos + p.shakeOffset, top = labelAnchor(p).0.y - 6
        let half = p.kind.size * (p.kind.pack != nil ? p.kind.extent.x : 1) * 0.6
        return CGRect(x: CGFloat(at.x - half), y: CGFloat(at.y), width: CGFloat(half * 2), height: CGFloat(max(4, top - at.y)))
    }

    /// Objects on the sand are drawn above their anchor point.
    func hitCenter(_ p: Presence) -> SIMD2<Float> {
        p.kind.motion.grounded ? p.pos + [0, p.kind.size * (p.kind.pack != nil ? p.kind.extent.y * 0.9 : 0.4)] : p.pos
    }

    /// Creates or updates. Returns an error for the protocol's response.
    func upsert(_ t: Tank, source: String, id: String, kind kindName: String?, state: State?, label: String?, detail: String?,
                link: String?, value: Float?, color: SIMD3<Float>?, x: Float?, sound: String? = nil, fallback: String? = nil,
                overrideTheme: Bool? = nil) -> String? {
        if let e = Self.checkSound(sound) { return e }
        var kind: PresenceKind?
        var wanted: String?
        if let k = kindName {
            if let known = Self.kinds[k] {
                kind = known
            } else if let f = fallback, let stand = Self.kinds[f] {
                // a pack's kind that isn't here (yet): a built-in one stands in, and it turns into the real one when
                // the pack is installed
                kind = stand
                wanted = k
            } else {
                return "unknown kind: \(k) (use \(Self.kinds.keys.sorted().joined(separator: ", ")), or send \"fallback\": a built-in kind)"
            }
        }
        if let p = presence(source: source, id: id) {
            p.leaving = false
            if kindName != nil { p.wantedKind = wanted }
            if let overrideTheme { p.overrideTheme = overrideTheme }
            if let kind, kind.id != p.kind.id { p.kind = kind; place(p, t, fresh: false) }
            var changed = false
            if let label, !label.isEmpty, label != p.label { p.label = label; changed = true }
            if let detail, detail != p.detail { p.detail = detail.isEmpty ? nil : detail; changed = true }
            if let link { p.link = link.isEmpty ? nil : link }
            if let value { p.value = value }
            if let color { p.color = color }
            if let sound { p.sound = sound }
            if let x, abs(x - (p.askedU >= 0 ? p.askedU : p.u)) > 0.001 { p.u = x; p.askedU = x; place(p, t, fresh: false) }
            if let state, state != p.state { setState(p, state, t); changed = true }
            if changed { p.changedAt = t.time }
            return nil
        }
        guard let kind else { return "a new presence needs \"kind\" (\(Self.kinds.keys.sorted().joined(separator: ", ")))" }
        let u = x ?? spot(for: "\(source):\(id)", kind.motion, t)
        let p = Presence(id: "\(source):\(id)", source: source, kind: kind, state: state ?? .ok, label: label ?? id,
                         u: u, pos: [t.size.x * u, t.size.y * 0.5], now: t.time)
        p.wantedKind = wanted
        p.overrideTheme = overrideTheme ?? false
        p.detail = detail?.isEmpty == false ? detail : nil
        p.link = link
        p.value = value
        p.color = color
        p.sound = sound
        place(p, t, fresh: true)
        presences.append(p)
        if kind.motion == .glass { layoutGlass(t); p.pos = p.home }
        t.burst(at: p.kind.drops ? [p.pos.x, t.size.y - 10] : p.pos, n: kind.motion == .glass ? 3 : 10)
        if p.state == .done { shine(p, t) }
        // arrives: its state's call, or a soft hello
        if p.state == .waiting { p.reminder = t.time }
        playSound(p, Self.cue(p.state) ?? .born, t)
        onPresenceState?(p)
        return nil
    }

    func remove(source: String, id: String, party: Bool, _ t: Tank) {
        guard let p = presence(source: source, id: id), !p.leaving else { return }
        p.leaving = true
        p.party = party
        if party { shine(p, t) }
    }

    /// A spot on the sand picked from the id, away from the scenery and from the other presences on the sand
    /// (their labels need room: at least ~110 points apart when there is space; otherwise the emptiest spot).
    private func spot(for key: String, _ motion: PresenceKind.Motion, _ t: Tank) -> Float {
        // room from its neighbors: the ones on the sand, or the ones floating at the surface
        let taken = presences.filter { !$0.leaving && ($0.kind.motion.grounded ? motion.grounded : $0.kind.motion == motion) }.map(\.u)
        let onSand = motion.grounded
        let gap = max(0.05, 110 / max(1, t.size.x))
        func room(_ u: Float) -> Float { taken.map { abs($0 - u) }.min() ?? 1 }
        var u = 0.1 + Float(fnv(key) % 1000) / 1000 * 0.8
        if room(u) >= gap && !(onSand && t.scenery.blocks(t, t.size.x * u)) { return u }
        // the spot with the most room, among a few candidates
        var best = u, bestRoom: Float = -1
        for i in 0..<40 {
            let c = 0.06 + Float(i) / 39 * 0.88
            guard !(onSand && t.scenery.blocks(t, t.size.x * c)) else { continue }
            if room(c) > bestRoom { best = c; bestRoom = room(c) }
        }
        u = best
        return u
    }

    /// Where it starts (fresh) or goes back to (moved).
    private func place(_ p: Presence, _ t: Tank, fresh: Bool) {
        let w = t.size.x, h = t.size.y
        switch p.kind.motion {
        case .swim:
            if fresh {
                p.dir = p.u < 0.5 ? 1 : -1
                p.pos = [p.dir > 0 ? -40 : w + 40, h * mixf(p.kind.band, p.lane)]
            }
        case .drift, .hover:
            if fresh { p.pos = [w * p.u, h * mixf(p.kind.band, p.lane)] }
        case .float:
            if fresh { p.pos = [w * p.u, h * 0.955] }
        case .glass:
            break       // layoutGlass gives it its place, and it glides there
        case .walk, .sit:
            if p.askedU < 0 { p.askedU = p.u }
            let x = t.scenery.clear(t, w * p.askedU)
            p.u = x / max(1, w)
            p.pos = [x, ground(p, t)]
            if fresh && p.kind.drops { p.pos.y = h + 20; p.landed = false }
        }
    }

    /// The theme changed: the scenery stands elsewhere now, so whoever is on the floor takes its place again, from
    /// where it was asked to be.
    func resettle(_ t: Tank) {
        guard t.size.x > 10 else { return }
        for p in presences where p.kind.motion.grounded && !p.leaving && p.landed { place(p, t, fresh: false) }
    }

    /// Which side glass each source's lights are on (0 left, 1 right): a new source takes the emptier side.
    private var glassSides: [String: Int] = [:]

    /// The lights on the side glass: each source's together, one under the other from high up down to just above the
    /// dark seaweed in the corners (then a second column). One that needs you takes more room, for its text.
    private func layoutGlass(_ t: Tank) {
        let bySource = Dictionary(grouping: presences.filter { $0.kind.motion == .glass && !$0.leaving }, by: \.source)
        glassSides = glassSides.filter { bySource[$0.key] != nil }
        let sources = bySource.keys.sorted()
        for s in sources where glassSides[s] == nil {
            func lights(_ side: Int) -> Int { bySource.reduce(0) { $0 + (glassSides[$1.key] == side ? $1.value.count : 0) } }
            glassSides[s] = lights(0) <= lights(1) ? 0 : 1
        }
        let w = t.size.x, h = t.size.y
        let top = h * 0.8, bottom = h * 0.36
        for side in 0...1 {
            var y = top, column: Float = 0
            for s in sources where glassSides[s] == side {
                for p in bySource[s]!.sorted(by: { $0.id < $1.id }) {
                    let room = 20 + 12 * p.swell
                    if y - room < bottom && y < top { column += 1; y = top }
                    let inset = max(16, w * 0.014) + column * 28
                    p.side = side == 0 ? 1 : -1
                    p.home = [side == 0 ? inset : w - inset, y - room / 2]
                    y -= room
                }
                y -= 12
            }
        }
    }

    private func ground(_ p: Presence, _ t: Tank) -> Float {
        let u = p.pos.x / max(1, t.size.x)
        let lift: Float = p.kind.sprite == 6 ? 2 : p.kind.motion == .walk ? 8 : 1
        // where there's no floor (the open sea) it rides at the surface as flotsam does, bobbing with the waves
        if !Themes.current.floor {
            return t.surfaceY(p.pos.x) - p.kind.size * (p.kind.motion == .walk ? 0.5 : 1.1) + sinf(p.phase * 1.3) * 2
        }
        // one that walks keeps to a lane up front on the floor, before the scenery: it passes in front of the rocks
        // and the chest, never over them
        return t.size.y * t.sand(u) * (p.kind.motion == .walk ? 1 - 0.2 * 2.8 : 1) + lift
    }

    private func setState(_ p: Presence, _ s: State, _ t: Tank) {
        let before = p.state
        p.state = s
        p.since = t.time
        t.ring(at: hitCenter(p), color: color(of: s) ?? [0.85, 0.95, 1], size: p.kind.size * 0.4, grow: 90, life: 0.8)
        if s == .error { p.shake = 1 }
        if s == .done || (before == .error && s != .error) { shine(p, t) }
        if let c = Self.cue(s) {
            if s == .waiting { p.reminder = t.time }
            playSound(p, c, t)
        }
        if s == .born { t.burst(at: p.pos, n: 8) }
        onPresenceState?(p)
    }

    /// What a lamp shows for a state: the helm's hub, a pilot light.
    func lamp(_ s: State) -> SIMD3<Float> {
        color(of: s) ?? (s == .idle ? [0.5, 0.52, 0.55] : s == .busy ? [0.45, 0.75, 1] : [0.35, 0.85, 0.5])
    }

    /// The state's color (nil: the presence's own).
    func color(of s: State) -> SIMD3<Float>? {
        switch s {
        case .waiting: return [1, 0.85, 0.4]
        case .alert: return [1, 0.72, 0.25]
        case .error: return [1, 0.38, 0.32]
        case .done: return [0.6, 1, 0.7]
        default: return nil
        }
    }

    private func shine(_ p: Presence, _ t: Tank) {
        let c = hitCenter(p)
        for i in 0..<10 {
            let a = Float(i) / 10 * 2 * .pi
            t.addParticle(Particle(pos: c + SIMD2(cosf(a), sinf(a)) * p.kind.size * 0.9, vel: SIMD2(cosf(a), sinf(a)) * 14 + [0, 6],
                                   life: 0, maxLife: 1.4, size: 8, grow: 2, kind: 4, color: SIMD4(mix(p.baseColor, [1, 1, 0.85], t: 0.5), 1)))
        }
    }

    // MARK: - simulation

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x, h = t.size.y
        let time = t.time

        // lightning: two quick flashes
        let lt = Float(time - lightningAt)
        flash = lt < 0 || lt > 1.2 ? 0 : max(expf(-lt * 9), lt > 0.22 ? 0.75 * expf(-(lt - 0.22) * 6) : 0)
        musicFlash *= expf(-dt * 7)
        flash = max(flash, musicFlash)
        // quake: a shake that fades
        quake = time < quakeUntil ? Float(quakeUntil - time) / 2.6 : 0
        shakeOffset = quake > 0 ? [sinf(Float(time) * 53) * 5 * quake, sinf(Float(time) * 41 + 1) * 3 * quake] : .zero

        if presences.contains(where: { $0.kind.motion == .glass }) { layoutGlass(t) }
        for p in presences {
            p.phase += dt
            p.alpha += ((p.leaving ? 0 : 1) - p.alpha) * min(1, dt * 2.5)
            if p.shake > 0 { p.shake = max(0, p.shake - dt * 1.5) }
            let pace: Float = p.state == .busy ? 1.7 : p.state == .idle ? 0.45 : p.state == .error ? 0.35 : 1
            switch p.kind.motion {
            case .swim:
                if time > p.laneAt { p.lane = Float.random(in: 0...1); p.laneAt = time + Double.random(in: 8...20) }
                var goalY = h * mixf(p.kind.band, p.lane)
                if p.state == .error { goalY = h * 0.2 }
                if p.state == .waiting && !p.leaving {
                    // comes to the front of the glass, in the middle, and waits
                    let goal: SIMD2<Float> = [w * mixf(0.35...0.65, p.u), h * 0.5]
                    let d = goal - p.pos
                    p.vel += ((simd_length(d) > 4 ? simd_normalize(d) * min(60, simd_length(d)) : .zero) - p.vel) * min(1, dt * 1.5)
                    if abs(p.vel.x) > 3 { p.dir = p.vel.x > 0 ? 1 : -1 }
                } else {
                    let speed: Float = (p.kind.id == "submarine" ? 22 : p.kind.id == "turtle" ? 26 : 40) * pace
                    if p.leaving { p.dir = p.pos.x < w / 2 ? -1 : 1 }
                    else if p.pos.x < w * 0.08 { p.dir = 1 } else if p.pos.x > w * 0.92 { p.dir = -1 }
                    let target: SIMD2<Float> = [p.dir * speed, (goalY - p.pos.y) * 0.4]
                    p.vel += (target - p.vel) * min(1, dt * 1.2)
                }
                p.pos += p.vel * dt
                p.pos.y += sinf(p.phase * 0.6) * 4 * dt
            case .drift:
                let goalY = p.state == .error ? h * 0.22 : h * mixf(p.kind.band, 0.5 + 0.5 * sinf(p.phase * 0.12 * pace))
                p.pos.y += (goalY - p.pos.y) * min(1, dt * 0.4)
                p.pos.x += ((w * p.u + sinf(p.phase * 0.21) * 30) - p.pos.x) * min(1, dt * 0.5)
            case .hover:
                let goalY = p.state == .error ? h * 0.25 : h * mixf(p.kind.band, p.lane) + sinf(p.phase * 1.4 * pace) * 6
                p.pos.y += (goalY - p.pos.y) * min(1, dt * 1.2)
                p.pos.x += ((w * p.u) - p.pos.x) * min(1, dt * 0.8)
                p.dir = sinf(p.phase * 0.1) >= 0 ? 1 : -1
            case .float:
                // bobs with the waves and drifts a little around its spot; in error it sinks halfway
                let sunk: Float = p.state == .error ? 0.03 : 0
                // rides the actual surface (waves included), a little under it
                p.pos.y += (t.surfaceY(p.pos.x) - h * (0.01 + sunk) + sinf(p.phase * 1.3) * 2 - p.pos.y) * min(1, dt * 4)
                p.pos.x += ((w * p.u + sinf(p.phase * 0.11) * 30) - p.pos.x) * min(1, dt * 0.6)
            case .walk:
                let home = w * p.u
                if abs(p.pos.x - home) > 70 { p.dir = p.pos.x > home ? -1 : 1 }
                if p.state != .idle && p.state != .error && p.state != .waiting {
                    let next = p.pos.x + p.dir * 22 * pace * dt
                    p.pos.x = next
                }
                p.pos.y = ground(p, t)
            case .glass:
                p.swell += ((p.needsYou && !p.leaving ? 1 : 0) - p.swell) * min(1, dt * 4)
                p.pos += (p.home - p.pos) * min(1, dt * 3)
                p.dir = p.side
            case .sit:
                // the moray comes out of its burrow while it has something going on, and goes back in to rest
                if p.kind.sprite == 47 {
                    var out: Float = p.leaving || p.state == .ok || p.state == .idle ? 0.22 : 1
                    if out < 1 && !p.leaving {
                        // resting isn't still: it edges out of the door and back as it breathes, takes a longer look
                        // around every half minute or so, and comes all the way out when it's called (a click)
                        let tm = Float(t.time) + Float(abs(p.id.hashValue % 97))
                        out += 0.1 * max(0, sinf(tm * 0.6))
                        if (tm / 31).truncatingRemainder(dividingBy: 1) < 0.14 { out = 0.62 }
                        if t.time < p.outUntil { out = 1 }
                    }
                    p.swell += (out - p.swell) * min(1, dt * 2.2)
                }
                if p.kind.sprite == 47 && !Themes.current.floor {
                    // where there's no floor (the open sea) there's no rock to live in: it swims free, a slow winding
                    // round low in the water, and comes up toward the middle while it has something to say
                    p.landed = true
                    let tt = Float(t.time) * 0.045 + 1.7
                    let goal: SIMD2<Float> = [t.size.x * (0.5 + 0.33 * sinf(tt) + 0.06 * sinf(tt * 2.3 + 1)),
                                              t.size.y * (0.2 + 0.2 * p.swell + 0.05 * sinf(tt * 1.7))]
                    let before = p.pos.x
                    p.pos += (goal - p.pos) * min(1, dt * 0.9)
                    let vx = (p.pos.x - before) / max(dt, 0.001)
                    if abs(vx) > 2 { p.dir = vx > 0 ? 1 : -1 }
                } else if !p.landed {
                    p.pos.y -= 320 * dt
                    if p.pos.y <= ground(p, t) {
                        p.landed = true
                        p.pos.y = ground(p, t)
                        // lands: a puff of sand
                        for _ in 0..<5 {
                            t.addParticle(Particle(pos: p.pos + [Float.random(in: -10...10), 2], vel: [Float.random(in: -18...18), Float.random(in: 6...16)],
                                                   life: 0, maxLife: 2, size: 10, grow: 9, kind: 10, color: [0.5, 0.43, 0.3, 1]))
                        }
                    }
                } else {
                    p.pos.x = t.size.x * p.u
                    p.pos.y = ground(p, t)
                }
            }
            if p.kind.id == "helm" { p.spin += dt * (p.state == .busy ? 1.1 : p.state == .waiting ? 0.25 : 0) }
            // a light on the glass only shines: no bubbles, no ink
            if p.kind.motion == .glass { continue }
            // busy: small bubbles rise from it
            if p.state == .busy && !p.leaving && time > p.bubbleAt {
                p.bubbleAt = time + Double.random(in: 0.35...0.9)
                t.bubble(at: hitCenter(p) + [Float.random(in: -6...6), p.kind.size * 0.4], size: Float.random(in: 1.5...3))
            }
            // waiting: calls again every 2.5 min
            if p.state == .waiting && !p.leaving && time - p.reminder > 150 {
                p.reminder = time
                playSound(p, .waiting, t)
            }
            // error: a little ink now and then
            if p.state == .error && !p.leaving && time > p.inkAt {
                p.inkAt = time + Double.random(in: 2.5...4.5)
                t.ink(at: hitCenter(p), n: 1, color: [0.12, 0.08, 0.1])
            }
        }
        presences.removeAll { p in
            guard p.leaving else { return false }
            if p.kind.motion == .swim { return p.pos.x < -80 || p.pos.x > w + 80 || p.alpha < 0.02 }
            return p.alpha < 0.02
        }

        for i in school.indices {
            school[i].phase += dt * 9
            school[i].pos += school[i].vel * dt
            school[i].pos.y = school[i].y0 + sinf(school[i].pos.x * 0.012 + Float(i)) * 10
        }
        school.removeAll { $0.pos.x < -120 || $0.pos.x > w + 120 }
    }

    /// `front`: the ones waiting for you are drawn in front of the fish.
    /// The theme's looks for built-in kinds ("bottle": "floating-lantern"), and whether they're on (Preferences).
    var themeLooks: [String: String] = [:]
    var dressByTheme = true
    /// Built-in variants a theme can dress a built-in kind in ("looks": {"shark": "hammerhead"}): of which kind, and
    /// the number its drawing gets (extra.z).
    static let variants: [String: (of: String, n: Float)] = ["hammerhead": ("shark", 1), "rusty-helm": ("helm", 1), "deep-bottle": ("bottle", 1), "safe": ("chest", 1), "fish-trap": ("chest", 2),
                                                             "egg-case": ("eggs", 1), "root-eggs": ("eggs", 2)]
}

/// A value inside a range, by a fraction (0…1).
func mixf(_ r: ClosedRange<Float>, _ t: Float) -> Float { r.lowerBound + (r.upperBound - r.lowerBound) * t }
