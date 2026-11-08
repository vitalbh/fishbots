import Foundation

/// Packs: folders in ~/Library/Application Support/Fishbots/packs/<id>/ with a pack.json that adds themes, music styles
/// and fish kinds (with their Metal drawing). Data and GPU code only: a pack can't run anything on the Mac.
/// A broken pack (or a part of one) is skipped and reported in the Tema menu. See docs/extensions.md and
/// packs/examples/ in the repository.
///
///   {"id": "coral", "name": "Recife de coral",
///    "themes": [ {theme JSON, see Theme.init(json:)} ],
///    "styles": [ {"id", "name", "bpm": [lo, hi], "progressions": ["Dreamy"], "scale": "major" | "penta" | [0, 2, …],
///                 "lead": ["flute"], "accomp": "arpeggio" | "lofi" | "bossa", "accompTimbre": ["soft"], …} ],
///    "chords": {"Dm9": [2, 5, 9, 0, 4]}, "progressions": {"Lagoon": ["Cmaj7", "Dm9"]},
///    "fish": [ {"id": "clownfish", "name": "palhaço", "metal": "clownfish.metal", "function": "draw_clownfish"} ],
///    "scenery": [ {"id": "lantern", "metal": "lantern.metal", "function": "draw_lantern", "anchor": "sand" | "surface" | "float",
///                  "size": 0.08, "extent": [0.6, 1], "at": [0.3] or "count": 3, "glowAtNight": true, …} ]}
enum Packs {
    struct Loaded {
        let id: String
        let name: String
        var contents: [String] = []
    }

    private(set) static var loaded: [Loaded] = []
    private(set) static var problems: [String] = []

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fishbots/packs", isDirectory: true)
    }

    /// Reads every pack. Call before the renderer compiles the shader (fish kinds go into it) and before applying the theme.
    static func load() {
        loaded = []
        problems = []
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let dirs = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { var isDir: ObjCBool = false; return fm.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue }   // follows links
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for dir in dirs { load(dir) }
    }

    private static func load(_ dir: URL) {
        let name = dir.lastPathComponent
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("pack.json")),
              let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
            problems.append(tr("%@: pack.json ausente ou inválido", name))
            return
        }
        var pack = Loaded(id: json["id"] as? String ?? name, name: json["name"] as? String ?? name)

        for t in json["themes"] as? [[String: Any]] ?? [] {
            if let theme = Theme(json: t, base: Themes.named("classic")) { Themes.register(theme); pack.contents.append(tr("tema %@", theme.name)) }
            else { problems.append(tr("%@: tema sem \"id\"", name)) }
        }

        let chords = (json["chords"] as? [String: [NSNumber]] ?? [:]).mapValues { $0.map { $0.intValue % 12 } }
        let progressions = json["progressions"] as? [String: [String]] ?? [:]
        for s in json["styles"] as? [[String: Any]] ?? [] {
            if let style = style(s) {
                Generator.register(style, chords: chords, progressions: progressions)
                if let v = s["visualizer"] as? String { Visualizers.setDefault(v, forStyle: style.id) }
                pack.contents.append(tr("estilo %@", style.name))
            } else {
                problems.append(tr("%@: estilo incompleto (%@)", name, s["id"] as? String ?? "?"))
            }
        }

        for f in json["fish"] as? [[String: Any]] ?? [] {
            guard let id = f["id"] as? String, let file = f["metal"] as? String, let fn = f["function"] as? String,
                  fn.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
                  !file.contains("/"), let src = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) else {
                problems.append(tr("%@: peixe incompleto (%@)", name, f["id"] as? String ?? "?"))
                continue
            }
            FishKinds.register(FishKind(id: id, name: f["name"] as? String ?? id, source: src, call: "\(fn)(c, phase, glow, col, extra)",
                                        pack: pack.id))
            pack.contents.append(tr("peixe %@", f["name"] as? String ?? id))
        }
        for sc in json["scenery"] as? [[String: Any]] ?? [] {
            guard let id = sc["id"] as? String, let file = sc["metal"] as? String, let fn = sc["function"] as? String,
                  fn.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
                  !file.contains("/"), let src = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) else {
                problems.append(tr("%@: cenário incompleto (%@)", name, sc["id"] as? String ?? "?"))
                continue
            }
            func num(_ k: String, _ def: Float) -> Float { (sc[k] as? NSNumber)?.floatValue ?? def }
            func vec(_ k: String) -> [Float]? { (sc[k] as? [NSNumber])?.map(\.floatValue) }
            let anchor = SceneryKind.Anchor(rawValue: sc["anchor"] as? String ?? "sand") ?? .sand
            // where the copies go: "at" (one place or a list), or "count" spread out from the id
            var at = vec("at") ?? (sc["at"] as? NSNumber).map { [$0.floatValue] } ?? []
            if at.isEmpty {
                let n = max(1, min(12, Int(num("count", 1))))
                var h = UInt64(5381)
                for b in id.utf8 { h = h &* 33 &+ UInt64(b) }
                at = (0..<n).map { i in 0.08 + 0.84 * ((Float(i) + Float((h >> (UInt64(i) % 40)) % 100) / 100) / Float(n)) }
            }
            let ext = vec("extent")
            let col = Theme.color(sc["color"]).map { SIMD3($0.x, $0.y, $0.z) } ?? [0.6, 0.6, 0.6]
            SceneryKinds.register(SceneryKind(
                id: id, name: sc["name"] as? String ?? id, source: src, function: fn, pack: pack.id, anchor: anchor,
                extent: ext.flatMap { $0.count == 2 ? SIMD2($0[0], $0[1]) : nil } ?? [1, 1],
                size: max(0.005, min(0.5, num("size", 0.06))), color: col, at: at.map { max(0, min(1, $0)) },
                height: max(0, min(1, num("height", 0.5))), glowAtNight: sc["glowAtNight"] as? Bool ?? false,
                drift: sc["drift"] as? Bool ?? (anchor == .surface), solid: sc["solid"] as? Bool ?? (anchor != .surface)))
            pack.contents.append(tr("cenário %@", sc["name"] as? String ?? id))
        }
        loaded.append(pack)
    }

    /// The renderer couldn't compile a pack's scenery: it's dropped and reported.
    static func sceneryFailed(_ kind: SceneryKind, _ error: String) {
        let line = error.split(separator: "\n").first { $0.contains("error") } ?? Substring(error)
        problems.append(tr("%@: o cenário %@ não compilou (%@)", kind.pack, kind.name, String(line.prefix(140))))
        if let i = loaded.firstIndex(where: { $0.id == kind.pack }) { loaded[i].contents.removeAll { $0 == tr("cenário %@", kind.name) } }
    }

    /// The renderer couldn't compile a pack's fish: it's dropped and reported.
    static func fishFailed(_ kind: FishKind, _ error: String) {
        let line = error.split(separator: "\n").first { $0.contains("error") } ?? Substring(error)
        problems.append(tr("%@: o peixe %@ não compilou (%@)", kind.pack ?? "?", kind.name, String(line.prefix(140))))
        if let i = loaded.firstIndex(where: { $0.id == kind.pack }) { loaded[i].contents.removeAll { $0 == tr("peixe %@", kind.name) } }
    }

    private static let timbres: [String: Timbre] = [
        "pluck": .pluck, "bell": .bell, "pad": .pad, "bass": .bass, "glass": .glass, "bubble": .bubble,
        "soft": .soft, "rhodes": .rhodes, "flute": .flute, "kalimba": .kalimba, "tap": .tap,
    ]

    /// A music style from JSON (missing values get the calm defaults).
    private static func style(_ s: [String: Any]) -> Style? {
        guard let id = s["id"] as? String, let progs = s["progressions"] as? [String], !progs.isEmpty else { return nil }
        func range(_ k: String, _ def: ClosedRange<Double>) -> ClosedRange<Double> {
            guard let a = s[k] as? [NSNumber], a.count == 2, a[0].doubleValue <= a[1].doubleValue else { return def }
            return a[0].doubleValue...a[1].doubleValue
        }
        func timbreList(_ k: String, _ def: [Timbre]) -> [Timbre] {
            let l = (s[k] as? [String] ?? []).compactMap { timbres[$0] }
            return l.isEmpty ? def : l
        }
        let scale: [Int]
        switch s["scale"] {
        case let a as [NSNumber] where !a.isEmpty: scale = a.map { $0.intValue % 12 }
        case let n as String where n == "penta": scale = Generator.penta
        default: scale = Generator.major
        }
        let accomp: Accomp = ["lofi": .lofi, "bossa": .bossa][s["accomp"] as? String ?? ""] ?? .arpeggio
        let notes = range("notesPerBar", 2...3)
        let keys = (s["keys"] as? [NSNumber])?.map { $0.intValue % 12 } ?? [0, 2, 5, 7]
        return Style(id: id, name: s["name"] as? String ?? id, bpm: range("bpm", 56...72), progs: progs, scale: scale,
                     barsPerChord: max(1, (s["barsPerChord"] as? NSNumber)?.intValue ?? 2),
                     lead: timbreList("lead", [.soft]), accomp: accomp, accompTimbre: timbreList("accompTimbre", [.soft]),
                     notesPerBar: Int(notes.lowerBound)...Int(notes.upperBound), swing: range("swing", 0...0.1),
                     keys: keys.isEmpty ? [0] : keys, energy: min(1, max(0, (s["energy"] as? NSNumber)?.doubleValue ?? 0.3)),
                     rest: min(0.9, max(0, (s["rest"] as? NSNumber)?.doubleValue ?? 0.35)))
    }
}
