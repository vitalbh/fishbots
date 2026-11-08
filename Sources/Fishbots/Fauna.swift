import Foundation
import simd

/// Where a creature is drawn, relative to the monitored fish.
enum FaunaLayer { case background, middle, front }

/// An ambient creature: it means nothing, it just brings the aquarium to life. Each one decides when it shows up.
/// See docs/extensions.md.
protocol Creature: AnyObject {
    var id: String { get }
    func update(_ t: Tank, dt: Float)
    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite]
}

/// The tank's creatures: crabs in the sand, a turtle that swims across now and then, a snail on the glass,
/// starfish, lanternfish at night and, rarely, a whale passing in the distance. The theme can pick which ones live here.
final class Fauna {
    /// Factories of every known creature, by id.
    private(set) static var kinds: [(id: String, make: () -> Creature)] = [
        ("crab", { Crabs() }), ("starfish", { Starfish() }), ("turtle", { TurtleSwimmer() }),
        ("snail", { Snail() }), ("lanternfish", { Lanterns() }), ("whale", { WhaleSwimmer() }),
    ]

    static func register(_ id: String, _ make: @escaping () -> Creature) {
        kinds.removeAll { $0.id == id }
        kinds.append((id, make))
    }

    private(set) var creatures: [Creature] = Fauna.kinds.map { $0.make() }
    /// The whale showed up: the app plays its song.
    var onWhale: (() -> Void)? { didSet { whale?.onWhale = onWhale } }
    private var whale: WhaleSwimmer? { creatures.first { $0 is WhaleSwimmer } as? WhaleSwimmer }
    /// Where the whale is passing (nil: it isn't).
    var whalePosition: SIMD2<Float>? { whale?.position }

    /// Only these creatures (a theme's list; nil: all of them).
    func select(_ ids: [String]?) {
        let wanted = ids ?? Fauna.kinds.map(\.id)
        creatures.removeAll { !wanted.contains($0.id) }
        for k in Fauna.kinds where wanted.contains(k.id) && !creatures.contains(where: { $0.id == k.id }) {
            creatures.append(k.make())
        }
        whale?.onWhale = onWhale
    }

    /// Lots of tasks today already? Then the whale shows up (once a day).
    func maybeWhale(_ t: Tank, tasksToday: Int) { whale?.maybe(t, tasksToday: tasksToday) }

    func callWhale(_ t: Tank) { whale?.call(t) }

    func update(_ t: Tank, dt: Float) { for c in creatures { c.update(t, dt: dt) } }

    func background(_ t: Tank) -> [Sprite] { creatures.flatMap { $0.sprites(t, layer: .background) } }
    func middle(_ t: Tank) -> [Sprite] { creatures.flatMap { $0.sprites(t, layer: .middle) } }
    func front(_ t: Tank) -> [Sprite] { creatures.flatMap { $0.sprites(t, layer: .front) } }
}

// MARK: - built-in creatures

/// Crabs: walk sideways in the sand, stop, sometimes bury themselves.
final class Crabs: Creature {
    let id = "crab"
    private struct Crab { var x: Float; var dir: Float; var walking = true; var until: Double = 0; var buried: Float = 0; var phase: Float = 0; var color: SIMD3<Float> }
    private var crabs: [Crab] = []

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x
        if crabs.isEmpty {
            crabs = [Crab(x: w * 0.3, dir: 1, color: [0.85, 0.35, 0.22]),
                     Crab(x: w * 0.66, dir: -1, until: t.time + 20, color: [0.9, 0.5, 0.25])]
        }
        // one that ended up on the scenery (a theme change, a resize) walks off it
        for i in crabs.indices where t.sceneryBlocks(crabs[i].x) && crabs[i].buried < 0.5 { crabs[i].x += crabs[i].dir * 40 * dt }
        for i in crabs.indices {
            var c = crabs[i]
            c.phase += dt
            if t.time > c.until {
                let r = Float.random(in: 0...1)
                if c.buried > 0.5 { c.buried = 0; c.walking = true; c.until = t.time + Double.random(in: 4...9) }
                else if r < 0.15 {
                    c.buried = 1; c.walking = false; c.until = t.time + Double.random(in: 20...45)
                    // digs in: a little cloud of sand
                    let y = t.size.y * t.sand(c.x / max(1, t.size.x)) + 4
                    for _ in 0..<4 {
                        t.addParticle(Particle(pos: [c.x + Float.random(in: -8...8), y], vel: [Float.random(in: -14...14), Float.random(in: 4...14)],
                                               life: 0, maxLife: 1.8, size: 9, grow: 8, kind: 10, color: [0.75, 0.65, 0.48, 1]))
                    }
                }
                else if r < 0.45 { c.walking = false; c.until = t.time + Double.random(in: 2...6) }
                else { c.walking = true; if Bool.random() { c.dir = -c.dir }; c.until = t.time + Double.random(in: 3...8) }
            }
            if c.walking && c.buried < 0.5 {
                let next = c.x + c.dir * 22 * dt
                // the edges and the scenery: turn around instead of walking over a rock or the chest
                if next < w * 0.14 || next > w * 0.86 || (t.sceneryBlocks(next) && !t.sceneryBlocks(c.x)) { c.dir = -c.dir }
                else { c.x = next }
            }
            crabs[i] = c
        }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .middle else { return [] }
        return crabs.map { c in
            let u = c.x / max(1, t.size.x)
            return Sprite(pos: [c.x, t.size.y * t.sand(u) + 7 - c.buried * 7], dir: [1, 0], size: 20, kind: 14,
                          glow: c.walking ? 1 : 0, phase: c.phase, color: SIMD4(c.color * (0.55 + 0.45 * t.light), 1 - c.buried * 0.75),
                          extra: [1, 0, 0, 0])
        }
    }
}

/// Starfish in the sand: they just move an arm now and then.
final class Starfish: Creature {
    let id = "starfish"
    private var stars: [(u: Float, phase: Float, color: SIMD3<Float>)] = [(0.42, 0, [0.95, 0.5, 0.35]), (0.57, 2, [0.85, 0.4, 0.6])]

    func update(_ t: Tank, dt: Float) { for i in stars.indices { stars[i].phase += dt } }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .middle else { return [] }
        return stars.map { (u, phase, color) in
            Sprite(pos: [t.size.x * u, t.size.y * t.sand(u) + 3], dir: [1, 0], size: 16, kind: 17, glow: 0, phase: phase,
                   color: SIMD4(color * (0.55 + 0.45 * t.light), 1), extra: [1, 0, 0, 0])
        }
    }
}

/// A turtle that swims across now and then.
final class TurtleSwimmer: Creature {
    let id = "turtle"
    private struct Turtle { var pos: SIMD2<Float>; var dir: Float; var phase: Float = 0; var y0: Float; var breathes = false; var breathed = false }
    private var turtle: Turtle?
    private var next: Double?

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x, h = t.size.y
        if next == nil { next = t.time + Double.random(in: 60...150) * Tank.scale }
        if turtle == nil, let n = next, t.time > n {
            let dir: Float = Bool.random() ? 1 : -1
            let y0 = h * Float.random(in: 0.35...0.7)
            turtle = Turtle(pos: [dir > 0 ? -60 : w + 60, y0], dir: dir, y0: y0, breathes: Float.random(in: 0...1) < 0.5)
        }
        if var tt = turtle {
            tt.phase += dt
            tt.pos.x += tt.dir * 26 * dt
            // halfway across, now and then it goes up for a breath, then back down
            let k = tt.dir > 0 ? tt.pos.x / max(1, w) : 1 - tt.pos.x / max(1, w)
            let up = tt.breathes ? smoothstep(0.3, 0.5, k) * (1 - smoothstep(0.55, 0.75, k)) : 0
            tt.pos.y = (tt.y0 + sinf(tt.phase * 0.5) * 18) * (1 - up) + (h * 0.94) * up
            if up > 0.97 && !tt.breathed { tt.breathed = true; t.splash(at: [tt.pos.x + tt.dir * 20, h * 0.965]) }
            turtle = tt
            if tt.pos.x < -90 || tt.pos.x > w + 90 { turtle = nil; next = t.time + Double.random(in: 240...480) }
        }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .middle, let tt = turtle else { return [] }
        return [Sprite(pos: tt.pos, dir: [tt.dir, 0], size: 30, kind: 15, glow: 0, phase: tt.phase,
                       color: SIMD4(SIMD3<Float>(0.45, 0.55, 0.32) * (0.6 + 0.4 * t.light), 1), extra: [tt.dir, 0, 0, 0])]
    }
}

/// A snail that climbs the right glass very slowly, leaving a trail; at the top, it lets go and falls.
final class Snail: Creature {
    let id = "snail"
    private var y: Float?
    private var falling = false
    private var trail: [(SIMD2<Float>, Double)] = []

    func update(_ t: Tank, dt: Float) {
        let h = t.size.y, cx = t.size.x - 9
        var y = self.y ?? h * 0.2
        if falling {
            y -= 140 * dt
            if y < h * 0.12 { falling = false; t.burst(at: [cx, y], n: 3) }
        } else {
            y += 2.6 * dt
            if Int(t.time * 2) % 3 == 0, trail.last.map({ simd_distance($0.0, [cx, y]) > 4 }) ?? true { trail.append(([cx, y - 6], t.time)) }
            if y > h * 0.88 { falling = true }
        }
        self.y = y
        trail.removeAll { t.time - $0.1 > 40 }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .front, let y else { return [] }
        var out: [Sprite] = []
        for (p, q) in zip(trail, trail.dropFirst()) {
            let d = q.0 - p.0, l = simd_length(d)
            guard l > 0.5, l < 30 else { continue }
            let life = Float(1 - (t.time - p.1) / 40)
            out.append(Sprite(pos: (p.0 + q.0) / 2, dir: d / l, size: l / 2, kind: 7, glow: life * 0.35, phase: 0,
                              color: [0.75, 0.85, 0.9, 1], extra: [1, 0, 0, 1.2]))
        }
        out.append(Sprite(pos: [t.size.x - 9, y], dir: [0, falling ? -1 : 1], size: 13, kind: 16, glow: 0, phase: Float(t.time),
                          color: [0.75, 0.55, 0.3, 1], extra: [1, 0, 0, 0]))
        return out
    }
}

/// Lanternfish: show up at night, swimming slowly down low.
final class Lanterns: Creature {
    let id = "lanternfish"
    private struct Lanternfish { var pos: SIMD2<Float>; var vel: SIMD2<Float> = .zero; var goal: SIMD2<Float>; var phase: Float }
    private var lanterns: [Lanternfish] = []
    private var night: Float = 0

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x, h = t.size.y
        night += ((t.light < 0.75 ? 1 : 0) - night) * min(1, dt * 0.3)
        if night > 0.5 && lanterns.count < 3 && Float.random(in: 0...1) < dt * 0.2 {
            let side: Float = Bool.random() ? -30 : w + 30
            lanterns.append(Lanternfish(pos: [side, h * Float.random(in: 0.18...0.45)], goal: [w * Float.random(in: 0.2...0.8), h * Float.random(in: 0.15...0.5)],
                                        phase: Float.random(in: 0...6)))
        }
        for i in lanterns.indices {
            var l = lanterns[i]
            l.phase += dt
            if simd_distance(l.pos, l.goal) < 20 || Float.random(in: 0...1) < dt * 0.05 {
                l.goal = night < 0.3 ? [l.pos.x < w / 2 ? -80 : w + 80, l.pos.y] : [w * Float.random(in: 0.1...0.9), h * Float.random(in: 0.15...0.5)]
            }
            let d = l.goal - l.pos
            l.vel += ((simd_length(d) > 1 ? simd_normalize(d) * 22 : .zero) - l.vel) * min(1, dt)
            l.pos += l.vel * dt
            lanterns[i] = l
        }
        lanterns.removeAll { $0.pos.x < -60 || $0.pos.x > w + 60 }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .middle else { return [] }
        let kind = Float(FishKinds.index(of: "lanternfish"))
        return lanterns.map { l in
            let dir: Float = l.vel.x >= 0 ? 1 : -1
            return Sprite(pos: l.pos, dir: [dir, 0], size: 13, kind: 0, glow: 0, phase: l.phase * 5,
                          color: [0.12, 0.14, 0.2, night], extra: [dir, 0, kind, 0])
        }
    }
}

/// The whale: rare, in the distance (or a gift when the day was productive).
final class WhaleSwimmer: Creature {
    let id = "whale"
    private struct Whale { var x: Float; var dir: Float; var y: Float }
    private var whale: Whale?
    private var next: Double?
    private var today = ""
    var onWhale: (() -> Void)?
    /// Where the whale is now (x, y), for the seaweed to feel it pass.
    var position: SIMD2<Float>? { whale.map { [$0.x, $0.y] } }

    func maybe(_ t: Tank, tasksToday: Int) {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: Date())
        guard tasksToday >= 10, today != day, whale == nil else { return }
        today = day
        call(t)
    }

    func call(_ t: Tank) {
        let dir: Float = Bool.random() ? 1 : -1
        whale = Whale(x: dir > 0 ? -t.size.x * 0.4 : t.size.x * 1.4, dir: dir, y: t.size.y * Float.random(in: 0.5...0.7))
        onWhale?()
    }

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x
        if next == nil { next = t.time + Double.random(in: 1800...5400) }
        if whale == nil, let n = next, t.time > n {
            next = t.time + Double.random(in: 3600...9000)
            call(t)
        }
        if var b = whale {
            b.x += b.dir * w / 42 * dt
            whale = b
            if b.x < -w * 0.5 || b.x > w * 1.5 { whale = nil }
        }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .background, let b = whale else { return [] }
        return [Sprite(pos: [b.x, b.y], dir: [b.dir, 0], size: t.size.y * 0.16, kind: 19, glow: 0, phase: Float(t.time),
                       color: [0.05, 0.12, 0.2, 1], extra: [b.dir, 0, 0, 0])]
    }
}
