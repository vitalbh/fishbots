import Foundation
import simd

/// What the hour does to the tank: where the sun or moon is, and the color it gives the water.
extension Sky {
    /// The sun by day and the moon by night, seen through the surface: (x 0…1, strength, warmth, unused).
    /// The sun crosses from left (morning) to right (evening), warmer when low; the moon crosses at night.
    func disc(hour h: Float) -> SIMD4<Float> {
        if h >= 6 && h <= 18.5 {
            let k = (h - 6) / 12.5
            let low = 1 - sinf(k * .pi)                                         // 1 at sunrise and sunset
            return [0.1 + 0.8 * k, (0.36 - 0.06 * low) * sun, min(1, low * 1.3), 0]
        }
        let n = (h > 18.5 ? h - 18.5 : h + 5.5) / 11.5                           // 18:30 → 6:00
        let fade = smoothstep(0, 0.08, n) * (1 - smoothstep(0.92, 1, n))
        return [0.1 + 0.8 * n, 0.32 * fade * moon, 0, 0]
    }

    /// The color of the hour: warm at dawn, neutral by day, golden late afternoon, violet at dusk, blue at night.
    /// rgb multiplies the image; w is moonlight (0…1).
    func grade(hour h: Float) -> SIMD4<Float> {
        func k(_ c: SIMD3<Float>, _ moonlight: Float) -> SIMD4<Float> { SIMD4(c, min(1, moonlight * moon)) }
        let keys: [(Float, SIMD4<Float>)] = [
            (0, k(night, 1)), (4.8, k(night, 1)), (6.3, k(dawn, 0.2)), (8.5, k(day, 0)),
            (16, k(day, 0)), (18.2, k(golden, 0)), (19.6, k(dusk, 0.3)), (21, k(night, 1)),
            (24, k(night, 1)),
        ]
        for i in 1..<keys.count where h <= keys[i].0 {
            let (h0, a) = keys[i - 1], (h1, b) = keys[i]
            let k = smoothstep(0, 1, (h - h0) / max(0.001, h1 - h0))
            return a + (b - a) * k
        }
        return keys[0].1
    }
}
