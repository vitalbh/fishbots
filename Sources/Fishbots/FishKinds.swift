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

    /// The shader with only the built-in kinds and this one (to find which pack fish breaks it).
    static func shaderSource(testing k: FishKind) -> String {
        let keep = all
        all = all.filter { $0.pack == nil } + [k]
        defer { all = keep }
        return shaderSource()
    }

    static func index(of id: String) -> Int { all.firstIndex { $0.id == id } ?? 0 }

    static func id(at i: Int) -> String { all.indices.contains(i) ? all[i].id : all[0].id }

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
        var gen = all.compactMap(\.source).joined(separator: "\n\n")
        gen += "\n\nfloat4 draw_kind(int k, float2 c, float phase, float glow, float4 col, float4 extra, float4 aux) {\n    switch (k) {\n"
        for (i, k) in all.enumerated() { gen += "    case \(i): return \(k.call);\n" }
        gen += "    default: return \(all[0].call);\n    }\n}\n"
        // the lanternfish's quad is bigger, so its light fades out before the edge instead of ending in a straight line
        return "#define LANTERN_KIND \(index(of: "lanternfish"))\n#define LANTERN_ROOM 1.6\n"
            + shaderBase.replacingOccurrences(of: "// @fish-kinds", with: gen)
    }
}
