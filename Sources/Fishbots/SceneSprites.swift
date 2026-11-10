import Foundation
import simd

/// The presences and the effects as sprites, behind or in front of the fish.
extension Scene {
    // MARK: - sprites

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
