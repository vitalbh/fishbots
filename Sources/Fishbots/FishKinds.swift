import Foundation

/// A kind of fish: how it's drawn. Each kind is a Metal expression over (c, phase, glow, col, extra), optionally with
/// its own Metal functions; when the app compiles the shader, the kinds are joined into one `draw_kind` dispatch.
/// See docs/extensions.md.
struct FishKind {
    let id: String
    /// Shown in the fish menu.
    let name: String
    /// Metal functions this kind needs (nil: drawn by functions already in the shader).
    let source: String?
    /// The Metal expression that draws it. In scope: float2 c, float phase, float glow, float4 col, float4 extra
    /// (extra.x: mirror, extra.y: pattern and cut, extra.w: fatness + 2 if asleep).
    let call: String
    /// The pack it came from (nil: built-in).
    var pack: String? = nil
    /// How it swims (a pack fish's "swim"; the built-in kinds swim the usual way).
    var swim = FishSwim()
}

/// A theme's touch on how fish swim (the theme's "swim": {"*": {...}, "<kind>": {...}}): speed and beat multiply
/// the kind's own, the rest replaces it. The quad stays the kind's (it's set when the shader compiles).
struct SwimTweak {
    var speed: Float?, beat: Float?, bob: Float?
    var depth: ClosedRange<Float>?
    var upright: Bool?

    init(json j: [String: Any]) {
        let s = FishSwim(json: j)
        if j["speed"] != nil { speed = s.speed }
        if j["beat"] != nil { beat = s.beat }
        if j["bob"] != nil { bob = s.bob }
        depth = s.depth
        upright = j["upright"] as? Bool
    }

    func applied(to s: FishSwim) -> FishSwim {
        var s = s
        if let speed { s.speed *= speed }
        if let beat { s.beat *= beat }
        if let bob { s.bob = bob }
        if let depth { s.depth = depth }
        if let upright { s.upright = upright }
        return s
    }
}

/// How a kind of fish swims: its drawing's proportion, its pace, where it keeps, and its body language.
struct FishSwim {
    /// The quad, relative to the size (width, height): c goes -1…1 over it.
    var extent: SIMD2<Float> = [1.25, 0.8]
    /// Multiplies its speed (an eel 0.6, a darting fish 1.4).
    var speed: Float = 1
    /// The band it keeps to when it's free to roam (0…1 from the bottom; nil: the usual heights).
    var depth: ClosedRange<Float>? = nil
    /// Doesn't tilt with its course (a seahorse stays upright).
    var upright = false
    /// Bobs up and down as it goes, in body sizes.
    var bob: Float = 0
    /// Multiplies how fast phase (the tail, the body's wave) runs.
    var beat: Float = 1

    init() {}
    /// From a pack fish's "swim" object (anything missing keeps the usual).
    init(json j: [String: Any]?) {
        guard let j else { return }
        func num(_ k: String) -> Float? { (j[k] as? NSNumber)?.floatValue }
        if let e = (j["extent"] as? [NSNumber])?.map(\.floatValue), e.count == 2 {
            extent = [max(0.2, min(4, e[0])), max(0.2, min(4, e[1]))]
        }
        if let v = num("speed") { speed = max(0.1, min(3, v)) }
        if let d = (j["depth"] as? [NSNumber])?.map(\.floatValue), d.count == 2 {
            let lo = max(0.05, min(0.95, min(d[0], d[1]))), hi = max(0.05, min(0.95, max(d[0], d[1])))
            depth = lo...hi
        }
        upright = j["upright"] as? Bool ?? false
        if let v = num("bob") { bob = max(0, min(2, v)) }
        if let v = num("beat") { beat = max(0.1, min(4, v)) }
    }
}

/// The registry of fish kinds. A fish stores its kind as an index into `all` (that's what goes to the shader).
enum FishKinds {
    private(set) static var all: [FishKind] = [
        FishKind(id: "oval", name: "oval", source: nil, call: "draw_fish(c, phase, glow, col, float4(extra.xy, 0.0, extra.w), aux)"),
        FishKind(id: "slender", name: "comprido", source: nil, call: "draw_fish(c, phase, glow, col, float4(extra.xy, 1.0, extra.w), aux)"),
        FishKind(id: "puffer", name: "baiacu", source: nil, call: "draw_fish(c, phase, glow, col, float4(extra.xy, 2.0, extra.w), aux)"),
        FishKind(id: "angelfish", name: "acará-bandeira", source: nil, call: "draw_fish(c, phase, glow, col, float4(extra.xy, 3.0, extra.w), aux)"),
        FishKind(id: "octopus", name: "polvinho", source: nil, call: "draw_octo(c, phase, glow, col)"),
        FishKind(id: "stingray", name: "arraia", source: nil, call: "draw_ray(c, phase, glow, col)"),
        // the music fish (what Spotify or the Music app is playing)
        FishKind(id: "betta", name: "peixe-beta", source: nil, call: "draw_betta(c, phase, glow, col, extra)"),
        // the fauna's lanternfish (dark, with a light on its forehead)
        FishKind(id: "lanternfish", name: "peixe-lanterna", source: nil, call: "draw_fish(c, phase, glow, col, float4(extra.xy, 6.0, extra.w), aux)"),
    ]

    /// Kinds added after the shader was compiled only show up on the next launch.
    static func register(_ k: FishKind) {
        if let i = all.firstIndex(where: { $0.id == k.id }) { all[i] = k } else { all.append(k) }
    }

    /// Drops a kind that came from a pack (its Metal didn't compile).
    static func drop(_ id: String) { all.removeAll { $0.id == id && $0.pack != nil } }
    /// Drops every kind that came from a pack (before the packs are read again).
    static func dropPacks() { all.removeAll { $0.pack != nil } }

    /// The shader with only the built-in kinds and this one, and no pack scenery (to find which pack fish breaks it).
    static func shaderSource(testing k: FishKind) -> String {
        let keep = all, keepScenery = SceneryKinds.all, keepFauna = FaunaKinds.all, keepPres = PackPresences.all, keepBg = PackBackgrounds.all
        all = all.filter { $0.pack == nil } + [k]
        SceneryKinds.all = []; FaunaKinds.all = []; PackPresences.all = []; PackBackgrounds.all = []
        defer { all = keep; SceneryKinds.all = keepScenery; FaunaKinds.all = keepFauna; PackPresences.all = keepPres; PackBackgrounds.all = keepBg }
        return shaderSource()
    }

    /// The shader with the built-in fish and only this pack scenery (to find which one breaks it).
    static func shaderSource(testing k: SceneryKind) -> String {
        let keep = all, keepScenery = SceneryKinds.all, keepFauna = FaunaKinds.all, keepPres = PackPresences.all, keepBg = PackBackgrounds.all
        all = all.filter { $0.pack == nil }
        SceneryKinds.all = [k]; FaunaKinds.all = []; PackPresences.all = []; PackBackgrounds.all = []
        defer { all = keep; SceneryKinds.all = keepScenery; FaunaKinds.all = keepFauna; PackPresences.all = keepPres; PackBackgrounds.all = keepBg }
        return shaderSource()
    }

    /// The shader with the built-in fish and only this pack background (to find which one breaks it).
    static func shaderSource(testing k: PackBackground) -> String {
        let keep = all, keepScenery = SceneryKinds.all, keepFauna = FaunaKinds.all, keepPres = PackPresences.all, keepBg = PackBackgrounds.all
        all = all.filter { $0.pack == nil }
        SceneryKinds.all = []; FaunaKinds.all = []; PackPresences.all = []; PackBackgrounds.all = [k]
        defer { all = keep; SceneryKinds.all = keepScenery; FaunaKinds.all = keepFauna; PackPresences.all = keepPres; PackBackgrounds.all = keepBg }
        return shaderSource()
    }

    /// The shader with the built-in fish and only this pack presence (to find which one breaks it).
    static func shaderSource(testing k: PackPresence) -> String {
        let keep = all, keepScenery = SceneryKinds.all, keepFauna = FaunaKinds.all, keepPres = PackPresences.all, keepBg = PackBackgrounds.all
        all = all.filter { $0.pack == nil }
        SceneryKinds.all = []; FaunaKinds.all = []; PackPresences.all = [k]; PackBackgrounds.all = []
        defer { all = keep; SceneryKinds.all = keepScenery; FaunaKinds.all = keepFauna; PackPresences.all = keepPres; PackBackgrounds.all = keepBg }
        return shaderSource()
    }

    /// The shader with the built-in fish and only this pack creature (to find which one breaks it).
    static func shaderSource(testing k: FaunaKind) -> String {
        let keep = all, keepScenery = SceneryKinds.all, keepFauna = FaunaKinds.all, keepPres = PackPresences.all, keepBg = PackBackgrounds.all
        all = all.filter { $0.pack == nil }
        SceneryKinds.all = []; FaunaKinds.all = [k]; PackPresences.all = []; PackBackgrounds.all = []
        defer { all = keep; SceneryKinds.all = keepScenery; FaunaKinds.all = keepFauna; PackPresences.all = keepPres; PackBackgrounds.all = keepBg }
        return shaderSource()
    }

    static func index(of id: String) -> Int { all.firstIndex { $0.id == id } ?? 0 }

    /// Dressing by the theme (Preferences): its "looks" may draw a kind as another ("oval": "koi"). A kind picked by
    /// hand in the fish menu stays as picked.
    static var dressByTheme: Bool { UserDefaults.standard.object(forKey: "dressByTheme") as? Bool ?? true }
    static func dressed(_ id: String, picked: Bool) -> String {
        guard !picked, dressByTheme, let look = Themes.current.looks[id], all.contains(where: { $0.id == look }) else { return id }
        return look
    }

    static func id(at i: Int) -> String { all.indices.contains(i) ? all[i].id : all[0].id }

    /// The kind chosen for an agent in Preferences (all its fish, unless their project has one picked in the fish menu).
    /// A kind that's gone (its pack left) is ignored.
    static func agentKind(_ source: String) -> String? {
        guard let id = (UserDefaults.standard.dictionary(forKey: "agentFishKinds") as? [String: String])?[source],
              all.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    static func setAgentKind(_ id: String?, for source: String) {
        var d = UserDefaults.standard.dictionary(forKey: "agentFishKinds") as? [String: String] ?? [:]
        d[source] = id
        UserDefaults.standard.set(d, forKey: "agentFishKinds")
    }

    /// The kind chosen for a project in the fish menu (overrides the session provider's).
    static func override(for projectKey: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: "fishKinds") as? [String: String])?[projectKey]
    }

    static func setOverride(_ id: String?, for projectKey: String) {
        var d = UserDefaults.standard.dictionary(forKey: "fishKinds") as? [String: String] ?? [:]
        d[projectKey] = id
        UserDefaults.standard.set(d, forKey: "fishKinds")
    }

    /// The full shader: the base source with the kinds' functions and the `draw_kind` dispatch in place of the marker.
    static func shaderSource() -> String {
        var once = Set<String>()
        var gen = all.compactMap(\.source).filter { once.insert($0).inserted }.joined(separator: "\n\n")
        gen += "\n\nfloat4 draw_kind(int k, float2 c, float phase, float glow, float4 col, float4 extra, float4 aux) {\n    switch (k) {\n"
        for (i, k) in all.enumerated() { gen += "    case \(i): return \(k.call);\n" }
        gen += "    default: return \(all[0].call);\n    }\n}\n"
        // each kind's quad (a pack fish's "swim": "extent")
        gen += "\nfloat2 fish_extent(int k) {\n    switch (k) {\n"
        for (i, k) in all.enumerated() where k.swim.extent != FishSwim().extent {
            gen += "    case \(i): return float2(\(k.swim.extent.x), \(k.swim.extent.y));\n"
        }
        gen += "    default: return float2(1.25, 0.8);\n    }\n}\n"
        // the packs' scenery: their functions and a dispatch on their index (extra.z)
        // (a file shared by several pieces, or by a fish, goes in once)
        var seen = Set(all.compactMap(\.source))
        gen += SceneryKinds.all.map(\.source).filter { seen.insert($0).inserted }.joined(separator: "\n\n")
        gen += "\n\nfloat4 draw_scenery_pack(int k, float2 c, float t, float glow, float4 col, float4 extra) {\n    switch (k) {\n"
        for (i, k) in SceneryKinds.all.enumerated() { gen += "    case \(i): return \(k.function)(c, t, glow, col, extra);\n" }
        gen += "    default: return float4(0.0);\n    }\n}\n"
        // the packs' theme backgrounds (the theme's uniforms carry the index + 1)
        gen += "\n" + PackBackgrounds.all.map(\.source).filter { seen.insert($0).inserted }.joined(separator: "\n\n")
        gen += "\n\nfloat4 draw_background_pack(int k, float2 uv, float t, float light, float2 gaze, float3 water, float4 extra) {\n    switch (k) {\n"
        for (i, k) in PackBackgrounds.all.enumerated() { gen += "    case \(i): return \(k.function)(uv, t, light, gaze, water, extra);\n" }
        gen += "    default: return float4(0.0);\n    }\n}\n"
        // the packs' presences (extra.z: the index)
        gen += "\n" + PackPresences.all.map(\.source).filter { seen.insert($0).inserted }.joined(separator: "\n\n")
        gen += "\n\nfloat4 draw_presence_pack(int k, float2 c, float phase, float glow, float4 col, float4 extra) {\n    switch (k) {\n"
        for (i, k) in PackPresences.all.enumerated() { gen += "    case \(i): return \(k.function)(c, phase, glow, col, extra);\n" }
        gen += "    default: return float4(0.0);\n    }\n}\n"
        // the packs' creatures, the same way (extra.z: the index)
        gen += "\n" + FaunaKinds.all.map(\.source).filter { seen.insert($0).inserted }.joined(separator: "\n\n")
        gen += "\n\nfloat4 draw_fauna_pack(int k, float2 c, float phase, float glow, float4 col, float4 extra) {\n    switch (k) {\n"
        for (i, k) in FaunaKinds.all.enumerated() { gen += "    case \(i): return \(k.function)(c, phase, glow, col, extra);\n" }
        gen += "    default: return float4(0.0);\n    }\n}\n"
        // the lanternfish's quad is bigger, so its light fades out before the edge instead of ending in a straight line
        return "#define LANTERN_KIND \(index(of: "lanternfish"))\n#define LANTERN_ROOM 1.6\n"
            + shaderBase.replacingOccurrences(of: "// @fish-kinds", with: gen)
    }
}

/// A piece of scenery that comes from a pack: drawn by its own Metal function
/// `float4 draw_<id>(float2 c, float t, float glow, float4 col, float4 extra)`, placed by the app. In the function:
/// c is -1…1 over the quad (y up), t the time in seconds, glow how much it glows (at night, if it asks to), col its
/// color already lit by the hour, extra.y a seed (0…1, different for each copy), extra.w how dark the night is (0…1).
/// It returns premultiplied color and alpha. See docs/extensions.md.
struct SceneryKind {
    enum Anchor: String { case sand, surface, float }
    let id: String
    let name: String
    let source: String
    let function: String
    let pack: String
    let anchor: Anchor
    /// The quad, relative to the size (width, height).
    let extent: SIMD2<Float>
    /// Its size, as a fraction of the tank's height.
    let size: Float
    let color: SIMD3<Float>
    /// Where the copies sit (0…1 from the left).
    let at: [Float]
    /// Height in the water (0…1 from the bottom), for `float`.
    let height: Float
    /// Glows at night (a lantern, a lamp): `glow` goes up as the light goes down, and it feeds the bloom.
    let glowAtNight: Bool
    /// Drifts slowly sideways (things floating at the surface).
    let drift: Bool
    /// The fish swim around it (default: on the sand and in the water yes, at the surface no).
    let solid: Bool
    /// On the sand: how much of the quad's height sits below the sand line (default 0.05), so a wide piece doesn't
    /// float where the sand dips under it.
    var bury: Float = 0.05
}

/// A kind of presence that comes from a pack (plugins use it like the built-in ones: "kind": "<id>"), drawn by its own
/// Metal function `float4 draw_<id>(float2 c, float phase, float glow, float4 col, float4 extra)`, moved by the app like
/// the built-in presences. In the function: extra.y is its value (0…1, for meters), extra.w its state
/// (0 idle, 1 busy, 2 waiting, 3 ok, 4 alert, 5 error, 6 done, 7 born). A sprite of kind 37 carries its index in extra.z.
struct PackPresence {
    let id: String
    let source: String
    let function: String
    let pack: String
}

/// A pack theme's own background, drawn over the water and behind the seaweed by
/// `float4 draw_<id>(float2 uv, float t, float light, float2 gaze, float3 water, float4 extra)`: uv 0…1 over the
/// window (y up), t seconds, light the daylight (0…1), gaze the parallax (-1…1, move far things a little with it),
/// water the water's color there (mix toward it for haze), extra.x the aspect (width / height), extra.y moonlight
/// (0…1), extra.z the sand line's height at this x. Returns premultiplied rgba.
struct PackBackground {
    let id: String       // the theme's id
    let source: String
    let function: String
    let pack: String
}

enum PackBackgrounds {
    static var all: [PackBackground] = []
    /// One that didn't compile: it stays in its place (the themes keep their index) and draws nothing.
    static func blank(_ id: String) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i] = PackBackground(id: id, source: "", function: "fishbots_no_background", pack: all[i].pack)
    }
}

enum PackPresences {
    static var all: [PackPresence] = []
    static func index(of id: String) -> Int? { all.firstIndex { $0.id == id } }
    static func stateCode(_ s: State) -> Float {
        switch s { case .idle: 0; case .busy: 1; case .waiting: 2; case .ok: 3; case .alert: 4; case .error: 5; case .done: 6; case .born: 7 }
    }
}

/// The registry of pack scenery. A sprite of kind 35 carries its index in extra.z.
enum SceneryKinds {
    static var all: [SceneryKind] = []

    static func register(_ k: SceneryKind) {
        if let i = all.firstIndex(where: { $0.id == k.id }) { all[i] = k } else { all.append(k) }
    }
    static func drop(_ id: String) { all.removeAll { $0.id == id } }
    static func index(of id: String) -> Int? { all.firstIndex { $0.id == id } }
}
