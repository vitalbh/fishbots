import Foundation
import simd

/// What happened, for the sound. The app's music plays it (Music.sceneSound); the screen saver is silent.
enum SceneCue { case born, waiting, alert, error, done, effect }

/// What a presence is: how it moves and which sprite draws it. See docs/scene.md.
struct PresenceKind {
    enum Motion {
        case swim, drift, hover, walk, sit
        case float     // bobs at the surface, tilting with the waves
        case glass     // stuck on the side glass, next to the others from its source (small status lights)
        /// On the sand (their text goes above them).
        var grounded: Bool { self == .sit || self == .walk }
    }
    let id: String
    /// Sprite kind in the shader (25–30 are the presences' own drawings; the rest are reused).
    let sprite: Float
    let motion: Motion
    /// Size in points.
    let size: Float
    let color: SIMD3<Float>
    /// Height band (fraction of the tank) where swimmers, drifters and hoverers stay.
    var band: ClosedRange<Float> = 0.3...0.6
    /// Shows `value` in its drawing (hourglass, battery): the label adds the percentage.
    var meter = false
    /// Drops from the surface when it arrives (heavy objects).
    var drops = false
    /// Its voice (Scene.voices), when its state changes.
    var sound = "soft"
    /// From a pack: its index in PackPresences (the sprite is kind 37) and its quad (width, height relative to size).
    var pack: Int? = nil
    var extent: SIMD2<Float> = [1, 1]
}

/// A creature or object a plugin keeps in the tank, with a state and its own text.
final class Presence {
    let id: String             // "source:presence"
    let source: String
    var kind: PresenceKind
    var state: State
    var label: String
    var detail: String?
    var link: String?
    var value: Float?
    var color: SIMD3<Float>?
    /// The plugin's voice for it ("none": silent); nil: the kind's.
    var sound: String?
    /// Last "waiting" call (it's repeated every 2.5 min, like the fish).
    var reminder: Double = 0
    /// The helm's turn (radians): it turns while busy.
    var spin: Float = 0
    /// On the side glass: where it belongs, which way the tank's middle is (+1: to its right) and how much it has
    /// grown because it needs you (0…1).
    var home: SIMD2<Float> = .zero
    var side: Float = 1
    var swell: Float = 0
    /// When it arrived.
    let born: Double
    /// Home position (0…1 of the width).
    var u: Float
    var pos: SIMD2<Float>
    var vel: SIMD2<Float> = .zero
    var dir: Float = 1
    var phase: Float
    var since: Double
    /// Something changed (state or text): the detail shows for a few seconds.
    var changedAt: Double
    var leaving = false
    /// The pack kind it asked for, while it's drawn by a built-in stand-in (the pack isn't loaded, or left).
    var wantedKind: String?
    /// The plugin wants its own drawing even where the theme dresses this kind differently ("override_theme": true).
    var overrideTheme = false
    var party = false
    var alpha: Float = 0
    var shake: Float = 0
    var inkAt: Double = 0
    var bubbleAt: Double = 0
    /// Heavy objects fall from the surface until they land.
    var landed = true
    /// Swim height within the band (0…1), and when to pick a new one.
    var lane: Float
    var laneAt: Double = 0

    init(id: String, source: String, kind: PresenceKind, state: State, label: String, u: Float, pos: SIMD2<Float>, now: Double) {
        self.id = id
        self.source = source
        self.kind = kind
        self.state = state
        self.label = label
        self.u = u
        self.pos = pos
        self.phase = Float.random(in: 0...6)
        self.since = now
        self.born = now
        self.changedAt = now
        self.lane = Float.random(in: 0...1)
    }

    var baseColor: SIMD3<Float> { color ?? kind.color }
    /// Needs you: the detail stays on screen.
    var needsYou: Bool { [.waiting, .alert, .error].contains(state) }
    /// The little shake when it goes into error (the label shakes along).
    var shakeOffset: SIMD2<Float> { shake > 0 ? [sinf(phase * 40) * 3 * shake, 0] : .zero }
}
