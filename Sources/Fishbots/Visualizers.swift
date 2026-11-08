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
    private(set) static var all: [Visualizer] = [Plankton(), AuroraVisualizer(), LiveSurface(), BubbleScore(), Constellation(), Fireworks()]

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
