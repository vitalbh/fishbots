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
    /// Comes by now, if it's one that passes now and then (`{"summon": …}`); false: it's always around, or never comes.
    func summon(_ t: Tank) -> Bool
}
extension Creature { func summon(_ t: Tank) -> Bool { false } }

/// The tank's creatures: crabs in the sand, a turtle that swims across now and then, a snail on the glass,
/// starfish, lanternfish at night and, rarely, a whale passing in the distance. The theme can pick which ones live here.
final class Fauna {
    /// Factories of every known creature, by id.
    private(set) static var kinds: [(id: String, make: () -> Creature)] = [
        ("crab", { Crabs() }), ("starfish", { Starfish() }), ("turtle", { TurtleSwimmer() }),
        ("snail", { Snail() }), ("lanternfish", { Lanterns() }), ("whale", { WhaleSwimmer() }), ("grouper", { Grouper() }),
        ("anglerfish", { Anglerfish() }), ("sunfish", { Sunfish() }), ("manatee", { Manatee() }), ("seahorses", { Seahorses() }),
    ]

    static func register(_ id: String, _ make: @escaping () -> Creature) {
        kinds.removeAll { $0.id == id }
        kinds.append((id, make))
    }
    static func unregister(_ id: String) { kinds.removeAll { $0.id == id } }

    /// The built-in creatures (what a theme without a list gets; a pack's creatures only live where a theme lists them).
    private static let builtIn: Set<String> = ["crab", "starfish", "turtle", "snail", "lanternfish", "whale", "grouper"]

    private(set) var creatures: [Creature] = Fauna.kinds.filter { Fauna.builtIn.contains($0.id) }.map { $0.make() }
    /// The whale showed up: the app plays its song.
    var onWhale: (() -> Void)? { didSet { whale?.onWhale = onWhale } }
    private var whale: WhaleSwimmer? { creatures.first { $0 is WhaleSwimmer } as? WhaleSwimmer }
    /// Where the whale is passing (nil: it isn't).
    var whalePosition: SIMD2<Float>? { whale?.position }

    /// Only these creatures (a theme's list; nil: all of them).
    func select(_ ids: [String]?) {
        let wanted = ids ?? Fauna.kinds.map(\.id).filter { Fauna.builtIn.contains($0) }
        creatures.removeAll { !wanted.contains($0.id) }
        for k in Fauna.kinds where wanted.contains(k.id) && !creatures.contains(where: { $0.id == k.id }) {
            creatures.append(k.make())
        }
        whale?.onWhale = onWhale
    }

    /// Lots of tasks today already? Then the whale shows up (once a day).
    func maybeWhale(_ t: Tank, tasksToday: Int) { whale?.maybe(t, tasksToday: tasksToday) }

    func callWhale(_ t: Tank) { whale?.call(t) }
    /// Those that pass now and then come by now (nil: all of them); the ids of those that will.
    func summon(_ t: Tank, _ id: String?) -> [String] { creatures.filter { (id == nil || $0.id == id) && $0.summon(t) }.map(\.id) }

    func update(_ t: Tank, dt: Float) { for c in creatures { c.update(t, dt: dt) } }

    func background(_ t: Tank) -> [Sprite] { creatures.flatMap { $0.sprites(t, layer: .background) } }
    func middle(_ t: Tank) -> [Sprite] { creatures.flatMap { $0.sprites(t, layer: .middle) } }
    func front(_ t: Tank) -> [Sprite] { creatures.flatMap { $0.sprites(t, layer: .front) } }
}

// MARK: - built-in creatures

/// Crabs: walk sideways in the sand, stop, sometimes bury themselves.
final class Crabs: Creature {
    let id = "crab"
    private struct Crab {
        var x: Float; var dir: Float; var walking = true; var until: Double = 0; var buried: Float = 0; var phase: Float = 0; var color: SIMD3<Float>
        /// An errand: 1 going to the pearls, 2 carrying something shiny to the chest, 3 coming back home.
        var errand = 0
        var goal: Float = 0
        var home: Float = 0
        var errandAt: Double = 0
    }
    private var crabs: [Crab] = []

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x
        if crabs.isEmpty {
            crabs = [Crab(x: w * 0.3, dir: 1, color: [0.85, 0.35, 0.22]),
                     Crab(x: w * 0.66, dir: -1, until: t.time + 20, color: [0.9, 0.5, 0.25])]
        }
        // one that ended up on the scenery (a theme change, a resize) walks off it
        for i in crabs.indices where t.scenery.blocks(t, crabs[i].x) && crabs[i].buried < 0.5 { crabs[i].x += crabs[i].dir * 40 * dt }
        for i in crabs.indices {
            var c = crabs[i]
            c.phase += dt
            if c.errandAt == 0 { c.errandAt = t.time + Double.random(in: 40...120) * Tank.scale }
            // now and then, an errand: something shiny from the pearls' row to the treasure chest, then back home
            if c.errand == 0, c.buried < 0.5, t.time > c.errandAt, let p = t.pearls.all.randomElement(),
               let chest = t.scenery.chest {
                _ = chest
                c.errand = 1; c.home = c.x; c.goal = t.pearls.pos(p).x
            }
            if c.errand > 0 {
                c.walking = true
                c.dir = c.goal >= c.x ? 1 : -1
                c.x += c.dir * 30 * dt
                if abs(c.goal - c.x) < 4 {
                    let y = t.size.y * t.sand(c.x / max(1, t.size.x)) + 12
                    switch c.errand {
                    case 1:
                        t.sparkle(at: [c.x, y], color: [1, 0.97, 0.85])
                        if let s = t.scenery.chest {
                            let (center, sz) = t.scenery.place(t, s)
                            c.goal = center.x + (c.x < center.x ? -1 : 1) * sz * 1.05
                            c.errand = 2
                        } else { c.errand = 3; c.goal = c.home }
                    case 2:
                        // drops it into the chest: a golden glint and a bubble
                        if let s = t.scenery.chest {
                            let (center, sz) = t.scenery.place(t, s)
                            t.sparkle(at: center + [0, sz * 0.5], color: [1, 0.82, 0.4])
                            t.bubble(at: center + [0, sz * 0.3], size: 2)
                        }
                        c.errand = 3; c.goal = c.home
                    default:
                        c.errand = 0
                        c.errandAt = t.time + Double.random(in: 90...220) * Tank.scale
                        c.until = t.time + Double.random(in: 2...5)
                        c.walking = false
                    }
                }
                crabs[i] = c
                continue
            }
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
                if next < w * 0.14 || next > w * 0.86 || (t.scenery.blocks(t, next) && !t.scenery.blocks(t, c.x)) { c.dir = -c.dir }
                else { c.x = next }
            }
            crabs[i] = c
        }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .middle else { return [] }
        return crabs.flatMap { c -> [Sprite] in
            let u = c.x / max(1, t.size.x)
            let y = t.size.y * t.sand(u) + 7 - c.buried * 7
            var out = [Sprite(pos: [c.x, y], dir: [1, 0], size: 20, kind: 14,
                              glow: c.walking ? 1 : 0, phase: c.phase, color: SIMD4(c.color * (0.55 + 0.45 * t.light), 1 - c.buried * 0.75),
                              extra: [1, 0, 0, 0])]
            // carrying: a little shiny pearl held up over its shell
            if c.errand == 2 {
                out.append(Sprite(pos: [c.x, y + 11 + sinf(c.phase * 8) * 0.8], dir: [1, 0], size: 4.5, kind: 12, glow: 0.6, phase: 0,
                                  color: [0.97, 0.93, 0.88, 1], extra: [1, 0, 0, 0]))
            }
            return out
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
    func summon(_ t: Tank) -> Bool { next = t.time; return true }

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
    func summon(_ t: Tank) -> Bool { call(t); return true }
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

/// A big, slow grouper that wanders through now and then while the tank is quiet (few sessions), so it never feels empty.
final class Grouper: Creature {
    let id = "grouper"
    private var pos: SIMD2<Float> = .zero
    private var dir: Float = 1
    private var y0: Float = 0
    private var phase: Float = 0
    private var active = false
    private var next: Double?

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x, h = t.size.y
        if next == nil { next = t.time + Double.random(in: 30...80) * Tank.scale }
        if !active, let n = next, t.time > n {
            next = t.time + Double.random(in: 150...320) * Tank.scale
            let agents = t.fish.filter { $0.isAgent && !$0.decor && !$0.leaving }.count
            guard agents <= 3 else { return }
            active = true
            dir = Bool.random() ? 1 : -1
            y0 = h * Float.random(in: 0.28...0.55)
            pos = [dir > 0 ? -90 : w + 90, y0]
        }
        guard active else { return }
        phase += dt
        pos.x += dir * 17 * dt
        pos.y = y0 + sinf(phase * 0.3) * 14
        if pos.x < -110 || pos.x > w + 110 { active = false }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .middle, active else { return [] }
        let water: SIMD3<Float> = SIMD3<Float>(0.12, 0.3, 0.4) * (0.5 + 0.5 * t.light)
        let c = mix(SIMD3<Float>(0.55, 0.47, 0.36) * (0.55 + 0.45 * t.light), water, t: 0.3)
        return [Sprite(pos: pos, dir: [dir, 0], size: 46, kind: 0, glow: 0, phase: phase * 3.2, color: SIMD4(c, 0.95),
                       extra: [dir, 2, Float(FishKinds.index(of: "oval")), 0.55], aux: [0, 0, 0.3, 0])]
    }
}

/// The deep sea's anglerfish: it lives near the bottom, drifting slowly from spot to spot with its lure glowing in
/// front of it, and snaps its mouth open when a fish comes close to the light (it never catches one).
final class Anglerfish: Creature {
    let id = "anglerfish"
    private var pos: SIMD2<Float>?
    private var goal: SIMD2<Float> = .zero
    private var vel: SIMD2<Float> = .zero
    private var dir: Float = 1
    private var phase: Float = 0
    private var open: Float = 0
    private var snapUntil: Double = 0
    private var calmUntil: Double = 0
    private var restUntil: Double = 0
    private let size: Float = 40

    private func spot(_ t: Tank) -> SIMD2<Float> {
        let w = t.size.x, h = t.size.y
        let x = w * Float.random(in: 0.08...0.92)
        return [x, h * t.sand(x / max(1, w)) + size * Float.random(in: 0.9...2.6)]
    }

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x
        guard w > 10 else { return }
        if pos == nil {
            let from: Float = Bool.random() ? -60 : w + 60
            pos = [from, t.size.y * t.sand(0.5) + size * 1.6]
            goal = spot(t)
        }
        guard var p = pos else { return }
        phase += dt
        // drift to a spot, linger there a while, pick another
        let d = goal - p
        if simd_length(d) < 12 {
            if restUntil < t.time { restUntil = t.time + Double.random(in: 8...25); goal = spot(t) }
        }
        let resting = restUntil > t.time
        let want: SIMD2<Float> = resting || simd_length(d) < 1 ? .zero : simd_normalize(d) * 9
        vel += (want - vel) * min(1, dt * 0.6)
        p += vel * dt
        p.y += sinf(phase * 0.8) * 0.06
        if abs(vel.x) > 1.5 { dir = vel.x > 0 ? 1 : -1 }
        pos = p
        // a fish near the lure: the mouth snaps open, then closes slowly
        let lure = p + SIMD2<Float>(dir * size * 0.9, size * 0.6)
        if t.time > calmUntil, t.fish.contains(where: { simd_distance($0.pos, lure) < size * 1.8 }) {
            snapUntil = t.time + 0.35; calmUntil = t.time + 6
        } else if t.time > calmUntil, Float.random(in: 0...1) < dt * 0.01 {
            snapUntil = t.time + 1.2; calmUntil = t.time + 10          // now and then a slow yawn
        }
        let target: Float = t.time < snapUntil ? 1 : 0
        open += (target - open) * min(1, dt * (target > open ? 14 : 1.5))
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .middle, let p = pos else { return [] }
        let c = SIMD3<Float>(0.2, 0.15, 0.14) * (0.6 + 0.4 * t.light)
        return [Sprite(pos: p, dir: [dir, 0], size: size, kind: 39, glow: 1, phase: phase, color: SIMD4(c, 1),
                       extra: [dir, open, 0, 0], aux: [1.3, 1.0, 0, 0])]
    }
}

/// The ocean sunfish: rare, huge and slow, it crosses the deep water now and then, a little in the distance.
final class Sunfish: Creature {
    let id = "sunfish"
    private var pos: SIMD2<Float>?
    private var dir: Float = 1
    private var y0: Float = 0
    private var phase: Float = 0
    private var next: Double?
    func summon(_ t: Tank) -> Bool { next = t.time; return true }

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x, h = t.size.y
        if next == nil { next = t.time + Double.random(in: 40...150) * Tank.scale }
        if pos == nil, let n = next, t.time > n {
            next = t.time + Double.random(in: 600...1500) * Tank.scale
            dir = Bool.random() ? 1 : -1
            y0 = h * Float.random(in: 0.42...0.68)
            pos = [dir > 0 ? -h * 0.2 : w + h * 0.2, y0]
        }
        guard var p = pos else { return }
        phase += dt
        p.x += dir * max(14, w / 75) * dt
        p.y = y0 + sinf(phase * 0.25) * h * 0.02
        pos = p
        if p.x < -h * 0.3 || p.x > w + h * 0.3 { pos = nil }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .background, let p = pos else { return [] }
        let c = SIMD3<Float>(0.5, 0.56, 0.62) * (0.45 + 0.55 * t.light)
        // a gentle tilt now and then, as sunfish do
        let tilt = sinf(phase * 0.15) * 0.12
        let th = dir > 0 ? tilt : .pi - tilt                 // facing left: turned around and mirrored, like the fish
        return [Sprite(pos: p, dir: [cosf(th), sinf(th)], size: t.size.y * 0.11, kind: 40, glow: 0, phase: phase,
                       color: SIMD4(c, 1), extra: [dir, 0, 0, 0], aux: [1.0, 1.25, 0, 0])]
    }
}

/// The lagoon's manatee: now and then it drifts slowly across, and halfway it may rise to the surface to breathe
/// (a ring spreads where its snout touches it) and sink back.
final class Manatee: Creature {
    let id = "manatee"
    private var pos: SIMD2<Float>?
    private var dir: Float = 1
    private var y0: Float = 0
    private var phase: Float = 0
    private var next: Double?
    func summon(_ t: Tank) -> Bool { next = t.time; return true }
    private var breath: Float = 0          // 0 cruising … 1 at the surface
    private var breathes = false
    private var breathed = false
    private var tilt: Float = 0
    private var lastY: Float?

    func update(_ t: Tank, dt: Float) {
        let w = t.size.x, h = t.size.y
        if next == nil { next = t.time + Double.random(in: 40...150) * Tank.scale }
        if pos == nil, let n = next, t.time > n {
            next = t.time + Double.random(in: 480...1200) * Tank.scale
            dir = Bool.random() ? 1 : -1
            y0 = h * Float.random(in: 0.3...0.55)
            breathes = Float.random(in: 0...1) < 0.7
            breathed = false
            pos = [dir > 0 ? -h * 0.2 : w + h * 0.2, y0]
        }
        guard var p = pos else { return }
        phase += dt
        p.x += dir * max(10, w / 110) * dt
        // halfway across, up to breathe
        let u = dir > 0 ? p.x / w : 1 - p.x / w
        let wantUp: Float = breathes && u > 0.35 && u < 0.6 ? 1 : 0
        breath += (wantUp - breath) * min(1, dt * 0.35)
        let top = h * 0.93 - h * 0.035
        p.y = mix(y0 + sinf(phase * 0.3) * h * 0.015, top, t: breath)
        if breath > 0.95 && !breathed {
            breathed = true
            t.ring(at: [p.x + dir * h * 0.11, h * 0.965], color: [0.9, 1, 0.95], size: 10, grow: 60, life: 1.6)
        }
        // the nose follows where it's heading, easing in and out (up as it rises, down as it sinks)
        if let ly = lastY, dt > 0 {
            let vy = (p.y - ly) / dt, vx = max(10, w / 110)
            let want = max(-0.3, min(0.35, atan2f(vy, vx)))
            tilt += (want - tilt) * min(1, dt * 0.6)
        }
        lastY = p.y
        pos = p
        if p.x < -h * 0.3 || p.x > w + h * 0.3 { pos = nil; lastY = nil; tilt = 0 }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .background, let p = pos else { return [] }
        let c = SIMD3<Float>(0.5, 0.48, 0.44) * (0.5 + 0.5 * t.light)
        let th = dir > 0 ? tilt : .pi - tilt
        return [Sprite(pos: p, dir: [cosf(th), sinf(th)], size: t.size.y * 0.075, kind: 44, glow: 0, phase: phase,
                       color: SIMD4(c, 1), extra: [dir, 0, 0, 0], aux: [1.7, 0.8, 0, 0])]
    }
}

private func mix(_ a: Float, _ b: Float, t: Float) -> Float { a + (b - a) * t }

/// The lagoon's seahorses: a few hold on to the seaweed with their tails, bobbing upright, and now and then let go
/// and drift slowly to another blade.
final class Seahorses: Creature {
    let id = "seahorses"
    private struct Horse { var pos: SIMD2<Float>; var goal: SIMD2<Float>; var dir: Float; var phase: Float; var until: Double; var color: SIMD3<Float> }
    private var horses: [Horse] = []

    private func perch(_ t: Tank) -> SIMD2<Float> {
        let spots = t.weeds.spots
        guard let s = spots.randomElement() else { return [t.size.x * 0.5, t.size.y * 0.3] }
        let y = t.size.y * (0.055 + s.h * Float.random(in: 0.35...0.75))
        return [s.x * t.size.x + Float.random(in: -6...6), y]
    }

    func update(_ t: Tank, dt: Float) {
        guard t.size.x > 10 else { return }
        if horses.isEmpty {
            let colors: [SIMD3<Float>] = [[1.0, 0.68, 0.35], [0.95, 0.85, 0.45], [0.85, 0.45, 0.4]]
            horses = (0..<3).map { i in
                let p = perch(t)
                return Horse(pos: p, goal: p, dir: Bool.random() ? 1 : -1, phase: Float.random(in: 0...6),
                             until: t.time + Double.random(in: 20...60), color: colors[i])
            }
        }
        for i in horses.indices {
            var hz = horses[i]
            hz.phase += dt
            if t.time > hz.until { hz.goal = perch(t); hz.until = t.time + Double.random(in: 30...90) }
            let d = hz.goal - hz.pos, l = simd_length(d)
            if l > 2 {
                hz.pos += d / l * min(l, 9 * dt)               // slow, upright, fins fluttering
                if abs(d.x) > 3 { hz.dir = d.x > 0 ? 1 : -1 }
            }
            horses[i] = hz
        }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard layer == .middle else { return [] }
        return horses.map { hz in
            let bob = sinf(hz.phase * 1.2) * 2
            return Sprite(pos: hz.pos + [0, bob], dir: [hz.dir, 0], size: 15, kind: 13, glow: 0.1, phase: hz.phase,
                          color: SIMD4(hz.color * (0.6 + 0.4 * t.light), 1), extra: [hz.dir, 0, 0, 0])
        }
    }
}
