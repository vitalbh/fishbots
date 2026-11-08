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
    /// x: the pack background's index + 1 (0: none), y: 1 when it replaces the distant reef.
    var pack: SIMD4<Float> = .zero
}

/// A scene: water, light, seaweed and sand, plus optional defaults for the visualizer, the music and the fauna.
/// Built-ins are written in the same JSON format that packs will use (docs/extensions.md).
struct Theme {
    let id: String
    let name: String               // shown in the menu (Portuguese, translated by tr)
    /// Names in other languages, from a pack: {"en": "Coral reef"}.
    var names: [String: String] = [:]
    var displayName: String { names[L10n.isPortuguese ? "pt" : "en"] ?? tr(name) }
    /// One sentence about it ("description", "descriptions": {"en": …}); built-in ones go through tr().
    var description = ""
    var descriptions: [String: String] = [:]
    var displayDescription: String { descriptions[L10n.resolved] ?? (description.isEmpty ? "" : tr(description)) }
    var uniforms: ThemeUniforms
    /// The visualizer used when the choice is "auto" (otherwise it follows the music style).
    var visualizer: String?
    /// The music style chosen more often in this scene.
    var music: String?
    /// Which creatures live here (nil: all of them).
    var fauna: [String]?
    /// Which scenery sits on the sand: "rock", "shell", "chest" (nil: all of it).
    var scenery: [String]?
    /// A pack's drawing for a built-in piece ("chest": "shrine"): same place and behavior, another look.
    var looks: [String: String] = [:]
    /// The theme's light through the day (nil: the usual one). See `Sky`.
    var sky: Sky?
    /// The decorative schools (nil: the usual neons, tetras and silversides). At most 3: the first swims in the middle,
    /// the second up high, the third low and far.
    var schools: [School]?
    /// The jellyfish that drifts around (false: none here).
    var jellyfish = true
    /// The blurred seaweed tufts up front, in the corners: their color (nil: none here, "foreground": false).
    var foreground: SIMD3<Float>? = [0.02, 0.065, 0.065]
    /// The seaweed's shapes ("weeds": {"shapes": ["reed", "blade"]}): blade, kelp, leafy, reed, ribbon (nil: the usual mix).
    var weedShapes: [Int]?
    var weedCount: Int { Int(uniforms.params.x) }

    /// A color from JSON: "#rrggbb" or [r, g, b] (0…1).
    static func color(_ v: Any?) -> SIMD4<Float>? {
        if let a = v as? [NSNumber], a.count >= 3 { return [a[0].floatValue, a[1].floatValue, a[2].floatValue, 1] }
        if let s = v as? String, s.hasPrefix("#"), s.count == 7, let n = UInt32(s.dropFirst(), radix: 16) {
            return [Float((n >> 16) & 255) / 255, Float((n >> 8) & 255) / 255, Float(n & 255) / 255, 1]
        }
        return nil
    }

    /// Reads a theme from JSON. Colors are "#rrggbb" or [r, g, b] (0…1). Missing values come from `base`.
    init?(json: [String: Any], base: Theme? = nil) {
        guard let id = json["id"] as? String, !id.isEmpty else { return nil }
        self.id = id
        name = json["name"] as? String ?? id
        names = json["names"] as? [String: String] ?? [:]
        var u = base?.uniforms ?? Theme.classicUniforms
        func color(_ v: Any?) -> SIMD4<Float>? { Theme.color(v) }
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
        looks = json["looks"] as? [String: String] ?? [:]
        description = json["description"] as? String ?? ""
        descriptions = json["descriptions"] as? [String: String] ?? [:]
        if let s = json["sky"] as? [String: Any] { sky = Sky(json: s) }
        if let list = json["schools"] as? [[String: Any]] { schools = list.prefix(3).map(School.init(json:)) }
        jellyfish = json["jellyfish"] as? Bool ?? true
        if (json["foreground"] as? Bool) == false { foreground = nil }
        else if let c = Theme.color(json["foreground"]) { foreground = [c.x, c.y, c.z] }
        let shapeNames = ["blade": 0, "kelp": 1, "leafy": 2, "reed": 3, "ribbon": 4]
        if let s = (json["weeds"] as? [String: Any])?["shapes"] as? [String] {
            let ids = s.compactMap { shapeNames[$0] }
            weedShapes = ids.isEmpty ? nil : ids
        }
    }

    /// The original look.
    static let classicUniforms = ThemeUniforms(
        deep: [0.012, 0.05, 0.11, 1], shallow: [0.05, 0.30, 0.40, 1], rays: [0.25, 0.45, 0.45, 1],
        caustics: [0.5, 0.75, 0.75, 1], surface: [0.35, 0.6, 0.65, 1], farWeed: [0.08, 0.2, 0.14, 1],
        weedLow: [0.05, 0.22, 0.12, 1], weedHigh: [0.18, 0.45, 0.22, 1],
        sandDark: [0.40, 0.33, 0.22, 1], sandLight: [0.62, 0.53, 0.38, 1], murk: [0.17, 0.2, 0.11, 1],
        params: [12, 12, 0.22, 0.06])
}

/// The registry of themes. The chosen one is stored under "theme".
enum Themes {
    private(set) static var all: [Theme] = builtIns()

    static func register(_ t: Theme) {
        if let i = all.firstIndex(where: { $0.id == t.id }) { all[i] = t } else { all.append(t) }
    }
    static func unregister(_ ids: [String]) { all.removeAll { ids.contains($0.id) && $0.id != "classic" } }

    static func named(_ id: String?) -> Theme { all.first { $0.id == id } ?? all[0] }

    static var current: Theme {
        get { named(UserDefaults.standard.string(forKey: "theme")) }
        set { UserDefaults.standard.set(newValue.id, forKey: "theme") }
    }

    private static func builtIns() -> [Theme] {
        let specs: [[String: Any]] = [
            ["id": "classic", "name": "Aquário", "description": "O aquário de sempre: água azul, algas verdes, pedras, a ostra e o baú."],
            ["id": "abyss", "name": "Fundo do mar", "description": "Quase escuro, poucas plantas, peixes-lanterna à noite e a baleia passando ao longe.", "visualizer": "constellation", "fauna": ["starfish", "snail", "lanternfish", "whale"], "scenery": ["rock", "chest"],
             "water": ["deep": "#010309", "shallow": "#0a2440", "rays": "#2a4d6e", "raysStrength": 0.08,
                       "caustics": "#4a7fb0", "causticsStrength": 0.03, "surface": "#123a5c", "murk": "#0d1420"],
             "weeds": ["count": 5, "farCount": 8, "far": "#0b1f33", "low": "#06202a", "high": "#1d5a6b"],
             "sand": ["dark": "#1c1d24", "light": "#3a3a44"]],
            ["id": "lagoon", "name": "Lagoa", "description": "Água verde e clara, muitas algas, caranguejos, a tartaruga e a superfície viva.", "visualizer": "surface", "fauna": ["crab", "turtle", "snail", "starfish"], "scenery": ["rock", "shell"],
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

/// A theme's light through the day: the color the hour casts over everything (a multiplier: `[r, g, b]` may go over 1
/// to warm or brighten; "#rrggbb" stays within 1) at night, dawn, day, the golden hour and dusk; how bright the
/// water is at night and by day; and how strong the sun and the moon are through the surface.
///
///   "sky": {"night": [0.6, 0.72, 1.1], "dawn": [1.0, 0.92, 0.95], "day": [0.92, 0.97, 1.08],
///           "golden": [1.05, 0.95, 0.9], "dusk": [0.8, 0.8, 1.05], "light": [0.5, 0.9], "sun": 0.6, "moon": 1.3}
struct Sky {
    var night: SIMD3<Float> = [0.72, 0.8, 1.05]
    var dawn: SIMD3<Float> = [1.12, 0.9, 0.78]
    var day: SIMD3<Float> = [1, 1, 1]
    var golden: SIMD3<Float> = [1.22, 0.98, 0.7]
    var dusk: SIMD3<Float> = [0.98, 0.8, 0.96]
    /// The water's brightness at night and at midday.
    var light: ClosedRange<Float> = 0.62...1.0
    var sun: Float = 1
    var moon: Float = 1

    init() {}
    init(json s: [String: Any]) {
        func c(_ k: String) -> SIMD3<Float>? { Theme.color(s[k]).map { SIMD3(max(0, min(2, $0.x)), max(0, min(2, $0.y)), max(0, min(2, $0.z))) } }
        if let v = c("night") { night = v }
        if let v = c("dawn") { dawn = v }
        if let v = c("day") { day = v }
        if let v = c("golden") { golden = v }
        if let v = c("dusk") { dusk = v }
        if let a = s["light"] as? [NSNumber], a.count == 2 {
            let lo = max(0.1, min(1.2, a[0].floatValue)), hi = max(lo, min(1.3, a[1].floatValue))
            light = lo...hi
        }
        if let v = (s["sun"] as? NSNumber)?.floatValue { sun = max(0, min(3, v)) }
        if let v = (s["moon"] as? NSNumber)?.floatValue { moon = max(0, min(3, v)) }
    }
}

/// A decorative school: how many, how big, their color, the fish kind (a built-in one or a pack's), the pattern and
/// how far back they swim (0 near … 1 far).
///
///   "schools": [{"color": "#c8d4dc", "kind": "slender", "count": 12, "size": [7, 9], "pattern": 0, "depth": [0.3, 0.7]}]
struct School {
    var count = 8
    var size: ClosedRange<Float> = 8...10
    var color: SIMD3<Float> = [0.6, 0.7, 0.8]
    var pattern = 0
    var depth: ClosedRange<Float> = 0.2...0.6
    var kind = "oval"

    init(count: Int, size: ClosedRange<Float>, color: SIMD3<Float>, pattern: Int, depth: ClosedRange<Float>, kind: String) {
        self.count = count; self.size = size; self.color = color; self.pattern = pattern; self.depth = depth; self.kind = kind
    }
    init(json s: [String: Any]) {
        if let n = (s["count"] as? NSNumber)?.intValue { count = max(1, min(16, n)) }
        if let a = s["size"] as? [NSNumber], a.count == 2 { let lo = max(4, a[0].floatValue); size = lo...max(lo, min(30, a[1].floatValue)) }
        if let c = Theme.color(s["color"]) { color = [c.x, c.y, c.z] }
        if let p = (s["pattern"] as? NSNumber)?.intValue { pattern = max(0, min(7, p)) }
        if let a = s["depth"] as? [NSNumber], a.count == 2 { let lo = max(0, min(0.9, a[0].floatValue)); depth = lo...max(lo, min(0.9, a[1].floatValue)) }
        if let k = s["kind"] as? String { kind = k }
    }

    /// The usual ones: blue neons in the middle, orange tetras up high, silversides deep in the back.
    static let usual: [School] = [
        School(count: 10, size: 9.5...11, color: [0.35, 0.75, 1.0], pattern: 1, depth: 0.2...0.6, kind: "oval"),
        School(count: 8, size: 8...9.5, color: [1.0, 0.62, 0.25], pattern: 3, depth: 0.25...0.5, kind: "oval"),
        School(count: 6, size: 14...17, color: [0.72, 0.8, 0.88], pattern: 0, depth: 0.6...0.8, kind: "slender"),
    ]
}
