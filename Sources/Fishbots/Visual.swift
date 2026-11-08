import Foundation
import simd

/// The aquarium's visualizers: aquatic versions of the Jardim de Chuva ones. They react to each note (with the position and color
/// of the fish that played), to the chord, the energy and events. They sit behind the fish and are subtle.
///
/// `Visual` is the host: it owns the particles, the helpers to make them (spark, line, fire, wave) and the aurora, which is
/// a core background feature. Each visualizer is a `Visualizer` registered in `Visualizers` (Visualizers.swift).
final class Visual {
    /// A particle drawn as a sprite (kind 1 bubble, 4 glow, 7 line, 8 ripple).
    struct P {
        var pos: SIMD2<Float>
        var vel: SIMD2<Float>
        var life: Float = 0
        var maxLife: Float
        var size: Float
        var grow: Float = 0
        var kind: Float
        var color: SIMD4<Float>
        var dir: SIMD2<Float> = [1, 0]
        var width: Float = 0       // lines
        var phase: Float = 0
        var blink: Float = 0
        var drag: Float = 0        // the water slows it (fireworks)
    }

    var size: SIMD2<Float> = [960, 600]
    var energy: Float = 0
    private var parts: [P] = []
    private(set) var time: Float = 0

    // aurora
    private var curtains: [(x: Float, phase: Float, vel: Float, pulse: Float, goal: Float?)] =
        [(0.25, 0, 0.012, 0, nil), (0.55, 2.1, -0.009, 0, nil), (0.8, 4.2, 0.007, 0, nil)]

    /// Aurora variation, drawn for each piece (or every 3 min without music).
    struct AuroraVariant {
        var bands = false       // horizontal bands up high (otherwise, vertical curtains)
        var twoColors = true     // one color on top, another at the bottom
        var breathes = true       // swells on each chord and fades out
        var segue = false        // the nearest curtain slides toward whoever sings
        var stars = false     // little stars twinkling inside the veil
    }
    private(set) var va = AuroraVariant()
    private var auroraRerollAt: Float = 0
    private var pulseAll: Float = 0
    private var starAt: Float = 0
    /// Daylight (0.62 at night … 1 by day): by day the aurora becomes golden sunbeams.
    var light: Float = 1
    private var day: Bool { light > 0.92 }

    /// Style palette: (top color, bottom color).
    var palette: (SIMD3<Float>, SIMD3<Float>) {
        if day { return ([1.0, 0.85, 0.45], [1.0, 0.95, 0.72]) }
        switch style {
        case "lullaby": return ([0.75, 0.6, 1.0], [1.0, 0.6, 0.82])
        case "ambient": return ([0.35, 0.95, 0.8], [0.4, 0.62, 1.0])
        case "lofi": return ([1.0, 0.75, 0.38], [1.0, 0.5, 0.42])
        case "bossa": return ([0.3, 0.9, 0.95], [0.5, 1.0, 0.6])
        default: return ([0.35, 1.0, 0.6], [0.72, 0.45, 1.0])
        }
    }

    func rerollAurora() {
        va = AuroraVariant(bands: Float.random(in: 0...1) < 0.45, twoColors: Float.random(in: 0...1) < 0.65,
                       breathes: Float.random(in: 0...1) < 0.6, segue: Float.random(in: 0...1) < 0.45,
                       stars: Float.random(in: 0...1) < 0.5)
        auroraRerollAt = time
    }

    /// The current combination, for the footer.
    var auroraDescription: String {
        var p: [String] = [tr(day ? "raios de sol" : va.bands ? "faixas" : "cortinas")]
        if va.twoColors { p.append(tr("duas cores")) }
        if va.breathes { p.append(tr("respirando")) }
        if va.segue { p.append(tr("seguindo quem canta")) }
        if va.stars { p.append(tr("estrelinhas")) }
        return p.joined(separator: ", ")
    }
    private var auroraColor: SIMD3<Float> = [0.3, 0.85, 0.7]
    private var auroraTarget: SIMD3<Float> = [0.3, 0.85, 0.7]
    private var auroraStrength: Float = 0

    // MARK: choice

    /// "auto", "random", "off" or a visualizer's id.
    var choice: String {
        get { UserDefaults.standard.string(forKey: "visual") ?? "auto" }
        set { UserDefaults.standard.set(newValue, forKey: "visual"); if newValue == "random" { reroll() } }
    }
    private var rolled = "plankton"
    /// The theme's visualizer, used instead of the style's when the choice is "auto".
    var themeVisualizer: String?
    var style: String?

    /// Aurora as the background of everything (default: on); the other visualizers appear on top.
    var auroraBackground: Bool {
        get { UserDefaults.standard.object(forKey: "auroraBackground") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "auroraBackground") }
    }
    /// The chosen visualizer is the aurora itself (drawn at full strength).
    var auroraChosen: Bool { mode?.isAurora == true }
    private var auroraVisible: Bool { auroraBackground || auroraChosen }

    /// The visualizer playing now (nil: none).
    var mode: Visualizer? {
        switch choice {
        case "off": return nil
        case "auto": return themeVisualizer.flatMap(Visualizers.named) ?? Visualizers.forStyle(style)
        case "random": return Visualizers.named(rolled) ?? Visualizers.forStyle(style)
        default: return Visualizers.named(choice) ?? Visualizers.forStyle(style)
        }
    }

    func reroll() { rolled = Visualizers.all.map(\.id).filter { $0 != rolled }.randomElement() ?? "plankton" }

    /// New ambient music piece: in random mode, switches the visualizer.
    func newPiece(style id: String) {
        style = id
        rerollAurora()
        if choice == "random" { reroll() }
    }

    // MARK: events

    var surfaceY: Float { size.y * 0.965 }

    /// Height for a pitch: low notes near the bottom, high ones near the top.
    func notePitch(_ midi: Int) -> Float {
        let t = max(0, min(1, Float(midi - 50) / 36))
        return size.y * (0.18 + 0.62 * t)
    }

    /// A note sounded. `pos` is the position of the fish that played (nil: music without a singer).
    func note(pos: SIMD2<Float>?, midi: Int, vel: Float, color: SIMD3<Float>, projectKey: String) {
        let p = pos ?? [size.x * Float.random(in: 0.3...0.7), notePitch(midi)]
        let strength = max(0.3, min(1, vel * 3))
        // the aurora (background or chosen) always reacts: the curtain nearest to whoever played lights up and may move toward them
        if auroraVisible, let i = curtains.indices.min(by: { abs(curtains[$0].x * size.x - p.x) < abs(curtains[$1].x * size.x - p.x) }) {
            curtains[i].pulse = min(1, curtains[i].pulse + 0.35 * strength)
            if va.segue && pos != nil { curtains[i].goal = max(0.08, min(0.92, p.x / max(1, size.x))) }
        }
        mode?.note(VisualNote(pos: p, midi: midi, strength: strength, color: color, projectKey: projectKey, hasSinger: pos != nil), in: self)
    }

    /// New chord: the aurora gradually changes color (each root has a hue).
    func chord(_ pcs: [Int]) {
        guard let root = pcs.first else { return }
        auroraTarget = hsv(Float(root) / 12 * 0.8 + 0.35, 0.55, 0.95)
        if va.breathes { pulseAll = 1 }
        mode?.chord(pcs, in: self)
    }

    /// Event (deploy, food): in any mode, a light firework opens in the water; on the surface, also a big wave.
    func event(at p: SIMD2<Float>) {
        guard mode != nil else { return }
        let base: SIMD2<Float> = [p.x, min(p.y, size.y * 0.55)]
        fire(at: base, n: 30, radius: 95, color: hsv(Float.random(in: 0...1), 0.45, 1))
        mode?.event(at: p, in: self)
    }

    /// Burst of little dots slowed by the water; they rise slowly as they fade.
    func fire(at c: SIMD2<Float>, n: Int, radius: Float, color: SIMD3<Float>) {
        for i in 0..<n {
            let a = Float(i) / Float(n) * 2 * .pi + Float.random(in: -0.1...0.1)
            let v = radius * Float.random(in: 0.75...1.1)
            let tone = mix(color, [1, 1, 1], t: Float.random(in: 0...0.35))
            parts.append(P(pos: c, vel: SIMD2(cosf(a), sinf(a)) * v + [0, 8], maxLife: Float.random(in: 2.4...3.4),
                           size: Float.random(in: 6...10), kind: 4, color: SIMD4(tone, 1), phase: Float.random(in: 0...6), drag: 1.6))
        }
    }

    func line(from a: SIMD2<Float>, until b: SIMD2<Float>, color: SIMD4<Float>, life: Float, width: Float, vel: SIMD2<Float>) {
        let d = b - a, l = simd_length(d)
        guard l > 2 else { return }
        parts.append(P(pos: (a + b) / 2, vel: vel, maxLife: life, size: l / 2, kind: 7, color: color, dir: d / l, width: width))
    }

    /// Splash from a jump: a wave on the surface (in any mode, if there's a visualizer).
    func splash(x: Float) { if mode != nil || auroraBackground { wave(x: x, strength: 1.2) } }

    func wave(x: Float, strength: Float) {
        parts.append(P(pos: [x, surfaceY], vel: .zero, maxLife: 2.2, size: 8, grow: 75 * strength, kind: 8, color: [0.8, 0.95, 1, 1]))
        if strength > 0.7 {
            parts.append(P(pos: [x, surfaceY], vel: .zero, maxLife: 2.2, size: 4, grow: 38 * strength, kind: 8, color: [0.8, 0.95, 1, 0.8]))
        }
    }

    /// Adds a particle (for visualizers).
    func add(_ p: P) { parts.append(p) }

    // MARK: frame

    func update(dt: Float) {
        time += dt
        for i in parts.indices {
            parts[i].life += dt
            if parts[i].drag > 0 {
                parts[i].vel *= expf(-parts[i].drag * dt)
                parts[i].vel.y += 6 * dt          // buoyancy: they rise slowly
            }
            parts[i].pos += parts[i].vel * dt
            parts[i].size += parts[i].grow * dt
            parts[i].phase += dt
        }
        parts.removeAll { $0.life > $0.maxLife || $0.pos.x < -60 }
        if parts.count > 1500 { parts.removeFirst(parts.count - 1500) }

        // aurora: color and strength change slowly
        auroraColor += (auroraTarget - auroraColor) * min(1, dt * 0.25)
        // as background, a bit more subtle (the visualizer on top shows better); when chosen, full
        let goal: Float = auroraChosen ? 0.55 + 0.45 * energy : auroraBackground ? 0.42 + 0.35 * energy : 0
        auroraStrength += (goal - auroraStrength) * min(1, dt * 0.5)
        // without music, draws a new variation every 3 min
        if style == nil && time - auroraRerollAt > 180 { rerollAurora() }
        pulseAll *= expf(-dt * 0.3)
        let sway = 0.35 + energy * 1.7                      // sways faster when people are working
        for i in curtains.indices {
            if let a = curtains[i].goal {
                curtains[i].x += (a - curtains[i].x) * min(1, dt * 0.5)
                if abs(a - curtains[i].x) < 0.01 { curtains[i].goal = nil }
            } else {
                curtains[i].x += curtains[i].vel * dt * 0.3
                if curtains[i].x < 0.1 || curtains[i].x > 0.9 { curtains[i].vel = -curtains[i].vel }
            }
            curtains[i].phase += dt * sway
            curtains[i].pulse *= expf(-dt * 0.8)
        }
        mode?.update(dt: dt, in: self)
        // little stars inside the veil
        if va.stars && auroraStrength > 0.2 && time > starAt {
            starAt = time + Float.random(in: 0.08...0.25)
            let c = curtains.randomElement()!
            let q: SIMD2<Float> = va.bands && !day
                ? [size.x * Float.random(in: 0.15...0.85), size.y * Float.random(in: 0.66...0.86)]
                : [c.x * size.x + Float.random(in: -0.12...0.12) * size.y * 0.42, size.y * 0.66 + Float.random(in: -0.25...0.35) * size.y * 0.42]
            parts.append(P(pos: q, vel: [0, Float.random(in: -2...2)], maxLife: Float.random(in: 1.4...3), size: Float.random(in: 4...7),
                           kind: 4, color: SIMD4(mix(palette.0, [1, 1, 1], t: 0.6), 1), phase: Float.random(in: 0...6), blink: 1))
        }
    }

    func sprites() -> [Sprite] {
        var out: [Sprite] = []
        out.reserveCapacity(parts.count + 3)
        if auroraStrength > 0.01 {
            let (top, bottom) = palette
            let topColor = mix(top, auroraColor, t: day ? 0.1 : 0.35)
            let bottomColor = mix(bottom, auroraColor, t: day ? 0.05 : 0.2)
            let pack = Float(Int(bottomColor.x * 255) << 16 | Int(bottomColor.y * 255) << 8 | Int(bottomColor.z * 255))
            let rest: Float = va.breathes ? 0.55 + 0.6 * pulseAll : 1
            let night: Float = light < 0.7 ? 1.25 : day ? 0.75 : 1
            let shape: Float = day ? 2 : va.bands ? 1 : 0
            let two: Float = va.twoColors ? 1 : 0
            if shape == 1 {
                // two wavy ribbons up high
                for (i, c) in curtains.prefix(2).enumerated() {
                    out.append(Sprite(pos: [size.x * (0.4 + Float(i) * 0.22), size.y * (0.8 - Float(i) * 0.1)], dir: [1, 0],
                                      size: size.x * 0.5, kind: 9, glow: auroraStrength * (0.6 + 0.6 * c.pulse) * rest * night,
                                      phase: c.phase + Float(i) * 2, color: SIMD4(topColor, 1), extra: [1, shape, pack, two]))
                }
            } else {
                for c in curtains {
                    out.append(Sprite(pos: [c.x * size.x, size.y * 0.66], dir: [1, 0], size: size.y * 0.42, kind: 9,
                                      glow: auroraStrength * (0.6 + 0.6 * c.pulse) * rest * night, phase: c.phase,
                                      color: SIMD4(topColor, 1), extra: [1, shape, pack, two]))
                }
            }
        }
        for p in parts {
            let k = 1 - p.life / p.maxLife
            var g: Float
            switch p.kind {
            case 4:   // glow: lights up fast, fades slowly, twinkles
                let input = min(1, p.life / 0.25)
                g = input * k * (p.blink > 0 ? 0.75 + 0.25 * sinf(p.phase * 3) : 0.85 + 0.15 * sinf(p.phase * 9))
            case 7: g = min(1, p.life / 0.4) * k * 0.55
            case 1: g = min(1, k * 3)
            default: g = k
            }
            out.append(Sprite(pos: p.pos, dir: p.dir, size: p.size, kind: p.kind, glow: g, phase: p.phase,
                              color: p.color, extra: [1, 0, 0, p.width]))
        }
        return out
    }
}
