import Foundation
import simd

/// The seaweed: where each blade stands (the same formula as the shader's) and how it bends, away from whoever
/// swims through it, with the current, with the whale passing by and to the music.
final class Weeds {
    /// How many the theme draws.
    var count = 9 { didSet { spots = Self.spots(count) } }
    /// The theme's shapes (0 blade, 1 kelp, 2 leafy, 3 reed, 4 ribbon), mixed along the tank (nil: the usual mix).
    var shapes: [Int]?
    /// Where each one stands: x (0…1) and height (a fraction of the screen), rising from y = 0.055.
    private(set) var spots: [(x: Float, h: Float)] = Weeds.spots(9)

    /// Each blade's bend (springs), in widths: the shader's unit. It only draws 16.
    private var bend = [Float](repeating: 0, count: 16)
    private var bendVel = [Float](repeating: 0, count: 16)
    /// Dancing to the music (the "dancing seaweed" visualizer): a wave sweeping across, and kicks.
    private var danceWave: (start: Double, dir: Float, strength: Float)?
    private var danceKicks: [(x: Float, when: Double, s: Float)] = []
    /// The last bit of current made by dragging through the water.
    private var flow: (at: SIMD2<Float>, flow: SIMD2<Float>, when: Double)?

    private static func spots(_ n: Int) -> [(x: Float, h: Float)] { (0..<n).map { k in
        let fk = Float(k)
        let fr: (Float) -> Float = { $0 - floorf($0) }
        // spread over the whole width: each blade in its own slice, at a random place within it (so it doesn't look lined up)
        let slice = 0.9 / Float(max(1, n))
        return (0.05 + (fk + 0.1 + 0.8 * fr(sinf(fk * 91.7) * 437.1)) * slice, 0.16 + fr(sinf(fk * 13.1) * 91.3) * 0.28)
    } }

    /// Each blade's kind: 0 thin blade, 1 kelp, 2 leafy stem (mixed, so neighbors differ).
    func kind(_ k: Int) -> Int {
        guard let s = shapes, !s.isEmpty else { return [0, 1, 2, 0, 2, 1, 0, 2, 1, 0, 1, 2, 0, 2, 0, 1][k % 16] }
        return s[(k * 7 + k / 3) % s.count]                                   // mixed, so neighbors differ
    }

    /// For the shader: x, height, bend and kind of each blade, 16 of them.
    func uniforms() -> [SIMD4<Float>] {
        (0..<16).map { k in k < spots.count ? SIMD4(spots[k].x, spots[k].h, bend[k], Float(kind(k))) : .zero }
    }

    /// Where each one's tip is now.
    func tips(_ t: Tank) -> [SIMD2<Float>] {
        spots.indices.map { k in [spots[k].x * t.size.x + (k < 16 ? bend[k] : 0) * t.size.x, t.size.y * (0.055 + spots[k].h)] }
    }

    /// A place on the nearest blade (for a fish to nibble at).
    func nearest(_ t: Tank, to p: SIMD2<Float>) -> SIMD2<Float> {
        let pts = spots.map { a -> SIMD2<Float> in
            [a.x * t.size.x, t.size.y * (0.055 + a.h * Float.random(in: 0.35...0.75))]
        }
        return pts.min { simd_distance($0, p) < simd_distance($1, p) } ?? p
    }

    /// x: a kick there; nil: a wave across the tank.
    func dance(_ t: Tank, at x: Float?, strength: Float) {
        danceKicks.removeAll { t.time - $0.when > 2.5 }
        if let w = danceWave, t.time - w.start > 2.4 { danceWave = nil }
        if let x { danceKicks.append((x, t.time, strength)); if danceKicks.count > 12 { danceKicks.removeFirst() } }
        else { danceWave = (t.time, Bool.random() ? 1 : -1, strength) }
    }

    /// A drag through the water: the blades nearby lean with it for a moment.
    func lean(_ t: Tank, with flow: SIMD2<Float>, at p: SIMD2<Float>) {
        self.flow = (p, flow, t.time)
    }

    func update(_ t: Tank, dt: Float) {
        let size = t.size, time = t.time
        // what pushes: the fish and the presences that swim (position, size)
        var pushers: [(SIMD2<Float>, Float)] = t.fish.filter { !$0.leaving }.map { ($0.pos, $0.size * (1 - 0.35 * $0.depth)) }
        for p in t.scene.presences where !p.leaving && [.swim, .drift, .hover].contains(p.kind.motion) { pushers.append((p.pos, p.kind.size * 0.8)) }
        for k in spots.indices where k < 16 {
            let x = spots[k].x * size.x
            let base = size.y * t.sand(spots[k].x)
            let top = base + spots[k].h * size.y
            var target: Float = 0
            for (pos, r0) in pushers where pos.y > base - 10 && pos.y < top + r0 {
                let dx = x - pos.x, r = r0 * 1.3 + 10
                guard abs(dx) < r * 2.5 else { continue }
                // away from it, more the closer it is; the push is in widths (the shader's unit)
                target += (dx >= 0 ? 1 : -1) * expf(-(dx * dx) / (r * r)) * r0 * 0.9 / max(1, size.x)
            }
            // a current made by dragging through the water: the seaweed nearby leans with it
            if let fp = flow, time - fp.when < 0.6 {
                let dx = x - fp.at.x, r: Float = 140
                target += fp.flow.x / max(1, size.x) * 1.5 * expf(-(dx * dx) / (r * r)) * Float(1 - (time - fp.when) / 0.6)
            }
            // the whale passing in the distance: a slow pressure wave sways the seaweed it goes by
            if let wp = t.fauna.whalePosition {
                let dx = x - wp.x, r = size.x * 0.25
                target += (dx >= 0 ? 1 : -1) * expf(-(dx * dx) / (r * r)) * 0.022 * sinf(Float(time) * 0.9)
            }
            // dancing to the music: a wave sweeping across the tank on a chord, little kicks on the notes
            if let w = danceWave {
                let u = Float(time - w.start) / 1.8
                let fx = (w.dir > 0 ? u : 1 - u) * size.x, dx = x - fx
                target += w.strength * 0.04 * w.dir * expf(-(dx * dx) / (130 * 130))
            }
            for kick in danceKicks {
                let age = Float(time - kick.when), dx = x - kick.x
                target += kick.s * 0.03 * sinf(age * 7) * expf(-age * 2.2) * expf(-(dx * dx) / (170 * 170))
            }
            target += t.current * 0.0011                          // the seaweed leans with the current
            target = max(-0.05, min(0.05, target))
            bendVel[k] += ((target - bend[k]) * 30 - bendVel[k] * 5) * dt
            bend[k] += bendVel[k] * dt
        }
    }
}
