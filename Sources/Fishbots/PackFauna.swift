import Foundation
import simd

/// A creature that comes from a pack: drawn by its own Metal function
/// `float4 draw_<id>(float2 c, float phase, float glow, float4 col, float4 extra)`, moved by one of the app's ready-made
/// behaviors (a pack can't bring code). In the function: c is -1…1 over the quad (y up, facing +x), phase runs while it
/// moves (for the legs, the fins, the wings), col its color lit by the hour, extra.y a seed (0…1, different for each one),
/// extra.w 1 while it moves and 0 while it rests. It returns premultiplied color and alpha. See docs/extensions.md.
struct FaunaKind {
    enum Behavior: String, CaseIterable {
        case cross      // swims across the tank now and then (the turtle)
        case pass       // rare, far away in the background (the whale)
        case crawl      // walks on the sand, stops, turns around (the crab)
        case rest       // stays on the sand, barely moving (the starfish)
        case glass      // climbs up and down the glass (the snail)
        case drift      // floats, rising and sinking slowly (a jellyfish)
        case school     // a little group wandering together
        case skim       // just under the surface, darting and stopping
        case perch      // sits on a piece of scenery (`on`), hopping between copies now and then
        case home       // lives around a piece of scenery (`on`): swims about it, never far, and back in (a clownfish and its anemone)
    }
    enum When: String { case any, day, night }
    let id: String
    let name: String
    let source: String
    let function: String
    let pack: String
    let behavior: Behavior
    /// Size in points (like the fish).
    let size: Float
    let count: ClosedRange<Int>
    /// Points per second.
    let speed: Float
    /// Where in the water (0…1 from the bottom), for the ones that swim.
    let height: ClosedRange<Float>
    let when: When
    let color: SIMD3<Float>
    /// The quad, relative to the size (width, height).
    let extent: SIMD2<Float>
    /// Seconds between visits, for `cross` and `pass`.
    let every: ClosedRange<Double>
    /// Swims away from the mouse.
    let shy: Bool
    /// The scenery it sits on, for `perch`.
    let on: String?
    /// Drawn in front of the fish (default: behind them, or far behind for `pass`).
    let front: Bool
}

/// The registry of pack creatures. A sprite of kind 36 carries its index in extra.z.
enum FaunaKinds {
    static var all: [FaunaKind] = []

    static func register(_ k: FaunaKind) {
        if let i = all.firstIndex(where: { $0.id == k.id }) { all[i] = k } else { all.append(k) }
        Fauna.register(k.id) { PackCreature(id: k.id) }
    }
    static func drop(_ id: String) { all.removeAll { $0.id == id }; Fauna.unregister(id) }
}

/// One pack creature (all the individuals of a kind), moved by its behavior.
final class PackCreature: Creature {
    let id: String
    private struct One {
        var pos: SIMD2<Float>
        var vel: SIMD2<Float> = .zero
        var goal: SIMD2<Float> = .zero
        var phase: Float = Float.random(in: 0...6)
        var seed: Float = Float.random(in: 0...1)
        var wait: Float = Float.random(in: 0...3)
        var dir: Float = Bool.random() ? 1 : -1
        var moving: Float = 0
        var y0: Float = 0
        var perch = 0
        var hop: Float = -1
        var from: SIMD2<Float> = .zero
    }
    private var ones: [One] = []
    private var nextVisit: Double?
    func summon(_ t: Tank) -> Bool {
        guard let k = kind, k.behavior == .cross || k.behavior == .pass else { return false }
        nextVisit = t.time; return true
    }
    private var shown: Float = 0
    private var center: SIMD2<Float> = .zero
    private var centerGoal: SIMD2<Float> = .zero

    init(id: String) { self.id = id }

    private var kind: FaunaKind? { FaunaKinds.all.first { $0.id == id } }
    private var index: Int { FaunaKinds.all.firstIndex { $0.id == id } ?? 0 }

    func update(_ t: Tank, dt: Float) {
        guard let k = kind, t.size.x > 10 else { return }
        let w = t.size.x, h = t.size.y
        let want: Float = k.when == .any ? 1 : (k.when == .night) == t.isNight ? 1 : 0
        shown += (want - shown) * min(1, dt * 0.3)
        let sandY = { (x: Float) -> Float in h * t.sand(max(0, min(1, x / w))) }
        let n = { Int.random(in: k.count) }
        func randomHeight() -> Float { h * Float.random(in: k.height) }

        switch k.behavior {
        case .cross, .pass:
            if ones.isEmpty {
                if nextVisit == nil { nextVisit = t.time + Double.random(in: k.every) * t.visitGap }
                if let at = nextVisit, t.time > at, shown > 0.5 {
                    nextVisit = nil
                    for i in 0..<(k.behavior == .pass ? 1 : n()) {
                        let dir: Float = Bool.random() ? 1 : -1
                        var o = One(pos: [dir > 0 ? -k.size * 2 - Float(i) * k.size * 1.5 : w + k.size * 2 + Float(i) * k.size * 1.5, randomHeight()])
                        o.dir = dir; o.y0 = o.pos.y; o.moving = 1
                        ones.append(o)
                    }
                }
            }
            for i in ones.indices {
                ones[i].phase += dt * max(1, k.speed / 8)
                ones[i].pos.x += ones[i].dir * k.speed * dt
                ones[i].pos.y = ones[i].y0 + sinf(ones[i].phase * 0.25 + ones[i].seed * 6) * h * 0.012
            }
            ones.removeAll { $0.pos.x < -k.size * 6 || $0.pos.x > w + k.size * 6 }

        case .crawl, .rest:
            if ones.isEmpty {
                for _ in 0..<n() {
                    var x = Float.random(in: w * 0.08...w * 0.92)
                    for _ in 0..<10 where t.scenery.blocks(t, x) { x = Float.random(in: w * 0.08...w * 0.92) }
                    ones.append(One(pos: [x, 0]))
                }
            }
            for i in ones.indices {
                var o = ones[i]
                if k.behavior == .crawl {
                    o.wait -= dt
                    if o.wait <= 0 {
                        o.moving = 1
                        let next = o.pos.x + o.dir * k.speed * dt
                        if next < w * 0.06 || next > w * 0.94 || (t.scenery.blocks(t, next) && !t.scenery.blocks(t, o.pos.x)) { o.dir = -o.dir }
                        else { o.pos.x = next }
                        o.phase += dt * max(1, k.speed / 4)
                        if Float.random(in: 0...1) < dt * 0.25 { o.wait = Float.random(in: 1.5...5); if Bool.random() { o.dir = -o.dir } }
                    } else { o.moving = 0; o.phase += dt * 0.3 }
                } else { o.phase += dt * 0.4 }
                o.pos.y = sandY(o.pos.x) + k.size * k.extent.y * 0.9          // its feet (c.y = -0.9) on the sand
                ones[i] = o
            }

        case .glass:
            if ones.isEmpty {
                for i in 0..<n() {
                    let side = i % 2 == 0 ? w - k.size * 0.45 : k.size * 0.45
                    var o = One(pos: [side, Float.random(in: h * 0.15...h * 0.85)])
                    o.goal = [side, Float.random(in: h * 0.15...h * 0.85)]
                    ones.append(o)
                }
            }
            for i in ones.indices {
                var o = ones[i]
                let dy = o.goal.y - o.pos.y
                if abs(dy) < 2 { o.wait -= dt; o.moving = 0; if o.wait <= 0 { o.goal.y = Float.random(in: h * 0.15...h * 0.85); o.wait = Float.random(in: 4...12) } }
                else { o.pos.y += (dy > 0 ? 1 : -1) * min(abs(dy), k.speed * dt); o.dir = dy > 0 ? 1 : -1; o.moving = 1; o.phase += dt * 2 }
                ones[i] = o
            }

        case .drift:
            if ones.isEmpty {
                for _ in 0..<n() {
                    var o = One(pos: [Float.random(in: w * 0.1...w * 0.9), randomHeight()])
                    o.y0 = o.pos.y
                    ones.append(o)
                }
            }
            for i in ones.indices {
                var o = ones[i]
                o.phase += dt * 1.2
                o.moving = 1
                o.pos.y = o.y0 + sinf(o.phase * 0.18 + o.seed * 6) * h * 0.06
                o.pos.x += (sinf(o.phase * 0.07 + o.seed * 3) * k.speed * 0.3) * dt
                o.pos.x = max(k.size, min(w - k.size, o.pos.x))
                o.dir = sinf(o.phase * 0.07 + o.seed * 3) >= 0 ? 1 : -1
                ones[i] = o
            }

        case .school:
            if ones.isEmpty {
                center = [w * Float.random(in: 0.2...0.8), randomHeight()]
                centerGoal = center
                for _ in 0..<n() { ones.append(One(pos: center + SIMD2(Float.random(in: -30...30), Float.random(in: -15...15)))) }
            }
            if simd_distance(center, centerGoal) < 20 || Float.random(in: 0...1) < dt * 0.05 {
                centerGoal = [w * Float.random(in: 0.1...0.9), randomHeight()]
            }
            let cd = centerGoal - center
            center += (simd_length(cd) > 1 ? simd_normalize(cd) : .zero) * k.speed * 0.6 * dt
            for i in ones.indices {
                var o = ones[i]
                let spot = center + SIMD2(sinf(o.seed * 40) * k.size * 2.5, cosf(o.seed * 23) * k.size * 1.2)
                o.vel += ((spot - o.pos) * 1.2 - o.vel) * min(1, dt * 2)
                o.pos += o.vel * dt
                o.phase += dt * (2 + simd_length(o.vel) * 0.1)
                if abs(o.vel.x) > 2 { o.dir = o.vel.x > 0 ? 1 : -1 }
                o.moving = 1
                ones[i] = o
            }

        case .skim:
            if ones.isEmpty { for _ in 0..<n() { ones.append(One(pos: [Float.random(in: w * 0.1...w * 0.9), 0])) } }
            for i in ones.indices {
                var o = ones[i]
                o.wait -= dt
                if o.wait <= 0 && abs(o.goal.x - o.pos.x) < 2 {
                    o.goal.x = max(w * 0.05, min(w * 0.95, o.pos.x + Float.random(in: -w * 0.3...w * 0.3)))
                    o.wait = Float.random(in: 1...4)
                }
                let dx = o.goal.x - o.pos.x
                if abs(dx) > 2 { o.pos.x += dx * min(1, dt * max(0.5, k.speed / 40)); o.dir = dx > 0 ? 1 : -1; o.moving = 1 } else { o.moving = 0 }
                o.phase += dt * (o.moving > 0.5 ? 6 : 2)
                o.pos.y = t.surfaceY(o.pos.x) - k.size * k.extent.y * 0.6
                ones[i] = o
            }

        case .home:
            // around a home: pick a spot near it, swim there (facing the way it goes), pause, pick another
            let homes = t.scenery.items.filter { $0.id == k.on }.map { s -> (SIMD2<Float>, Float) in
                let (c, sz) = t.scenery.place(t, s)
                return (c + [0, sz * s.extent.y * 0.2], sz * max(s.extent.x, s.extent.y) * 0.75)
            }
            guard !homes.isEmpty else { ones = []; return }
            if ones.isEmpty {
                for i in 0..<n() {
                    let (c, _) = homes[i % homes.count]
                    var o = One(pos: c)
                    o.perch = i % homes.count
                    o.goal = c
                    ones.append(o)
                }
            }
            for i in ones.indices {
                var o = ones[i]
                o.perch = min(o.perch, homes.count - 1)
                let (c, r) = homes[o.perch]
                let d = o.goal - o.pos
                if simd_length(d) < 3 {
                    o.wait -= dt
                    o.moving = 0
                    if o.wait <= 0 {
                        // mostly close in (nestled in it), sometimes out to the edge of its range
                        let a = Float.random(in: 0...(2 * .pi)), far = Float.random(in: 0...1) < 0.3 ? r : r * 0.5
                        o.goal = c + SIMD2(cosf(a), sinf(a) * 0.7 + 0.3) * Float.random(in: 0...far)
                        o.wait = Float.random(in: 0.5...2.5)
                    }
                } else {
                    let v = simd_normalize(d) * k.speed
                    o.vel += (v - o.vel) * min(1, dt * 3)
                    o.pos += o.vel * dt
                    if abs(o.vel.x) > 1 { o.dir = o.vel.x > 0 ? 1 : -1 }
                    o.moving = 1
                }
                o.phase += dt * (o.moving > 0.5 ? 9 : 4)              // the tail keeps going, slower when it hovers
                ones[i] = o
            }

        case .perch:
            let spots = t.scenery.items.filter { $0.id == k.on }.map { s -> SIMD2<Float> in
                let (c, sz) = t.scenery.place(t, s)
                return c + [0, sz * s.extent.y * 0.3 + k.size * k.extent.y * 0.9]   // its feet (c.y = -0.9) on the piece
            }
            guard !spots.isEmpty else { ones = []; return }
            if ones.isEmpty {
                for i in 0..<min(n(), spots.count) { var o = One(pos: spots[i]); o.perch = i; o.wait = Float.random(in: 6...20); ones.append(o) }
            }
            for i in ones.indices {
                var o = ones[i]
                o.perch = min(o.perch, spots.count - 1)
                if o.hop >= 0 {
                    // a hop: an arc to the next piece
                    o.hop += dt / 1.1
                    let to = spots[o.perch], s = min(1, o.hop)
                    o.pos = mix(o.from, to, t: s) + [0, sinf(s * .pi) * max(30, simd_distance(o.from, to) * 0.3)]
                    o.moving = 1; o.phase += dt * 8
                    if o.hop >= 1 { o.hop = -1; o.wait = Float.random(in: 8...25) }
                } else {
                    o.pos = spots[o.perch]; o.moving = 0; o.phase += dt * 0.5
                    o.wait -= dt
                    if o.wait <= 0, spots.count > 1 {
                        var next = Int.random(in: 0..<spots.count)
                        if next == o.perch { next = (next + 1) % spots.count }
                        o.from = o.pos; o.perch = next; o.hop = 0
                        o.dir = spots[next].x > o.pos.x ? 1 : -1
                    }
                }
                ones[i] = o
            }
        }

        // shy ones swim away from the mouse
        if k.shy, let cur = t.cursor, t.time - t.cursorAt < 2, k.behavior != .rest, k.behavior != .perch, k.behavior != .glass {
            for i in ones.indices {
                let away = ones[i].pos - cur, d = simd_length(away)
                if d < 90, d > 0.1 { ones[i].pos.x += away.x / d * (90 - d) * min(1, dt * 3) }
            }
        }
    }

    func sprites(_ t: Tank, layer: FaunaLayer) -> [Sprite] {
        guard let k = kind, shown > 0.01 else { return [] }
        let mine: FaunaLayer = k.behavior == .pass ? .background : k.front ? .front : .middle
        guard layer == mine else { return [] }
        let lit = 0.45 + 0.55 * t.light
        let water: SIMD3<Float> = SIMD3<Float>(0.12, 0.3, 0.4) * (0.5 + 0.5 * t.light)
        let far = k.behavior == .pass
        let color = mix(k.color * lit, water, t: far ? 0.55 : 0.1)
        let i = Float(index)
        return ones.map { o in
            let vertical = k.behavior == .glass
            return Sprite(pos: o.pos, dir: vertical ? [0, o.dir] : [o.dir, 0], size: k.size, kind: 36, glow: 0, phase: o.phase,
                          color: SIMD4(color, (far ? 0.6 : 1) * shown), extra: [vertical ? 1 : o.dir, o.seed, i, o.moving],
                          aux: [k.extent.x, k.extent.y, 0, 0])
        }
    }
}
