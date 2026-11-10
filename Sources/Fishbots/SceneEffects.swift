import Foundation
import simd

/// One-off moments a plugin asks for: fireworks, lightning, a quake, a passing school… (docs/scene.md).
extension Scene {
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
}
