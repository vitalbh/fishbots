import Foundation
import simd

/// What happened, for the sound. The app's music plays it (Music.sceneSound); the screen saver is silent.
enum SceneCue { case born, waiting, alert, error, done, effect }

/// What a presence is: how it moves and which sprite draws it. See docs/scene.md.
struct PresenceKind {
    enum Motion {
        case swim, drift, hover, walk, sit
        case float     // bobs at the surface, tilting with the waves
        /// On the sand (their text goes above them).
        var grounded: Bool { self == .sit || self == .walk }
    }
    let id: String
    /// Sprite kind in the shader (25–30 are the presences' own drawings; the rest are reused).
    let sprite: Float
    let motion: Motion
    /// Size in points.
    let size: Float
    let color: SIMD3<Float>
    /// Height band (fraction of the tank) where swimmers, drifters and hoverers stay.
    var band: ClosedRange<Float> = 0.3...0.6
    /// Shows `value` in its drawing (hourglass, battery): the label adds the percentage.
    var meter = false
    /// Drops from the surface when it arrives (heavy objects).
    var drops = false
    /// Its voice (Scene.voices), when its state changes.
    var sound = "soft"
    /// Hangs on the side glass while there's room (helms); otherwise it sits on the sand.
    var wall = false
    /// From a pack: its index in PackPresences (the sprite is kind 37) and its quad (width, height relative to size).
    var pack: Int? = nil
    var extent: SIMD2<Float> = [1, 1]
}

/// A creature or object a plugin keeps in the tank, with a state and its own text.
final class Presence {
    let id: String             // "source:presence"
    let source: String
    var kind: PresenceKind
    var state: State
    var label: String
    var detail: String?
    var link: String?
    var value: Float?
    var color: SIMD3<Float>?
    /// The plugin's voice for it ("none": silent); nil: the kind's.
    var sound: String?
    /// Last "waiting" call (it's repeated every 2.5 min, like the fish).
    var reminder: Double = 0
    /// The helm's turn (radians): it turns while busy.
    var spin: Float = 0
    /// Its place on the side glass (even: left, odd: right; /2: the level from the top), or nil when it's on the sand.
    var wallSlot: Int?
    var onWall: Bool { wallSlot != nil }
    /// Home position (0…1 of the width).
    var u: Float
    var pos: SIMD2<Float>
    var vel: SIMD2<Float> = .zero
    var dir: Float = 1
    var phase: Float
    var since: Double
    /// Something changed (state or text): the detail shows for a few seconds.
    var changedAt: Double
    var leaving = false
    /// The pack kind it asked for, while it's drawn by a built-in stand-in (the pack isn't loaded, or left).
    var wantedKind: String?
    /// The plugin wants its own drawing even where the theme dresses this kind differently ("override_theme": true).
    var overrideTheme = false
    var party = false
    var alpha: Float = 0
    var shake: Float = 0
    var inkAt: Double = 0
    var bubbleAt: Double = 0
    /// Heavy objects fall from the surface until they land.
    var landed = true
    /// Swim height within the band (0…1), and when to pick a new one.
    var lane: Float
    var laneAt: Double = 0

    init(id: String, source: String, kind: PresenceKind, state: State, label: String, u: Float, pos: SIMD2<Float>, now: Double) {
        self.id = id
        self.source = source
        self.kind = kind
        self.state = state
        self.label = label
        self.u = u
        self.pos = pos
        self.phase = Float.random(in: 0...6)
        self.since = now
        self.changedAt = now
        self.lane = Float.random(in: 0...1)
    }

    var baseColor: SIMD3<Float> { color ?? kind.color }
    /// Needs you: the detail stays on screen.
    var needsYou: Bool { [.waiting, .alert, .error].contains(state) }
    /// The little shake when it goes into error (the label shakes along).
    var shakeOffset: SIMD2<Float> { shake > 0 ? [sinf(phase * 40) * 3 * shake, 0] : .zero }
}

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
            PresenceKind(id: "helm", sprite: 31, motion: .sit, size: 34, color: [0.6, 0.4, 0.22], sound: "clang", wall: true),
            PresenceKind(id: "chest", sprite: 23, motion: .sit, size: 22, color: [0.5, 0.31, 0.16], sound: "bell"),
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
                                                                .walk: "crab", .sit: "flag", .float: "bottle"]
                    p.wantedKind = p.kind.id
                    if let k = Self.kinds[stand[p.kind.motion] ?? "flag"] { p.kind = k }
                }
            }
        }
    }

    /// What the tank can't draw by itself: fireworks and shooting stars live in the visualizer, the whale's song in
    /// the music. (effect, where, color)
    var onEffect: ((String, SIMD2<Float>, SIMD3<Float>) -> Void)?

    /// Lightning: how bright the water is right now (0…1).
    private(set) var flash: Float = 0
    /// The lightning's color: a cold blue, or what the plugin or the theme asked for.
    private(set) var flashColor: SIMD3<Float> = [0.55, 0.65, 0.85]
    /// Flashes from the music (the storm visualizer): fades fast.
    private var musicFlash: Float = 0
    func flashNow(_ strength: Float, color: SIMD3<Float>) {
        musicFlash = max(musicFlash, min(1, strength))
        flashColor = color
    }
    private var lightningAt: Double = -100
    /// Quake: how much the tank shakes right now (0…1).
    private(set) var quake: Float = 0
    private var quakeUntil: Double = 0
    /// The shake as an offset, in points (applied to every sprite and to the background's parallax).
    private(set) var shakeOffset: SIMD2<Float> = .zero

    /// A school crossing the tank (the `school` effect).
    private struct Swimmer { var pos: SIMD2<Float>; var vel: SIMD2<Float>; var size: Float; var phase: Float; var color: SIMD3<Float>; var y0: Float }
    private var school: [Swimmer] = []

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
        if p.onWall { return (p.pos + p.shakeOffset - [0, p.kind.size * 1.15 + 2], false) }
        if p.kind.motion.grounded {
            let top: Float = [27: 0.8, 28: 1.8, 29: 1.85, 30: 2.15, 31: 2.05, 17: 1.15, 23: 1.6, 6: 0.9, 14: 1.0][p.kind.sprite]
                ?? (p.kind.pack != nil ? p.kind.extent.y * 1.9 : 1.2)
            return (p.pos + p.shakeOffset + [0, p.kind.size * top + 4], true)
        }
        let below: Float = p.kind.motion == .float ? 0.55 : [5: 1.5, 25: 0.8, 26: 0.85, 13: 1.2, 15: 0.95][p.kind.sprite]
            ?? (p.kind.pack != nil ? p.kind.extent.y : 1)
        return (p.pos + p.shakeOffset - [0, p.kind.size * below + 2], false)
    }

    /// Objects on the sand are drawn above their anchor point.
    private func hitCenter(_ p: Presence) -> SIMD2<Float> {
        p.kind.motion.grounded && !p.onWall ? p.pos + [0, p.kind.size * (p.kind.pack != nil ? p.kind.extent.y * 0.9 : 0.4)] : p.pos
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
            if let x, abs(x - p.u) > 0.001 { p.u = x; place(p, t, fresh: false) }
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
        t.burst(at: p.kind.drops ? [p.pos.x, t.size.y - 10] : p.pos, n: 10)
        if p.state == .done { shine(p, t) }
        // arrives: its state's call, or a soft hello
        if p.state == .waiting { p.reminder = t.time }
        playSound(p, Self.cue(p.state) ?? .born, t)
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
        case .walk, .sit:
            // helms go on the side glass first, while there's room
            if p.kind.wall {
                if p.wallSlot == nil, let slot = freeWallSlot(t) { p.wallSlot = slot }
                if let slot = p.wallSlot, let at = wallPosition(slot, p.kind.size, t) { p.pos = at; return }
                p.wallSlot = nil
            }
            let x = t.scenery.clear(t, w * p.u)
            p.u = x / max(1, w)
            p.pos = [x, ground(p, t)]
            if fresh && p.kind.drops { p.pos.y = h + 20; p.landed = false }
        }
    }

    /// Where a wall slot is: alternating sides, from high up down to just above the dark seaweed in the corners.
    private func wallPosition(_ slot: Int, _ size: Float, _ t: Tank) -> SIMD2<Float>? {
        let w = t.size.x, h = t.size.y
        let spacing = size * 3.1
        let y = h * 0.8 - Float(slot / 2) * spacing
        guard y > h * 0.38 else { return nil }
        let x = slot % 2 == 0 ? max(size * 1.6, w * 0.045) : w - max(size * 1.6, w * 0.045)
        return [x, y]
    }

    private func freeWallSlot(_ t: Tank) -> Int? {
        let used = Set(presences.filter { !$0.leaving }.compactMap(\.wallSlot))
        for slot in 0..<40 where !used.contains(slot) {
            guard wallPosition(slot, 34, t) != nil else { return nil }
            return slot
        }
        return nil
    }

    private func ground(_ p: Presence, _ t: Tank) -> Float {
        let u = p.pos.x / max(1, t.size.x)
        let lift: Float = p.kind.sprite == 6 ? 2 : p.kind.motion == .walk ? 7 : 1
        return t.size.y * t.sand(u) + lift
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
    }

    /// The state's color (nil: the presence's own).
    private func color(of s: State) -> SIMD3<Float>? {
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

    // MARK: - effects

    /// Plays an effect. Returns an error for the protocol's response.
    /// The sand the quake stirs up: the theme's sand, a little lighter.
    private var quakeDust: SIMD4<Float> {
        let s = Themes.current.uniforms.sandLight
        return [min(1, s.x * 1.25 + 0.06), min(1, s.y * 1.25 + 0.06), min(1, s.z * 1.25 + 0.06), 1]
    }

    func effect(_ name: String, _ t: Tank, source: String, label: String?, x: Float?, y: Float?, color: SIMD3<Float>?,
                sound: String? = nil) -> String? {
        if let e = Self.checkSound(sound) { return e }
        let w = t.size.x, h = t.size.y
        let at: SIMD2<Float> = [w * (x ?? Float.random(in: 0.25...0.75)), h * (y ?? Float.random(in: 0.35...0.65))]
        // the theme's way: another effect in its place, and its color unless the plugin sent one
        var name = name
        let look = Self.effects.contains(name) ? Themes.current.effects[name] : nil
        if let other = look?.as_, other != name, Self.effects.contains(other) { name = other }
        let tint = color ?? look?.color
        var icon = "✨"
        switch name {
        case "food":
            let arps = t.pendingArp
            t.event(source: source, name: name, label: label)
            // another voice (or none) instead of the arpeggio
            if let sound, sound != "arpeggio" {
                t.pendingArp = arps
                if sound != "none" { onSound?(sound, .effect, source, nil, at.x / max(1, w)) }
            }
            return nil
        case "fireworks":
            icon = "🎆"
            onEffect?(name, [at.x, h * (y ?? 0.62)], tint ?? [1, 0.82, 0.45])
        case "whale":
            icon = "🐋"
            if let sound, sound != "whale" {
                // the whale without its song (another voice plays below)
                let song = t.fauna.onWhale
                t.fauna.onWhale = nil
                t.fauna.callWhale(t)
                t.fauna.onWhale = song
            } else {
                t.fauna.callWhale(t)
            }
        case "splash":
            icon = "💦"
            t.splash(at: [at.x, h * 0.965])
        case "ink":
            icon = "🦑"
            t.ink(at: at, n: 9, color: tint ?? [0.06, 0.04, 0.1])
        case "bubbles":
            icon = "🫧"
            let x0 = at.x
            for i in 0..<14 {
                t.after(Double(i) * 0.09) { [weak t] in
                    guard let t else { return }
                    t.bubble(at: [x0 + Float.random(in: -10...10), t.size.y * t.sand(x0 / max(1, t.size.x)) + 4], size: Float.random(in: 2...6))
                }
            }
        case "sparkle":
            for i in 0..<14 {
                let a = Float(i) / 14 * 2 * .pi
                t.addParticle(Particle(pos: at + SIMD2(cosf(a), sinf(a)) * 26, vel: SIMD2(cosf(a), sinf(a)) * 22 + [0, 6], life: 0,
                                       maxLife: 1.6, size: 9, grow: 2, kind: 4, color: SIMD4(tint ?? [1, 0.95, 0.75], 1)))
            }
        case "ring":
            icon = "◯"
            t.ring(at: at, color: tint ?? [0.85, 0.95, 1], size: 16, grow: 160, life: 1.4)
        case "scare":
            icon = "⚡︎"
            t.scare(at)
        case "pearl":
            icon = "⚪︎"
            t.pearls.add(color: tint ?? [0.95, 0.92, 0.85], title: label ?? source, project: source, in: t)
        case "lightning":
            icon = "⚡︎"
            lightningAt = t.time
            flashColor = tint.map { $0 * 0.75 } ?? [0.55, 0.65, 0.85]
            onEffect?(name, at, tint ?? [0.8, 0.88, 1])
        case "quake":
            icon = "〰︎"
            quakeUntil = t.time + 2.6
            t.motes.stir(t, at: [w / 2, 0], radius: max(w, h) * 1.2, strength: 60)
            for i in 0..<22 {
                let u = Float(i) / 21
                let px = w * (0.04 + 0.92 * u)
                t.addParticle(Particle(pos: [px, h * t.sand(px / max(1, w)) + 4], vel: [Float.random(in: -14...14), Float.random(in: 14...34)],
                                       life: 0, maxLife: Float.random(in: 3...4.5), size: Float.random(in: 22...34), grow: 16, kind: 10,
                                       color: quakeDust))
            }
            for f in t.fish where !f.leaving && !f.decor { f.fearUntil = t.time + 0.8; f.fearFrom = [f.pos.x, 0]; f.vel += [Float.random(in: -80...80), 120] }
        case "school":
            icon = "🐟"
            let dir: Float = Bool.random() ? 1 : -1
            let y0 = h * (y ?? Float.random(in: 0.35...0.7))
            // the theme's first school crosses (the usual silversides otherwise)
            let c = tint ?? Themes.current.schools?.first?.color ?? [0.7, 0.85, 1]
            for i in 0..<13 {
                let off: SIMD2<Float> = [Float(i % 5) * -18 * dir + Float.random(in: -8...8), Float(i / 5) * 14 - 14 + Float.random(in: -5...5)]
                school.append(Swimmer(pos: [(dir > 0 ? -40 : w + 40) + off.x, y0 + off.y], vel: [dir * Float.random(in: 92...104), 0],
                                      size: Float.random(in: 7...9.5), phase: Float.random(in: 0...6), color: mix(c, [1, 1, 1], t: Float.random(in: 0...0.25)),
                                      y0: y0 + off.y))
            }
        case "shooting-star":
            icon = "🌠"
            onEffect?(name, [at.x, h * 0.93], tint ?? [1, 0.95, 0.8])
        default:
            return "unknown effect: \(name) (use \(Self.effects.joined(separator: ", ")))"
        }
        let voice = sound ?? Self.effectSounds[name] ?? "none"
        if voice != "none" && !(name == "whale" && voice == "whale") { onSound?(voice, .effect, source, nil, at.x / max(1, w)) }
        if let label, !label.isEmpty {
            t.notice = (label, t.time)
            t.noticeIcon = icon
        }
        return nil
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
                    if t.scenery.blocks(t, next) && !t.scenery.blocks(t, p.pos.x) { p.dir = -p.dir } else { p.pos.x = next }
                }
                p.pos.y = ground(p, t)
            case .sit where p.onWall:
                if let slot = p.wallSlot, let at = wallPosition(slot, p.kind.size, t) { p.pos += (at - p.pos) * min(1, dt * 2.5) }
                else { p.wallSlot = nil; place(p, t, fresh: false) }   // no room anymore (smaller window): to the sand
            case .sit:
                if !p.landed {
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
            // a place freed up on the glass: one from the sand goes up there (gliding)
            if p.kind.wall && !p.onWall && !p.leaving && p.landed, let slot = freeWallSlot(t) { p.wallSlot = slot }
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

    // MARK: - sprites

    /// `front`: the ones waiting for you are drawn in front of the fish.
    /// The theme's looks for built-in kinds ("bottle": "floating-lantern"), and whether they're on (Preferences).
    var themeLooks: [String: String] = [:]
    var dressByTheme = true

    /// Built-in variants a theme can dress a built-in kind in ("looks": {"shark": "hammerhead"}): of which kind, and
    /// the number its drawing gets (extra.z).
    static let variants: [String: (of: String, n: Float)] = ["hammerhead": ("shark", 1), "rusty-helm": ("helm", 1), "deep-bottle": ("bottle", 1), "safe": ("chest", 1), "fish-trap": ("chest", 2)]
    func variant(_ p: Presence) -> Float {
        guard dressByTheme, !p.overrideTheme, let id = themeLooks[p.kind.id], let v = Self.variants[id], v.of == p.kind.id else { return 0 }
        return v.n
    }

    /// The kind whose drawing this presence wears: a pack kind the theme dresses it in (same motion), or its own.
    func dressed(_ p: Presence) -> PresenceKind? {
        guard dressByTheme, !p.overrideTheme, p.kind.pack == nil, let id = themeLooks[p.kind.id],
              let k = Self.kinds[id], k.pack != nil, k.motion == p.kind.motion else { return nil }
        return k
    }

    func sprites(_ t: Tank, front: Bool) -> [Sprite] {
        var out: [Sprite] = []
        let lit = 0.55 + 0.45 * t.light
        let pulse = 0.5 + 0.5 * sinf(Float(t.time) * 4)
        for p in presences where (p.state == .waiting && !p.leaving) == front && (!t.compact || p.needsYou) {
            let dress = dressed(p)
            var c = p.color ?? dress?.color ?? p.kind.color
            var glow: Float = 0
            switch p.state {
            case .idle: c *= 0.7
            case .alert: c = mix(c, [1, 0.72, 0.25], t: 0.45); glow = 0.25 + 0.25 * pulse
            case .error:
                let g = (c.x + c.y + c.z) / 3
                c = mix(SIMD3(repeating: g), [0.75, 0.32, 0.3], t: 0.45) * 0.85
                glow = 0.15 + 0.15 * pulse
            case .waiting: glow = 0.35 + 0.35 * pulse
            case .done: if t.time - p.since < 3 { glow = 0.6 * Float(1 - (t.time - p.since) / 3) }
            default: break
            }
            // the flag's cloth is the state's color (gray when idle: nothing to say)
            if p.kind.id == "flag" {
                if let s = color(of: p.state) { c = s } else if p.state == .idle { c = [0.5, 0.52, 0.55] }
            }
            // a helm dressed by the theme: its drawing's color is the hub's (the state's), as the helm's own
            if p.kind.id == "helm", dress != nil {
                c = color(of: p.state) ?? (p.state == .idle ? [0.5, 0.52, 0.55] : p.state == .busy ? [0.45, 0.75, 1] : [0.35, 0.85, 0.5])
            }
            c *= lit
            let a = p.alpha
            let shake = p.shakeOffset
            let center = hitCenter(p) + shake
            // a soft halo in the state's color, behind it
            if glow > 0.01 {
                let sc = color(of: p.state) ?? p.baseColor
                out.append(Sprite(pos: center, dir: [1, 0], size: p.kind.size * 0.75, kind: 4, glow: glow * 0.5 * a, phase: 0,
                                  color: SIMD4(sc, 1), extra: [1, 0, 0, 0]))
            }
            let pos = p.pos + shake
            let value = p.value ?? 1
            // dressed by the theme: the pack kind's drawing, moving as the plugin's kind does
            if let dk = dress, let i = dk.pack, i < PackPresences.all.count {
                let mirrored = p.kind.motion == .swim || p.kind.motion == .hover
                let tilt: Float = p.kind.motion == .swim ? max(-0.25, min(0.25, p.vel.y / 120))
                    : p.kind.motion == .float ? sinf(p.phase * 1.1) * 0.22 : 0
                let theta = !mirrored || p.dir >= 0 ? tilt : .pi - tilt
                let up: Float = p.kind.motion.grounded && !p.onWall ? dk.extent.y * 0.9 : 0
                out.append(Sprite(pos: pos + [0, dk.size * up], dir: [cosf(theta), sinf(theta)], size: dk.size, kind: 37,
                                  glow: glow, phase: p.phase * (p.state == .busy ? 1.8 : 1), color: SIMD4(c, a),
                                  extra: [mirrored ? p.dir : 1, value, Float(i), PackPresences.stateCode(p.state)],
                                  aux: [dk.extent.x, dk.extent.y, 0, 0]))
                continue
            }
            switch p.kind.sprite {
            case 5:      // jellyfish
                out.append(Sprite(pos: pos, dir: [1, 0], size: p.kind.size, kind: 5, glow: 0.25 + glow, phase: p.phase * 1.3,
                                  color: SIMD4(c, 0.8 * a), extra: [1, 0, 0, 0]))
            case 6:      // battery: the level is the glow
                out.append(Sprite(pos: pos, dir: [1, 0], size: p.kind.size, kind: 6, glow: value, phase: p.phase,
                                  color: [1, 1, 1, a], extra: [1, p.state == .busy ? 1 : 0, 0, 0]))
            case 13:     // seahorse
                out.append(Sprite(pos: pos, dir: [p.dir, 0], size: p.kind.size, kind: 13, glow: 0.2 + glow, phase: p.phase,
                                  color: SIMD4(c, a), extra: [p.dir, 0, 0, 0]))
            case 14:     // crab
                out.append(Sprite(pos: pos, dir: [1, 0], size: p.kind.size, kind: 14, glow: p.state == .busy || p.state == .ok ? 1 : 0,
                                  phase: p.phase, color: SIMD4(c, a), extra: [1, 0, 0, 0]))
            case 15:     // turtle
                out.append(Sprite(pos: pos, dir: [p.dir, 0], size: p.kind.size, kind: 15, glow: 0, phase: p.phase,
                                  color: SIMD4(c, a), extra: [p.dir, 0, 0, 0]))
            case 31:     // helm: wooden wheel; the hub takes the state's color, and it turns while busy (extra.yzw: hub color)
                let hub: SIMD3<Float> = color(of: p.state) ?? (p.state == .idle ? [0.5, 0.52, 0.55]
                                                                : p.state == .busy ? [0.45, 0.75, 1] : [0.35, 0.85, 0.5])
                let wobble: Float = p.state == .error ? sinf(p.phase * 7) * 0.06 : sinf(p.phase * 0.6) * 0.03
                // (alpha above 1.5: rusted)
                out.append(Sprite(pos: pos + [0, p.onWall ? 0 : p.kind.size * 1.0], dir: [1, 0], size: p.kind.size, kind: 31, glow: glow,
                                  phase: p.spin + wobble, color: SIMD4(c, a + 2 * variant(p)), extra: [1, hub.x * lit, hub.y * lit, hub.z * lit]))
            case 23:     // chest: glows when done or waiting
                let open: Float = p.state == .done || p.state == .waiting ? 1 : 0.25
                out.append(Sprite(pos: pos + [0, p.kind.size * 0.55], dir: [1, 0], size: p.kind.size, kind: 23, glow: open, phase: Float(t.time),
                                  color: SIMD4(c, a), extra: [1, open > 0.5 ? 1 : 0, variant(p), 0]))
            case 37:     // a pack's presence: its own drawing (extra.z: its index, extra.w: its state)
                guard let i = p.kind.pack, i < PackPresences.all.count else { break }
                let mirrored = p.kind.motion == .swim || p.kind.motion == .hover
                let tilt: Float = p.kind.motion == .swim ? max(-0.25, min(0.25, p.vel.y / 120))
                    : p.kind.motion == .float ? sinf(p.phase * 1.1) * 0.22 : 0
                let theta = !mirrored || p.dir >= 0 ? tilt : .pi - tilt
                let up: Float = p.kind.motion.grounded && !p.onWall ? p.kind.extent.y * 0.9 : 0   // its feet (c.y = -0.9) on the sand
                out.append(Sprite(pos: pos + [0, p.kind.size * up], dir: [cosf(theta), sinf(theta)], size: p.kind.size, kind: 37,
                                  glow: glow, phase: p.phase * (p.state == .busy ? 1.8 : 1), color: SIMD4(c, a),
                                  extra: [mirrored ? p.dir : 1, value, Float(i), PackPresences.stateCode(p.state)],
                                  aux: [p.kind.extent.x, p.kind.extent.y, 0, 0]))
            default:
                // the presences' own drawings (25–30) and the static ones (starfish)
                let up: Float = p.kind.motion.grounded ? [27: 0.3, 28: 0.85, 29: 0.85, 30: 1.0, 17: 0.15][p.kind.sprite] ?? 0 : 0
                // swimmers face where they go, like the fish: rotated by π - tilt and mirrored when going left
                let mirrored = p.kind.motion == .swim || p.kind.motion == .hover
                let tilt: Float = p.kind.motion == .swim ? max(-0.25, min(0.25, p.vel.y / 120))
                    : p.kind.motion == .float ? sinf(p.phase * 1.1) * 0.22 : 0
                let theta = !mirrored || p.dir >= 0 ? tilt : .pi - tilt
                out.append(Sprite(pos: pos + [0, p.kind.size * up], dir: [cosf(theta), sinf(theta)],
                                  size: p.kind.size, kind: p.kind.sprite, glow: glow, phase: p.phase * (p.state == .busy ? 1.8 : 1),
                                  color: SIMD4(c, a), extra: [mirrored ? p.dir : 1, value, variant(p), 0]))
            }
        }
        if front {
            let kind = Float(FishKinds.index(of: Themes.current.schools?.first?.kind ?? "slender"))
            for s in school {
                let d: Float = s.vel.x >= 0 ? 1 : -1
                out.append(Sprite(pos: s.pos, dir: [d, 0], size: s.size, kind: 0, glow: 0, phase: s.phase,
                                  color: SIMD4(s.color * lit, 0.9), extra: [d, 1, kind, 0]))
            }
        }
        return out
    }
}

/// A value inside a range, by a fraction (0…1).
func mixf(_ r: ClosedRange<Float>, _ t: Float) -> Float { r.lowerBound + (r.upperBound - r.lowerBound) * t }
