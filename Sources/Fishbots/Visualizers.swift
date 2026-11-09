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
    private(set) static var all: [Visualizer] = [Plankton(), AuroraVisualizer(), LiveSurface(), BubbleScore(), Constellation(), Fireworks(), LightSchool(), DancingWeeds(), HarmonyJellies(), Sonar(), Storm()]

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

/// The seaweed dances: each chord sweeps across it like a wave, each note gives the blades near whoever played a
/// little kick, and lights a few tips, the glow drifting up off them.
final class DancingWeeds: Visualizer {
    let id = "weeds"
    var title: String { tr("🌿 algas que dançam") }

    func note(_ n: VisualNote, in v: Visual) {
        v.sway?(n.pos.x, 0.6 + 0.6 * n.strength)
        guard let tips = v.weedTips?(), !tips.isEmpty else { return }
        let near = tips.sorted { abs($0.x - n.pos.x) < abs($1.x - n.pos.x) }.prefix(2)
        let c = mix(n.color, [0.75, 1.0, 0.7], t: 0.45)
        for t in near {
            for _ in 0..<Int(2 + 3 * n.strength) {
                v.add(Visual.P(pos: t + SIMD2(Float.random(in: -6...6), Float.random(in: -10...4)), vel: [Float.random(in: -4...4), Float.random(in: 6...14)],
                               maxLife: Float.random(in: 1.4...2.4), size: Float.random(in: 6...10), kind: 4, color: SIMD4(c, 1), phase: Float.random(in: 0...6)))
            }
        }
    }

    func chord(_ pcs: [Int], in v: Visual) { v.sway?(nil, 1) }
    func event(at p: SIMD2<Float>, in v: Visual) { v.sway?(p.x, 1.6) }
}

/// Jellyfish of the harmony: each chord lets out a translucent jellyfish in its color, low in the water; it pulses
/// with each note, drifts up slowly and fades.
final class HarmonyJellies: Visualizer {
    let id = "jellies"
    var title: String { tr("🪼 águas-vivas da harmonia") }
    private struct Jelly { var pos: SIMD2<Float>; var color: SIMD3<Float>; var phase: Float; var pulse: Float; var age: Float; var size: Float; var drift: Float }
    private var jellies: [Jelly] = []
    private var bornAt: Float = -100

    private func spawn(_ v: Visual, color c: SIMD3<Float>, near x: Float? = nil) {
        let px = x.map { max(v.size.x * 0.08, min(v.size.x * 0.92, $0 + Float.random(in: -80...80))) } ?? v.size.x * Float.random(in: 0.12...0.88)
        jellies.append(Jelly(pos: [px, v.size.y * Float.random(in: 0.18...0.4)], color: c,
                             phase: Float.random(in: 0...6), pulse: 1, age: 0, size: Float.random(in: 20...32), drift: Float.random(in: -1...1)))
        if jellies.count > 6 { jellies.removeFirst() }
        bornAt = v.time
    }

    func chord(_ pcs: [Int], in v: Visual) {
        guard let root = pcs.first else { return }
        let h = Float(root % 12) / 12 * 2 * .pi
        spawn(v, color: SIMD3(0.55 + 0.4 * cosf(h), 0.55 + 0.4 * cosf(h - 2.094), 0.55 + 0.4 * cosf(h + 2.094)) * 0.7 + [0.2, 0.25, 0.35])
    }

    func note(_ n: VisualNote, in v: Visual) {
        // few of them about (chords come slowly): a note lets one out too, now and then, in its color
        if jellies.count < 3 && v.time - bornAt > 3 { spawn(v, color: mix(n.color, [0.8, 0.85, 1], t: 0.4), near: n.pos.x) }
        // the nearest one pulses
        guard let i = jellies.indices.min(by: { simd_distance(jellies[$0].pos, n.pos) < simd_distance(jellies[$1].pos, n.pos) }) else { return }
        jellies[i].pulse = min(1.5, jellies[i].pulse + 0.5 + 0.5 * n.strength)
    }

    func event(at p: SIMD2<Float>, in v: Visual) {
        for i in jellies.indices where simd_distance(jellies[i].pos, p) < 200 { jellies[i].pulse = 1.5 }
    }

    func update(dt: Float, in v: Visual) {
        for i in jellies.indices {
            var j = jellies[i]
            j.age += dt
            j.pulse *= expf(-dt * 1.5)
            j.phase += dt * (1.0 + 4 * j.pulse)                 // a note: a quick contraction
            j.pos.y += (6 + 18 * j.pulse) * dt                   // each pulse pushes it up
            j.pos.x += sinf(j.age * 0.4 + j.drift * 3) * 6 * dt + j.drift * 3 * dt
            jellies[i] = j
        }
        jellies.removeAll { $0.age > 16 || $0.pos.y > v.size.y * 0.9 }
        for j in jellies {
            let fade = min(1, j.age / 1.5) * (1 - smoothstep(12, 16, j.age)) * (1 - smoothstep(v.size.y * 0.8, v.size.y * 0.9, j.pos.y))
            let c = j.color * fade * (0.75 + 0.35 * j.pulse)
            v.add(Visual.P(pos: j.pos, vel: .zero, maxLife: max(0.05, dt * 1.5), size: j.size, kind: 5, color: SIMD4(c, 0.8 * fade), phase: j.phase))
        }
    }

}

/// Sonar: each note sends out rings of sound from whoever played; low notes make wide, slow rings, high ones small,
/// quick ones; an echo follows, fainter. A click sends a big ping.
final class Sonar: Visualizer {
    let id = "sonar"
    var title: String { tr("📡 sonar") }
    private var echoes: [(at: SIMD2<Float>, when: Float, grow: Float, life: Float, color: SIMD3<Float>)] = []

    private func ping(_ v: Visual, at p: SIMD2<Float>, low: Float, color: SIMD3<Float>, strength: Float) {
        let grow = mix(170, 70, t: low), life = mix(1.0, 3.2, t: low)
        v.add(Visual.P(pos: p, vel: .zero, maxLife: life, size: 4, grow: grow, kind: 2, color: SIMD4(color * (0.6 + 0.5 * strength), 1)))
        echoes.append((p, v.time + 0.35 + 0.25 * low, grow, life * 0.8, color * 0.45))
    }

    func note(_ n: VisualNote, in v: Visual) {
        let low = 1 - max(0, min(1, Float(n.midi - 48) / 36))
        ping(v, at: n.pos, low: low, color: mix(n.color, [0.55, 0.95, 1.0], t: 0.5), strength: n.strength)
    }

    func event(at p: SIMD2<Float>, in v: Visual) { ping(v, at: p, low: 1, color: [0.7, 1, 1], strength: 1.4) }

    func update(dt: Float, in v: Visual) {
        for e in echoes where v.time >= e.when {
            v.add(Visual.P(pos: e.at, vel: .zero, maxLife: e.life, size: 4, grow: e.grow, kind: 2, color: SIMD4(e.color, 1)))
        }
        echoes.removeAll { v.time >= $0.when }
    }
}

private func mix(_ a: Float, _ b: Float, t: Float) -> Float { a + (b - a) * t }

/// A storm: lightning strikes the surface (a jagged bolt down to the water, a burst of light where it hits, a
/// wobbly streak into the water, a ripple), and the tank flashes with the music: chords strike, strong notes flash
/// and sometimes strike, soft ones flicker. When the music gets heavy, a current runs through the water.
final class Storm: Visualizer {
    let id = "storm"
    var title: String { tr("⛈️ tempestade") }
    private var heavy: Float = 0
    private var dir: Float = 1
    private var dirAt: Float = 0
    private var lastBolt: Float = -100

    private func bolt(_ v: Visual, x: Float, strength: Float) {
        guard v.time - lastBolt > 0.25 else { return }
        lastBolt = v.time
        let top = v.size.y + 4, surf = v.surfaceY
        let white: SIMD4<Float> = [0.92, 0.96, 1, 1]
        // in the air: a jagged bolt with a branch
        var p: SIMD2<Float> = [x + Float.random(in: -30...30), top]
        let steps = 4
        for i in 1...steps {
            let q: SIMD2<Float> = [x + Float.random(in: -14...14) * Float(steps - i) / Float(steps), top + (surf - top) * Float(i) / Float(steps)]
            v.line(from: p, until: q, color: white, life: 0.32, width: 1.6 + strength, vel: .zero)
            if i == 2 && Float.random(in: 0...1) < 0.6 {
                let b = q + [Float.random(in: -26...26), (surf - top) * 0.3]
                v.line(from: q, until: b, color: white * 0.7, life: 0.25, width: 1, vel: .zero)
            }
            p = q
        }
        // where it hits: a burst of light and a ripple, and a wobbly streak going down into the water, fading
        v.add(Visual.P(pos: [p.x, surf - 2], vel: .zero, maxLife: 0.5, size: 26 + 20 * strength, kind: 4, color: [0.85, 0.92, 1, 1]))
        v.wave(x: p.x, strength: 0.8 + strength)
        var w = p
        for i in 1...4 {
            let q: SIMD2<Float> = [w.x + Float.random(in: -18...18), surf - v.size.y * 0.05 * Float(i)]
            let fade = 1 - Float(i) * 0.18
            v.line(from: w, until: q, color: SIMD4(SIMD3<Float>(0.9, 0.95, 1) * fade, 1), life: 0.4, width: 1.8, vel: .zero)
            v.add(Visual.P(pos: q, vel: .zero, maxLife: 0.35, size: 9 * fade, kind: 4, color: SIMD4(SIMD3<Float>(0.8, 0.9, 1) * fade, 1)))
            w = q
        }
        v.flashScene?(0.55 + 0.4 * strength, [0.6, 0.72, 0.95])
    }

    func note(_ n: VisualNote, in v: Visual) {
        heavy += n.strength * 0.25
        if n.strength > 0.7 {
            v.flashScene?(0.18 + 0.3 * (n.strength - 0.7) / 0.3, mix(n.color, [0.7, 0.8, 1], t: 0.6))
            if Float.random(in: 0...1) < 0.2 { bolt(v, x: n.pos.x, strength: 0.4) }
        } else {
            v.flashScene?(0.06 + 0.08 * n.strength, [0.6, 0.72, 0.95])
        }
    }

    func chord(_ pcs: [Int], in v: Visual) { bolt(v, x: v.size.x * Float.random(in: 0.1...0.9), strength: 1) }
    func event(at p: SIMD2<Float>, in v: Visual) { bolt(v, x: p.x, strength: 1.2) }

    func update(dt: Float, in v: Visual) {
        heavy *= expf(-dt * 0.8)
        // a heavy stretch of music: the water runs, now one way, now the other
        if v.time - dirAt > 25 { dirAt = v.time; dir = Bool.random() ? 1 : -1 }
        let push = smoothstep(0.9, 2.4, heavy) * 45 * dir
        if abs(push) > 0.5 { v.stream?(push) }
    }
}
