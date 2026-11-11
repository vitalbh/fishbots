import Foundation
import simd

/// Golden dust: fine specks hanging in the water that only show where a sun ray crosses them, glinting as they turn.
/// By day only, and only as much as the theme has sun rays.
final class Dust {
    private struct Speck { var pos: SIMD2<Float>; var depth: Float; var size: Float; var phase: Float; var turn: Float }

    /// On or off (Preferências → Aparência).
    var show = true
    private var specks: [Speck] = []
    /// The tank size they were scattered for (a big resize scatters them again).
    private var madeFor: SIMD2<Float> = .zero

    func update(_ t: Tank, dt: Float) {
        let size = t.size
        guard size.x > 10, size.y > 10 else { return }
        if specks.isEmpty || abs(madeFor.x - size.x) > 200 || abs(madeFor.y - size.y) > 200 {
            madeFor = size
            let n = max(150, min(700, Int(size.x * size.y / 1500)))
            specks = (0..<n).map { _ in
                Speck(pos: [Float.random(in: 0...size.x), size.y * Float.random(in: 0.12...0.96)], depth: Float.random(in: 0...1),
                      size: Float.random(in: 1.5...3.0), phase: Float.random(in: 0...60), turn: Float.random(in: 1.6...4.2))
            }
        }
        // almost weightless: they wander, sink very slowly and go with the current
        for i in specks.indices {
            var s = specks[i]
            s.phase += dt
            s.pos.x += (sinf(s.phase * 0.31 + s.turn) * 3.5 + t.current * 0.35 * (1.1 - s.depth)) * dt
            s.pos.y += (cosf(s.phase * 0.23 + s.turn * 2) * 2.6 - 0.7) * dt
            if s.pos.y < size.y * 0.1 { s.pos.y = size.y * 0.96; s.pos.x = Float.random(in: 0...size.x) }
            if s.pos.x < -10 { s.pos.x += size.x + 20 } else if s.pos.x > size.x + 10 { s.pos.x -= size.x + 20 }
            specks[i] = s
        }
    }

    /// `front`: the near ones, in front of the fish.
    func sprites(_ t: Tank, front: Bool) -> [Sprite] {
        let sun = smoothstep(0.68, 0.86, t.light) * (1 - t.turbidity * 0.6)
        guard show, sun > 0.02, t.rayStrength > 0.01 else { return [] }
        // gold, a little toward the color of the theme's rays
        let r = Themes.current.uniforms.rays
        let gold = mix(SIMD3<Float>(1.0, 0.8, 0.42), SIMD3(r.x, r.y, r.z), t: 0.3)
        var out: [Sprite] = []
        for s in specks where (s.depth < 0.35) == front {
            // how much of a ray is on it (the theme's strength taken out: a faint ray still shows its dust)
            let ray = t.rayLight(s.pos) / t.rayStrength
            let lit = smoothstep(0.03, 0.25, ray)
            guard lit > 0.02 else { continue }
            // a flat grain turning: dim most of the time, a glint when it faces the light
            let glint = powf(max(0, sinf(s.phase * s.turn)), 8)
            let glow = lit * sun * (0.3 + 0.7 * glint) * (front ? 1 : 0.7) * min(1, 0.4 + t.rayStrength * 2.5)
            out.append(Sprite(pos: s.pos + t.gaze * (-10 * (1 - s.depth)), dir: [1, 0], size: s.size * (1 + glint * 0.9), kind: 33, glow: min(1, glow),
                              phase: 0, color: SIMD4(gold * (1.4 + glint * 0.8), 1), extra: [1, 0, 0, 0]))
        }
        return out
    }
}
