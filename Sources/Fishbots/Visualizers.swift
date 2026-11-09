import Foundation
import simd

/// A note as visualizers see it.
struct VisualNote {
    /// Where it sounded: the fish that played, or a point at the note's height (music without a singer).
    let pos: SIMD2<Float>
    let midi: Int
    /// 0.3…1, from the velocity.
    let strength: Float
    let color: SIMD3<Float>
    /// Who played it (fish id or project), to connect consecutive notes.
    let projectKey: String
    let hasSinger: Bool
}

/// A visualizer: reacts to notes, chords and events by adding particles to the host (`Visual`). See docs/extensions.md.
protocol Visualizer: AnyObject {
    var id: String { get }
    /// Shown in the menu and the footer.
    var title: String { get }
    /// Music styles it suits, for the automatic choice.
    var styles: [String] { get }
    /// The aurora itself: chosen, it draws the background aurora at full strength.
    var isAurora: Bool { get }
    func note(_ n: VisualNote, in v: Visual)
    func chord(_ pcs: [Int], in v: Visual)
    func event(at p: SIMD2<Float>, in v: Visual)
    func update(dt: Float, in v: Visual)
}

extension Visualizer {
    var styles: [String] { [] }
    var isAurora: Bool { false }
    func chord(_ pcs: [Int], in v: Visual) {}
    func event(at p: SIMD2<Float>, in v: Visual) {}
    func update(dt: Float, in v: Visual) {}
}

/// The registry of visualizers, in menu order.
enum Visualizers {
    private(set) static var all: [Visualizer] = [Plankton(), AuroraVisualizer(), LiveSurface(), BubbleScore(), Constellation(), Fireworks(), LightSchool()]

    static func register(_ v: Visualizer) {
        if let i = all.firstIndex(where: { $0.id == v.id }) { all[i] = v } else { all.append(v) }
    }

    static func named(_ id: String) -> Visualizer? { all.first { $0.id == id } }

    /// Visualizers chosen for styles that don't come with one (e.g. a pack's style naming a visualizer).
    private static var styleDefaults: [String: String] = [:]
    static func setDefault(_ visualizer: String, forStyle style: String) { styleDefaults[style] = visualizer }

    /// Automatic: whatever fits the ambient music style (no music, plankton).
    static func forStyle(_ style: String?) -> Visualizer? {
        guard let s = style else { return named("plankton") }
        return styleDefaults[s].flatMap(named) ?? all.first { $0.styles.contains(s) } ?? named("plankton")
    }
}

// MARK: - built-in visualizers

/// Little glowing plankton swirling around whoever sang.
final class Plankton: Visualizer {
    let id = "plankton"
    var title: String { tr("🌟 plâncton") }
    let styles = ["lullaby"]

    func note(_ n: VisualNote, in v: Visual) {
        let count = Int(6 + 8 * n.strength)
        for _ in 0..<count {
            let a = Float.random(in: 0...(2 * .pi)), r = Float.random(in: 6...38)
            let c = mix(n.color, [0.35, 0.95, 1.0], t: 0.55)
            v.add(Visual.P(pos: n.pos + SIMD2(cosf(a), sinf(a)) * r, vel: SIMD2(Float.random(in: -6...6), Float.random(in: 2...10)),
                           maxLife: Float.random(in: 2.5...4.5), size: Float.random(in: 7...14), kind: 4,
                           color: SIMD4(c, 1), phase: Float.random(in: 0...6)))
        }
    }
}

/// The underwater aurora at full strength (the host already makes it react to notes and chords).
final class AuroraVisualizer: Visualizer {
    let id = "aurora"
    var title: String { tr("✨ aurora submarina") }
    let isAurora = true
    func note(_ n: VisualNote, in v: Visual) {}
}

/// Ripples on the water surface above whoever sang; events make a big wave.
final class LiveSurface: Visualizer {
    let id = "surface"
    var title: String { tr("🌊 superfície viva") }
    let styles = ["bossa"]

    func note(_ n: VisualNote, in v: Visual) { v.wave(x: n.pos.x, strength: n.strength) }
    func event(at p: SIMD2<Float>, in v: Visual) { v.wave(x: p.x, strength: 1.6) }
}

/// A score of bubbles: each note at its pitch, entering on the right and scrolling left, linked to the previous one.
final class BubbleScore: Visualizer {
    let id = "score"
    var title: String { tr("🎼 partitura de bolhas") }
    let styles = ["lofi"]
    private var lastNote: (SIMD2<Float>, Float)?
    private let scroll: Float = -34

    func note(_ n: VisualNote, in v: Visual) {
        let q: SIMD2<Float> = [v.size.x * 0.86, v.notePitch(n.midi)]
        let c = mix(n.color, [0.85, 0.97, 1], t: 0.5)
        v.add(Visual.P(pos: q, vel: [scroll, 0], maxLife: 18, size: 3 + n.strength * 5, kind: 1, color: SIMD4(c, 1)))
        if let (prev, t) = lastNote, v.time - t < 3.5 {
            let prevNow = prev + SIMD2(scroll * (v.time - t), 0)
            v.line(from: prevNow, until: q, color: SIMD4(c, 1), life: 18, width: 0.8, vel: [scroll, 0])
        }
        lastNote = (q, v.time)
    }
}

/// A plankton constellation: each note leaves a twinkling star near the singer, linked to the same singer's previous one.
final class Constellation: Visualizer {
    let id = "constellation"
    var title: String { tr("🌌 constelação de plâncton") }
    let styles = ["ambient"]   // the aurora is already in the background
    private var lastPoint: [String: (SIMD2<Float>, Float)] = [:]

    func note(_ n: VisualNote, in v: Visual) {
        let q = n.pos + SIMD2(Float.random(in: -40...40), Float.random(in: -30...30))
        let c = mix(n.color, [0.85, 0.95, 1], t: 0.6)
        v.add(Visual.P(pos: q, vel: [0, 1.5], maxLife: 10, size: 13, kind: 4, color: SIMD4(c, 1), phase: Float.random(in: 0...6), blink: 1))
        if let (prev, t) = lastPoint[n.projectKey], v.time - t < 7, simd_distance(prev, q) < 320 {
            v.line(from: prev, until: q, color: SIMD4(c, 1), life: 10, width: 1.1, vel: [0, 1.5])
        }
        lastPoint[n.projectKey] = (q, v.time)
    }
}

/// Light fireworks in the water, now and then, above whoever sang.
final class Fireworks: Visualizer {
    let id = "fireworks"
    var title: String { tr("🎆 fogos de luz") }

    func note(_ n: VisualNote, in v: Visual) {
        if Float.random(in: 0...1) < 0.4 { v.fire(at: n.pos + [0, 14], n: 12, radius: 45, color: mix(n.color, [1, 0.95, 0.8], t: 0.3)) }
    }
}

/// A school of light: little bioluminescent fish swimming together after the melody. Each note pulls the school to its
/// pitch's height, toward whoever played; each chord shifts its color; they leave a trail of light. A click scatters
/// them and they gather again; without music they slow down, circle and fade.
final class LightSchool: Visualizer {
    let id = "school"
    var title: String { tr("🐟 cardume de luz") }

    private struct Swimmer { var pos: SIMD2<Float>; var vel: SIMD2<Float>; var phase: Float; var offset: SIMD2<Float> }
    private var fish: [Swimmer] = []
    private var goal: SIMD2<Float> = .zero
    private var color: SIMD3<Float> = [0.4, 0.95, 1.0]
    private var target: SIMD3<Float> = [0.4, 0.95, 1.0]
    private var lastNote: Float = -100
    private var scatterUntil: Float = -100
    private var scatterFrom: SIMD2<Float> = .zero
    private var trailAt: Float = 0
    private var heading: Float = 1

    private func start(_ v: Visual) {
        let c: SIMD2<Float> = [v.size.x * 0.5, v.size.y * 0.5]
        goal = c
        fish = (0..<18).map { i in
            let a = Float(i) * 2.4
            return Swimmer(pos: c + SIMD2(cosf(a), sinf(a)) * Float(10 + i * 3), vel: [30, 0], phase: Float.random(in: 0...6),
                           offset: SIMD2(Float.random(in: -1...1) * 70, Float.random(in: -1...1) * 38))
        }
    }

    func note(_ n: VisualNote, in v: Visual) {
        if fish.isEmpty { start(v) }
        // toward whoever played (or onward, across the tank), at the pitch's height
        var x = n.hasSinger ? n.pos.x : goal.x + heading * Float.random(in: 60...140)
        if x < v.size.x * 0.1 || x > v.size.x * 0.9 { heading = -heading; x = max(v.size.x * 0.1, min(v.size.x * 0.9, x)) }
        goal = [x, v.notePitch(n.midi)]
        target = mix(target, n.color, t: 0.25)
        lastNote = v.time
        // the note lights them up for a moment
        for i in fish.indices.shuffled().prefix(Int(3 + 6 * n.strength)) {
            v.add(Visual.P(pos: fish[i].pos, vel: fish[i].vel * 0.2, maxLife: 0.9, size: 12, kind: 4,
                           color: SIMD4(mix(color, [1, 1, 1], t: 0.5), 1)))
        }
    }

    func chord(_ pcs: [Int], in v: Visual) {
        guard let root = pcs.first else { return }
        // the root's color around the color wheel, soft and luminous
        let h = Float(root % 12) / 12 * 2 * .pi
        target = SIMD3(0.55 + 0.4 * cosf(h), 0.55 + 0.4 * cosf(h - 2.094), 0.55 + 0.4 * cosf(h + 2.094)) * 0.6 + [0.25, 0.4, 0.4]
    }

    func event(at p: SIMD2<Float>, in v: Visual) {
        scatterUntil = v.time + 1.2
        scatterFrom = p
    }

    func update(dt: Float, in v: Visual) {
        if fish.isEmpty { start(v) }
        color += (target - color) * min(1, dt * 0.8)
        let quiet = v.time - lastNote
        let awake = max(0.15, 1 - smoothstep(4, 14, quiet))           // without music they slow down and fade
        // without notes for a while, the goal drifts in a slow loop through the middle of the tank
        if quiet > 3 {
            let t = v.time * 0.12
            goal = [v.size.x * (0.5 + 0.3 * sinf(t)), v.size.y * (0.5 + 0.15 * sinf(t * 1.7))]
        }
        var center = SIMD2<Float>.zero
        for f in fish { center += f.pos }
        center /= Float(max(1, fish.count))
        let scatter = v.time < scatterUntil
        for i in fish.indices {
            var f = fish[i]
            f.phase += dt
            // each keeps its own place in the school around the goal, wobbling
            let wob = SIMD2(sinf(f.phase * 1.7 + Float(i)), cosf(f.phase * 1.3 + Float(i) * 0.7)) * 18
            // the school's shape keeps changing: each place swings and breathes slowly
            let ang = 0.5 * sinf(v.time * 0.23 + Float(i) * 0.4), k = 1 + 0.3 * sinf(f.phase * 0.45 + Float(i))
            let off = SIMD2(f.offset.x * cosf(ang) - f.offset.y * sinf(ang), f.offset.x * sinf(ang) + f.offset.y * cosf(ang)) * k
            var want = goal + off + wob - f.pos
            var speed: Float = 30 + 70 * awake
            // keep a little room from the others, and stay together
            for (j, o) in fish.enumerated() where j != i {
                let d = f.pos - o.pos, l = simd_length(d)
                if l < 24 && l > 0.1 { want += d / l * (24 - l) * 2.5 }
            }
            want += (center - f.pos) * 0.05
            if scatter {
                let d = f.pos - scatterFrom, l = max(1, simd_length(d))
                want = d / l * 300 + want * 0.2
                speed = 260
            }
            let l = simd_length(want)
            let desired = l > 1 ? want / l * min(speed, l * 2.5) : .zero
            f.vel += (desired - f.vel) * min(1, dt * 2.2)
            f.pos += f.vel * dt
            f.pos.x = max(10, min(v.size.x - 10, f.pos.x))
            f.pos.y = max(v.size.y * 0.1, min(v.surfaceY - 12, f.pos.y))
            fish[i] = f
        }
        // the fish themselves (a bright head) every frame, the trail a little less often
        let glow = SIMD4(mix(color, [1, 1, 1], t: 0.3) * awake * 0.85, 1)
        for f in fish {
            v.add(Visual.P(pos: f.pos, vel: .zero, maxLife: max(0.05, dt * 1.5), size: 6, kind: 4, color: glow))
        }
        if v.time > trailAt {
            trailAt = v.time + 1 / 30
            for f in fish {
                v.add(Visual.P(pos: f.pos, vel: f.vel * 0.05, maxLife: 0.45, size: 3.5, kind: 4, color: SIMD4(color * awake * 0.45, 1)))
            }
        }
    }
}
