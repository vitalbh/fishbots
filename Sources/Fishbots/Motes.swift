import Foundation
import simd

/// Marine snow: specks drifting down at different depths (far ones behind the fish, near ones in front).
/// Whatever moves the water stirs them, and at night the plankton among them lights up.
final class Motes {
    private struct Mote { var pos: SIMD2<Float>; var depth: Float; var size: Float; var phase: Float; var speed: Float; var vel: SIMD2<Float> = .zero }

    /// On or off (Preferências → Aparência).
    var show = true
    private var motes: [Mote] = []
    /// The tank size they were scattered for (a big resize scatters them again).
    private var madeFor: SIMD2<Float> = .zero

    /// Pushes the snow away from a point (a click, the mouse, a quake). At night the plankton lights up.
    func stir(_ t: Tank, at p: SIMD2<Float>, radius r: Float, strength: Float) {
        var lit = 0
        for i in motes.indices {
            let d = motes[i].pos - p, l = simd_length(d)
            guard l < r, l > 0.1 else { continue }
            motes[i].vel += d / l * strength * (1 - l / r) * (1.2 - motes[i].depth)
            if t.isNight && lit < 14 && Float.random(in: 0...1) < 0.5 { glowPlankton(t, at: motes[i].pos); lit += 1 }
        }
        if t.isNight { for _ in 0..<Int(strength / 12) { glowPlankton(t, at: p + SIMD2(Float.random(in: -r...r), Float.random(in: -r...r)) * 0.5) } }
    }

    /// Carries the snow near a point along with a flow (dragging through the water).
    func push(_ flow: SIMD2<Float>, at p: SIMD2<Float>) {
        for i in motes.indices {
            let d = simd_distance(motes[i].pos, p)
            if d < 140 { motes[i].vel += flow * 2.2 * (1 - d / 140) }
        }
    }

    /// A blue-green spark where the plankton was disturbed.
    private func glowPlankton(_ t: Tank, at p: SIMD2<Float>) {
        t.addParticle(Particle(pos: p, vel: [Float.random(in: -6...6), Float.random(in: 2...10)], life: 0,
                               maxLife: Float.random(in: 0.9...1.8), size: Float.random(in: 4...7), grow: 1.5, kind: 4,
                               color: SIMD4(mix([0.25, 0.85, 1], [0.4, 1, 0.75], t: Float.random(in: 0...1)), 1)))
    }

    func update(_ t: Tank, dt: Float) {
        let size = t.size
        if motes.isEmpty || abs(madeFor.x - size.x) > 200 || abs(madeFor.y - size.y) > 200 {
            madeFor = size
            let n = max(40, min(170, Int(size.x * size.y / 8000)))
            motes = (0..<n).map { _ in
                let depth = Float.random(in: 0...1)
                return Mote(pos: [Float.random(in: 0...size.x), Float.random(in: 0...size.y)], depth: depth,
                            size: depth < 0.3 ? Float.random(in: 2.8...4.2) : Float.random(in: 1.3...2.4),
                            phase: Float.random(in: 0...20), speed: Float.random(in: 2...7) * (1.2 - depth * 0.6))
            }
        }
        // fish swimming by leave a wake in the snow
        let movers = t.fish.filter { !$0.leaving && simd_length($0.vel) > 35 }
        for i in motes.indices {
            var m = motes[i]
            m.phase += dt
            for f in movers {
                let d = m.pos - f.pos, l = simd_length(d), r = f.size * 1.6
                if l < r && l > 0.1 {
                    m.vel += (d / l * 40 + f.vel * 0.5) * (1 - l / r) * dt * (1.2 - m.depth)
                    // at night, a fish swimming fast leaves a glowing wake
                    if t.isNight && simd_length(f.vel) > 60 && Float.random(in: 0...1) < dt * 3 { glowPlankton(t, at: m.pos) }
                }
            }
            m.pos += m.vel * dt
            m.vel *= expf(-dt * 1.6)
            m.pos.y -= m.speed * dt
            m.pos.x += (sinf(m.phase * 0.35) * 5 + t.current * 0.5 * (1.1 - m.depth)) * dt
            if m.pos.y < size.y * t.sand(m.pos.x / max(1, size.x)) { m.pos.y = size.y * 0.97; m.pos.x = Float.random(in: 0...size.x) }
            if m.pos.x < -10 { m.pos.x += size.x + 20 } else if m.pos.x > size.x + 10 { m.pos.x -= size.x + 20 }
            motes[i] = m
        }
    }

    /// `front`: the near ones (in front of the fish). They move more with the parallax, and light up inside the sun rays.
    func sprites(_ t: Tank, front: Bool) -> [Sprite] {
        guard show else { return [] }
        let light = t.light
        let tint: SIMD3<Float> = SIMD3<Float>(0.78, 0.9, 0.95) * (0.55 + 0.45 * light)
        let look = t.themeLook("mote")
        let lamps = t.fauna.lamps(t)
        return motes.filter { ($0.depth < 0.3) == front }.map { m in
            let shift = t.gaze * (-12 * (1 - m.depth))
            let twinkle = 0.75 + 0.25 * sinf(m.phase * 1.7)
            let lit = min(2.5, t.rayLight(m.pos) * 7)
            // a lamp nearby (a lanternfish's lure) lights the snow in its own color
            let lamp = lamps.isEmpty ? SIMD3<Float>.zero : Lamp.light(lamps, at: m.pos)
            let lampLit = max(lamp.x, max(lamp.y, lamp.z))
            let glow = min(1, (front ? 0.62 : 0.38) * twinkle * (1 + lit) + lampLit * 0.9)
            if let (i, k) = look {
                // the theme's own drifting bits (petals, ice crystals): bigger than a speck, turning slowly
                return Sprite(pos: m.pos + shift, dir: [1, 0], size: m.size * 3.2, kind: 35, glow: glow, phase: Float(t.time),
                              color: SIMD4(k.color * (0.55 + 0.45 * light), front ? 0.9 : 0.6), extra: [1, m.phase.truncatingRemainder(dividingBy: 1), Float(i), 0],
                              aux: [k.extent.x, k.extent.y, 0, 0])
            }
            return Sprite(pos: m.pos + shift, dir: [1, 0], size: m.size * (1 + lit * 0.25 + lampLit * 0.5), kind: 33, glow: glow,
                          phase: 0, color: SIMD4(tint * (1 + lit * 0.3) + lamp * 1.1, 1), extra: [1, 0, 0, 0])
        }
    }
}
