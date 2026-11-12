import Foundation
import simd

/// What stands in the tank: rocks, a big shell, a treasure chest, corals and the packs' pieces (the theme picks
/// which). The fish swim around them, crabs turn back at them, pearls and pebbles keep clear of them.
final class Scenery {
    /// Scenery on the sand that the fish swim around: rocks, a big shell, a chest, corals (the theme picks which).
    struct Item {
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
        var bury: Float = 0.05
        /// How far up front it stands on the floor: 0 at the back line, 1 in the middle, 2 near the glass (lower on the
        /// screen and a little bigger). The floor is seen at a slant, so a row of things all at the back line reads as a shelf.
        var row: Float = 0
    }
    static let all: [Item] = [
        Item(id: "rock", kind: 21, u: 0.17, scale: 0.075, color: [0.42, 0.4, 0.36], seed: 0.3),
        Item(id: "rock", kind: 21, u: 0.235, scale: 0.042, color: [0.36, 0.38, 0.41], seed: 1.7, row: 1.4),
        Item(id: "chest", kind: 23, u: 0.335, scale: 0.06, color: [0.5, 0.31, 0.16], seed: 0, row: 0.8),
        // the clutch: sessions started from the aquarium hatch here, and a click on it starts one
        Item(id: "eggs", kind: 46, u: 0.405, scale: 0.042, color: [1.0, 0.62, 0.3], seed: 0, extent: [1.25, 0.85], solid: false, row: 1.6),
        // only where a theme lists it (the deep sea)
        Item(id: "helmet", kind: 41, u: 0.6, scale: 0.068, color: [0.75, 0.75, 0.75], seed: 0, row: 1),
        Item(id: "shell", kind: 22, u: 0.66, scale: 0.04, color: [0.66, 0.6, 0.56], seed: 0, row: 1.8),   // the oyster
        Item(id: "rock", kind: 21, u: 0.8, scale: 0.058, color: [0.4, 0.37, 0.35], seed: 2.9, row: 0.9),
        // corals (seed: 0 branching, 1 sea fan, 2 brain), muted by the water
        Item(id: "coral", kind: 34, u: 0.47, scale: 0.085, color: [0.95, 0.45, 0.55], seed: 0.2),
        Item(id: "coral", kind: 34, u: 0.565, scale: 0.05, color: [0.62, 0.5, 0.85], seed: 2.6, row: 1.5),
        Item(id: "coral", kind: 34, u: 0.735, scale: 0.06, color: [0.35, 0.78, 0.75], seed: 0.8, row: 0.5),
        Item(id: "coral", kind: 34, u: 0.905, scale: 0.1, color: [0.98, 0.58, 0.3], seed: 1.4),
    ]

    /// The theme's list (nil: all the built-in scenery; a pack's scenery only shows up where a theme lists it).
    var kinds: [String]? = nil { didSet { items = Self.items(for: kinds, looks: looks) } }
    /// Built-in pieces drawn by a pack's scenery instead (the theme's "looks": "chest": "shrine").
    var looks: [String: String] = [:] { didSet { items = Self.items(for: kinds, looks: looks) } }
    private(set) var items: [Item] = Scenery.items(for: nil, looks: [:])

    private static func items(for ids: [String]?, looks: [String: String]) -> [Item] {
        // the clutch is in every theme that doesn't have a pack's own piece called "eggs"
        var out = all.filter { ids?.contains($0.id) ?? ($0.id != "helmet") || ($0.id == "eggs" && SceneryKinds.index(of: "eggs") == nil) }.map { s -> Item in
            // another look for a built-in piece: the pack's drawing, extent and color, in the same place
            guard let look = looks[s.id], let i = SceneryKinds.index(of: look) else { return s }
            let k = SceneryKinds.all[i]
            return Item(id: s.id, kind: 35, u: s.u, scale: s.scale, color: k.color, seed: s.seed, pack: i,
                        anchor: .sand, extent: k.extent, glowAtNight: k.glowAtNight, bury: k.bury, row: s.row)
        }
        for (i, k) in SceneryKinds.all.enumerated() where ids?.contains(k.id) == true {
            for (j, u) in k.at.enumerated() {
                out.append(Item(id: k.id, kind: 35, u: u, scale: k.size, color: k.color,
                                seed: Float(j) * 0.618 - floor(Float(j) * 0.618) + 0.05, pack: i, anchor: k.anchor,
                                extent: k.extent, height: k.height, drift: k.drift, solid: k.solid, glowAtNight: k.glowAtNight,
                                bury: k.bury))
            }
        }
        return out
    }

    /// The ones on the sand (what crabs, pearls and pebbles keep clear of).
    private var onSand: [Item] { items.filter { $0.anchor == .sand } }

    /// Where an item sits and how much room the fish give it.
    func place(_ t: Tank, _ s: Item) -> (center: SIMD2<Float>, size: Float) {
        let size = t.size
        var sz = s.scale * size.y
        switch s.anchor {
        case .sand:
            // a pack's piece stands on the sand with the bottom of its drawing (c.y = -1) a little buried
            sz *= 1 + 0.07 * s.row                                       // nearer: a little bigger
            return ([s.u * size.x, floorY(t, s) + (s.pack != nil ? sz * s.extent.y * (1 - 2 * s.bury) : sz * 0.3)], sz)
        case .surface:
            // floating: drifting slowly back and forth, riding the waves
            let x = s.u * size.x + (s.drift ? sinf(Float(t.time) * 0.035 + s.seed * 6.3) * size.x * 0.03 : 0)
            return ([x, t.surfaceY(x) - sz * 0.12], sz)
        case .float:
            return ([s.u * size.x, size.y * s.height + sinf(Float(t.time) * 0.5 + s.seed * 6.3) * 3], sz)
        }
    }

    /// Where an item touches the floor: the back line of the sand, lower for the ones standing nearer the glass.
    func floorY(_ t: Tank, _ s: Item) -> Float { t.size.y * t.sand(s.u) * (1 - 0.2 * s.row) }

    /// The stretch of sand an item takes (for the crabs, who turn around instead of walking over it).
    func blocks(_ t: Tank, _ x: Float) -> Bool {
        onSand.contains { s in let (c, sz) = place(t, s); return abs(x - c.x) < sz * 1.25 }
    }

    /// A spot on the sand moved out of the scenery's way (pearls and pebbles would float in front of a rock or the chest).
    func clear(_ t: Tank, _ x: Float) -> Float {
        for s in onSand {
            let (c, sz) = place(t, s)
            let half = sz * 1.35 + 8
            if abs(x - c.x) < half { return c.x + (x < c.x ? -half : half) }
        }
        return x
    }

    /// The closest spot to `x` with nothing on the sand within `room` points of it (the old battery lies there).
    func free(_ t: Tank, near x: Float, room: Float) -> Float {
        let spans = onSand.map { s -> (Float, Float) in let (c, sz) = place(t, s); return (c.x, sz * s.extent.x * 1.1 + room) }
        func taken(_ x: Float) -> Bool { spans.contains { abs(x - $0.0) < $0.1 } }
        let w = t.size.x
        for i in 0..<200 {
            for x in [x - Float(i) * 4, x + Float(i) * 4] where x > w * 0.14 && x < w * 0.94 && !taken(x) { return x }
        }
        return x
    }

    // MARK: the clutch of eggs

    var eggs: Item? { items.first { $0.id == "eggs" } }

    /// The clutch under the point (clicking it starts a session).
    func eggsHit(_ t: Tank, at p: SIMD2<Float>) -> Bool {
        guard let s = eggs else { return false }
        let (c, sz) = place(t, s)
        return abs(p.x - c.x) < sz * 1.05 && p.y > c.y - sz * 0.35 && p.y < c.y + sz * 0.85
    }

    /// Sessions the aquarium itself started and that haven't shown up yet: by agent, and until when they're awaited.
    private var expected: [(source: String, until: Double)] = []
    /// How stirred the eggs are: one is on its way (0…1), plus the jolt of one that just hatched.
    private(set) var eggsStir: Float = 0
    private var eggsJolt: Float = 0
    var eggsGlow: Float { min(1.4, eggsStir * 0.7 + eggsJolt) }

    /// A session of this agent was started from the aquarium: its fish will hatch from the clutch.
    func expect(_ t: Tank, source: String, for seconds: Double) {
        expected.append((source, t.time + seconds))
    }

    /// A fish of this agent is being born: where it hatches from, if it's one the clutch was waiting for.
    func hatching(_ t: Tank, source: String) -> SIMD2<Float>? {
        expected.removeAll { $0.until < t.time }
        guard let i = expected.firstIndex(where: { $0.source == source }), let s = eggs else { return nil }
        expected.remove(at: i)
        let (c, sz) = place(t, s)
        let at = c + [0, sz * 0.45]
        eggsJolt = 1
        for _ in 0..<10 {
            t.addParticle(Particle(pos: at + [Float.random(in: -sz * 0.5...sz * 0.5), 0], vel: [Float.random(in: -26...26), Float.random(in: 20...60)],
                                   life: 0, maxLife: Float.random(in: 0.8...1.6), size: Float.random(in: 3...6), grow: 1, kind: 4,
                                   color: [1, 0.8, 0.5, 1]))
        }
        for i in 0..<6 { t.after(Double(i) * 0.08) { [weak t] in t?.bubble(at: at + [Float.random(in: -sz * 0.4...sz * 0.4), 0], size: Float.random(in: 1.5...3)) } }
        return at
    }

    // MARK: the treasure chest

    var chest: Item? { items.first { $0.id == "chest" } }

    /// The chest under the point (clicking it opens the summary of the last hours).
    func chestHit(_ t: Tank, at p: SIMD2<Float>) -> Bool {
        guard let s = chest else { return false }
        let (c, sz) = place(t, s)
        return abs(p.x - c.x) < sz * 0.95 && p.y > c.y - sz * 0.75 && p.y < c.y + sz * 0.55
    }

    /// It opens while the summary is open (the app sets it); the lid follows with a little spring.
    var chestOpen = false
    private(set) var chestLid: Float = 0
    private var chestLidVel: Float = 0
    private var chestSparkAt: Double = 0
    private var chestBubblesAt: Double = 0

    func update(_ t: Tank, dt: Float) {
        expected.removeAll { $0.until < t.time }
        eggsStir += ((expected.isEmpty ? 0 : 1) - eggsStir) * min(1, dt * 2)
        eggsJolt = max(0, eggsJolt - dt * 0.7)
        let goal: Float = chestOpen ? 1 : 0
        chestLidVel += ((goal - chestLid) * 40 - chestLidVel * 7) * dt
        chestLid = max(0, min(1.08, chestLid + chestLidVel * dt))
        guard let s = chest else { return }
        let (c, sz) = place(t, s)
        // it lets out a few bubbles now and then
        if t.time > chestBubblesAt {
            chestBubblesAt = t.time + Double.random(in: 7...16)
            for i in 0..<Int.random(in: 3...6) {
                t.after(Double(i) * 0.12) { [weak t] in
                    t?.bubble(at: c + [Float.random(in: -sz * 0.4...sz * 0.4), sz * 0.15], size: Float.random(in: 1.5...3))
                }
            }
        }
        // open: gold sparks rising out of it
        guard chestLid > 0.5, t.time > chestSparkAt else { return }
        chestSparkAt = t.time + Double.random(in: 0.12...0.3)
        let p = c + [Float.random(in: -sz * 0.5...sz * 0.5), sz * 0.25]
        t.addParticle(Particle(pos: p, vel: [Float.random(in: -8...8), Float.random(in: 18...34)], life: 0, maxLife: Float.random(in: 1...1.8),
                               size: Float.random(in: 4...7), grow: 1, kind: 4, color: [1, 0.82, 0.4, 1]))
        if Float.random(in: 0...1) < 0.3 { t.bubble(at: p, size: Float.random(in: 1.5...2.6)) }
    }
}
