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
///                  "size": 0.08, "extent": [0.6, 1], "at": [0.3] or "count": 3, "glowAtNight": true, …} ],
///    "fauna": [ {"id": "frog", "metal": "frog.metal", "function": "draw_frog", "behavior": "perch", "on": "lilypad",
///                "size": 16, "count": [1, 2], "when": "any" | "day" | "night", …} ]}
enum Packs {
    struct Loaded {
        let id: String
        let name: String
        var contents: [String] = []
    }

    private(set) static var loaded: [Loaded] = []
    private(set) static var problems: [String] = []
    /// What the packs registered (to undo it on a reload).
    private(set) static var themeIds: [String] = []
    /// Packs paused by the guard (too heavy for the GPU), by id, with the reason; they aren't read until turned back on.
    static var paused: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "pausedPacks") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "pausedPacks") }
    }
    /// The paused packs that were found on the last load: (id, name, reason).
    private(set) static var pausedFound: [(id: String, name: String, reason: String)] = []

    static func pause(_ id: String, reason: String) { paused[id] = reason }
    /// Why a pack was paused, for people.
    static func reasonText(_ reason: String) -> String {
        if reason == "gpu" { return tr("travou a GPU") }
        return tr("pesado demais para a GPU")
    }
    static func resume(_ id: String) { paused[id] = nil }
    /// A pack being made (linked with `fishbots pack dev`) comes back when its files change: it may be fixed.
    static func resumeLinked() {
        for id in paused.keys {
            let u = folder.appendingPathComponent(id)
            if (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { resume(id) }
        }
    }
    private static var styleIds: [String] = []

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fishbots/packs", isDirectory: true)
    }

    /// Reads every pack. Call before the renderer compiles the shader (fish kinds go into it) and before applying the theme.
    /// Undoes everything the packs registered and reads them again. The app then recompiles the shader and applies the theme.
    static func reload() {
        Themes.unregister(themeIds)
        Generator.unregister(styleIds)
        FishKinds.dropPacks()
        SceneryKinds.all = []
        for k in FaunaKinds.all { FaunaKinds.drop(k.id) }
        load()
    }

    /// A fingerprint of the packs on disk (names, sizes and dates of their files): it changes when one is edited.
    static func signature() -> String {
        let fm = FileManager.default
        var parts: [String] = []
        for dir in ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).sorted(by: { $0.path < $1.path }) {
            for file in ((try? fm.contentsOfDirectory(at: dir.resolvingSymlinksInPath(), includingPropertiesForKeys: nil)) ?? []) {
                guard let a = try? fm.attributesOfItem(atPath: file.path) else { continue }
                parts.append("\(dir.lastPathComponent)/\(file.lastPathComponent):\((a[.size] as? Int) ?? 0):\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)")
            }
        }
        return parts.sorted().joined(separator: "|")
    }

    /// Installs a pack from a .fishbotspack (a zip of the pack's folder): unzipped apart, checked (a pack.json with an
    /// id, only data and Metal files), then put in the packs folder under its id, replacing an older copy.
    /// Returns the pack's id.
    static func install(_ archive: URL) throws -> String {
        struct Failure: LocalizedError { let errorDescription: String? }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("fishbots-pack-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        // before extracting anything: no links, no paths that climb out (../ or absolute), nothing huge
        func zipinfo(_ args: [String]) -> String? {
            let z = Process(), out = Pipe()
            z.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
            z.arguments = args + [archive.path]
            z.standardOutput = out
            z.standardError = Pipe()
            guard (try? z.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            z.waitUntilExit()
            return z.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
        }
        guard let names = zipinfo(["-1"]), let long = zipinfo(["-l"]), let total = zipinfo(["-t"]) else {
            throw Failure(errorDescription: tr("não consegui abrir o arquivo do pacote"))
        }
        for n in names.split(separator: "\n") where n.hasPrefix("/") || n.contains("..") {
            throw Failure(errorDescription: tr("o pacote tem um caminho inválido: %@", String(n)))
        }
        if long.split(separator: "\n").contains(where: { $0.hasPrefix("l") }) {
            throw Failure(errorDescription: tr("o pacote tem links para fora dele"))
        }
        // "N files, X bytes uncompressed, …"
        let bytes = total.components(separatedBy: " bytes uncompressed").first?.split(separator: " ").last.flatMap { Int($0) } ?? 0
        if bytes > 20_000_000 { throw Failure(errorDescription: tr("o pacote é grande demais (%@ MB)", "\(bytes / 1_000_000)")) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", archive.path, tmp.path]
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Failure(errorDescription: tr("não consegui abrir o arquivo do pacote")) }
        // the pack.json at the top, or inside a single folder
        var root = tmp
        if !fm.fileExists(atPath: tmp.appendingPathComponent("pack.json").path),
           let inner = try? fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil).filter({ $0.lastPathComponent != "__MACOSX" }),
           inner.count == 1 { root = inner[0] }
        guard let d = try? Data(contentsOf: root.appendingPathComponent("pack.json")),
              let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let id = json["id"] as? String, id.range(of: #"^[a-z0-9][a-z0-9_-]{0,40}$"#, options: .regularExpression) != nil else {
            throw Failure(errorDescription: tr("o pacote não tem um pack.json com um \"id\" válido"))
        }
        let allowed: Set<String> = ["json", "metal", "md", "txt", "png"]
        for f in (fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])?.allObjects as? [URL]) ?? [] {
            if (try? f.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw Failure(errorDescription: tr("o pacote tem links para fora dele"))
            }
            if f.hasDirectoryPath { continue }
            guard allowed.contains(f.pathExtension.lowercased()) else {
                throw Failure(errorDescription: tr("o pacote tem um arquivo que não é de pacote: %@", f.lastPathComponent))
            }
        }
        let dest = folder.appendingPathComponent(id)
        if let v = try? dest.resourceValues(forKeys: [.isSymbolicLinkKey]), v.isSymbolicLink == true {
            throw Failure(errorDescription: tr("%@ já está instalado como link (um pacote em desenvolvimento)", id))
        }
        try? fm.removeItem(at: dest)
        try fm.copyItem(at: root, to: dest)
        return id
    }

    /// Reads only this folder (the preview and the check of a pack being made).
    static func loadOnly(_ dir: URL) {
        loaded = []; problems = []; themeIds = []; styleIds = []; pausedFound = []
        load(dir)
    }

    static func load() {
        loaded = []
        problems = []
        pausedFound = []
        themeIds = []
        styleIds = []
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
        if let reason = paused[pack.id] {
            pausedFound.append((pack.id, pack.name, reason))
            problems.append(tr("%@: pausado, %@ (Tema → Reativar)", pack.name, reasonText(reason)))
            return
        }

        for t in json["themes"] as? [[String: Any]] ?? [] {
            if let theme = Theme(json: t, base: Themes.named("classic")) {
                Themes.register(theme); themeIds.append(theme.id); pack.contents.append(tr("tema %@", theme.name))
            }
            else { problems.append(tr("%@: tema sem \"id\"", name)) }
        }

        let chords = (json["chords"] as? [String: [NSNumber]] ?? [:]).mapValues { $0.map { $0.intValue % 12 } }
        let progressions = json["progressions"] as? [String: [String]] ?? [:]
        for s in json["styles"] as? [[String: Any]] ?? [] {
            if let style = style(s) {
                Generator.register(style, chords: chords, progressions: progressions)
                styleIds.append(style.id)
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
        for fa in json["fauna"] as? [[String: Any]] ?? [] {
            guard let id = fa["id"] as? String, let file = fa["metal"] as? String, let fn = fa["function"] as? String,
                  fn.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
                  !file.contains("/"), let src = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8),
                  let behavior = FaunaKind.Behavior(rawValue: fa["behavior"] as? String ?? "") else {
                problems.append(tr("%@: criatura incompleta (%@)", name, fa["id"] as? String ?? "?"))
                continue
            }
            guard !Fauna.kinds.contains(where: { $0.id == id }) || FaunaKinds.all.contains(where: { $0.id == id }) else {
                problems.append(tr("%@: a criatura %@ já existe", name, id))
                continue
            }
            func num(_ k: String, _ def: Float) -> Float { (fa[k] as? NSNumber)?.floatValue ?? def }
            func vec(_ k: String) -> [Float]? { (fa[k] as? [NSNumber])?.map(\.floatValue) }
            let cnt = vec("count").flatMap { $0.count == 2 ? Int($0[0])...max(Int($0[0]), Int($0[1])) : nil }
                ?? (fa["count"] as? NSNumber).map { $0.intValue...$0.intValue } ?? 1...1
            let hgt = vec("height").flatMap { $0.count == 2 && $0[0] <= $0[1] ? $0[0]...$0[1] : nil } ?? 0.2...0.7
            let every = vec("every").flatMap { $0.count == 2 && $0[0] <= $0[1] ? Double($0[0])...Double($0[1]) : nil }
                ?? (behavior == .pass ? 900...2700 : 60...180)
            let ext = vec("extent")
            FaunaKinds.register(FaunaKind(
                id: id, name: fa["name"] as? String ?? id, source: src, function: fn, pack: pack.id, behavior: behavior,
                size: max(4, min(400, num("size", 16))), count: max(1, cnt.lowerBound)...min(30, max(1, cnt.upperBound)),
                speed: max(1, min(400, num("speed", 20))), height: max(0.05, hgt.lowerBound)...min(0.95, hgt.upperBound),
                when: FaunaKind.When(rawValue: fa["when"] as? String ?? "any") ?? .any,
                color: Theme.color(fa["color"]).map { SIMD3($0.x, $0.y, $0.z) } ?? [0.6, 0.6, 0.6],
                extent: ext.flatMap { $0.count == 2 ? SIMD2($0[0], $0[1]) : nil } ?? [1, 1],
                every: max(5, every.lowerBound)...max(5, every.upperBound), shy: fa["shy"] as? Bool ?? false,
                on: fa["on"] as? String, front: fa["front"] as? Bool ?? false))
            pack.contents.append(tr("criatura %@", fa["name"] as? String ?? id))
        }
        loaded.append(pack)
    }

    /// The renderer couldn't compile a pack's creature: it's dropped and reported.
    static func faunaFailed(_ kind: FaunaKind, _ error: String) {
        let line = error.split(separator: "\n").first { $0.contains("error") } ?? Substring(error)
        problems.append(tr("%@: a criatura %@ não compilou (%@)", kind.pack, kind.name, String(line.prefix(140))))
        if let i = loaded.firstIndex(where: { $0.id == kind.pack }) { loaded[i].contents.removeAll { $0 == tr("criatura %@", kind.name) } }
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
