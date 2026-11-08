import Foundation

/// The scene's look, as the shader gets it (must match `struct Theme` in Shaders.swift). Colors are float4 so the
/// layout is the same on both sides; alpha is unused.
struct ThemeUniforms {
    var deep: SIMD4<Float>         // water at the bottom
    var shallow: SIMD4<Float>      // water near the surface
    var rays: SIMD4<Float>         // light rays from the surface
    var caustics: SIMD4<Float>
    var surface: SIMD4<Float>      // the band above the waterline
    var farWeed: SIMD4<Float>      // seaweed in the distance (mixed with the fog)
    var weedLow: SIMD4<Float>      // seaweed, at the base…
    var weedHigh: SIMD4<Float>     // …and at the tip
    var sandDark: SIMD4<Float>
    var sandLight: SIMD4<Float>
    var murk: SIMD4<Float>         // the color of murky water (disk filling up)
    /// x: seaweed count (0…16), y: distant seaweed count (0…16), z: rays strength, w: caustics strength.
    var params: SIMD4<Float>
}

/// A scene: water, light, seaweed and sand, plus optional defaults for the visualizer, the music and the fauna.
/// Built-ins are written in the same JSON format that packs will use (docs/extensions.md).
struct Theme {
    let id: String
    let name: String               // shown in the menu (Portuguese, translated by tr)
    /// Names in other languages, from a pack: {"en": "Coral reef"}.
    var names: [String: String] = [:]
    var displayName: String { names[L10n.isPortuguese ? "pt" : "en"] ?? tr(name) }
    var uniforms: ThemeUniforms
    /// The visualizer used when the choice is "auto" (otherwise it follows the music style).
    var visualizer: String?
    /// The music style chosen more often in this scene.
    var music: String?
    /// Which creatures live here (nil: all of them).
    var fauna: [String]?
    /// Which scenery sits on the sand: "rock", "shell", "chest" (nil: all of it).
    var scenery: [String]?
    var weedCount: Int { Int(uniforms.params.x) }

    /// Reads a theme from JSON. Colors are "#rrggbb" or [r, g, b] (0…1). Missing values come from `base`.
    init?(json: [String: Any], base: Theme? = nil) {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        name = json["name"] as? String ?? id
        names = json["names"] as? [String: String] ?? [:]
        var u = base?.uniforms ?? Theme.classicUniforms
        func color(_ v: Any?) -> SIMD4<Float>? {
            if let a = v as? [NSNumber], a.count >= 3 { return [a[0].floatValue, a[1].floatValue, a[2].floatValue, 1] }
            if let s = v as? String, s.hasPrefix("#"), s.count == 7, let n = UInt32(s.dropFirst(), radix: 16) {
                return [Float((n >> 16) & 255) / 255, Float((n >> 8) & 255) / 255, Float(n & 255) / 255, 1]
            }
            return nil
        }
        func number(_ v: Any?, _ range: ClosedRange<Float>) -> Float? {
            (v as? NSNumber).map { min(range.upperBound, max(range.lowerBound, $0.floatValue)) }
        }
        let water = json["water"] as? [String: Any] ?? [:]
        let weeds = json["weeds"] as? [String: Any] ?? [:]
        let sand = json["sand"] as? [String: Any] ?? [:]
        if let c = color(water["deep"]) { u.deep = c }
        if let c = color(water["shallow"]) { u.shallow = c }
        if let c = color(water["rays"]) { u.rays = c }
        if let c = color(water["caustics"]) { u.caustics = c }
        if let c = color(water["surface"]) { u.surface = c }
        if let c = color(water["murk"]) { u.murk = c }
        if let n = number(water["raysStrength"], 0...1) { u.params.z = n }
        if let n = number(water["causticsStrength"], 0...1) { u.params.w = n }
        if let c = color(weeds["far"]) { u.farWeed = c }
        if let c = color(weeds["low"]) { u.weedLow = c }
        if let c = color(weeds["high"]) { u.weedHigh = c }
        if let n = number(weeds["count"], 0...16) { u.params.x = n.rounded() }
        if let n = number(weeds["farCount"], 0...16) { u.params.y = n.rounded() }
        if let c = color(sand["dark"]) { u.sandDark = c }
        if let c = color(sand["light"]) { u.sandLight = c }
        uniforms = u
        visualizer = json["visualizer"] as? String ?? base?.visualizer
        music = json["music"] as? String ?? base?.music
        fauna = json["fauna"] as? [String] ?? base?.fauna
        scenery = json["scenery"] as? [String] ?? base?.scenery
    }

    /// The original look.
    static let classicUniforms = ThemeUniforms(
        deep: [0.012, 0.05, 0.11, 1], shallow: [0.05, 0.30, 0.40, 1], rays: [0.25, 0.45, 0.45, 1],
        caustics: [0.5, 0.75, 0.75, 1], surface: [0.35, 0.6, 0.65, 1], farWeed: [0.08, 0.2, 0.14, 1],
        weedLow: [0.05, 0.22, 0.12, 1], weedHigh: [0.18, 0.45, 0.22, 1],
        sandDark: [0.40, 0.33, 0.22, 1], sandLight: [0.62, 0.53, 0.38, 1], murk: [0.17, 0.2, 0.11, 1],
        params: [9, 12, 0.22, 0.06])
}

/// The registry of themes. The chosen one is stored under "theme".
enum Themes {
    private(set) static var all: [Theme] = builtIns()

    static func register(_ t: Theme) {
        if let i = all.firstIndex(where: { $0.id == t.id }) { all[i] = t } else { all.append(t) }
    }

    static func named(_ id: String?) -> Theme { all.first { $0.id == id } ?? all[0] }

    static var current: Theme {
        get { named(UserDefaults.standard.string(forKey: "theme")) }
        set { UserDefaults.standard.set(newValue.id, forKey: "theme") }
    }

    private static func builtIns() -> [Theme] {
        let specs: [[String: Any]] = [
            ["id": "classic", "name": "Aquário"],
            ["id": "abyss", "name": "Fundo do mar", "visualizer": "constellation", "fauna": ["starfish", "snail", "lanternfish", "whale"], "scenery": ["rock", "chest"],
             "water": ["deep": "#010309", "shallow": "#0a2440", "rays": "#2a4d6e", "raysStrength": 0.08,
                       "caustics": "#4a7fb0", "causticsStrength": 0.03, "surface": "#123a5c", "murk": "#0d1420"],
             "weeds": ["count": 5, "farCount": 8, "far": "#0b1f33", "low": "#06202a", "high": "#1d5a6b"],
             "sand": ["dark": "#1c1d24", "light": "#3a3a44"]],
            ["id": "lagoon", "name": "Lagoa", "visualizer": "surface", "fauna": ["crab", "turtle", "snail", "starfish"], "scenery": ["rock", "shell"],
             "water": ["deep": "#06231f", "shallow": "#2f8c7a", "rays": "#7fd1b0", "raysStrength": 0.3,
                       "caustics": "#bff2d8", "causticsStrength": 0.09, "surface": "#6cc2a8", "murk": "#3a3a1c"],
             "weeds": ["count": 14, "farCount": 16, "far": "#1f4a2a", "low": "#1a4a1c", "high": "#5c9a32"],
             "sand": ["dark": "#7a6a46", "light": "#c9b27a"]],
        ]
        var out: [Theme] = []
        for s in specs { if let t = Theme(json: s, base: out.first) { out.append(t) } }
        return out
    }
}
