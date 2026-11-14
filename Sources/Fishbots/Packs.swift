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
        /// From pack.json: "version", "author", "license", "description", "homepage", "minApp".
        var meta: [String: String] = [:]
        var version: String { meta["version"] ?? "" }
    }

    /// This app's version (packs can ask for a minimum with "minApp").
    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1" }

    /// Compares "1.2.3"-style versions: is a older than b?
    static func older(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q }
        }
        return false
    }

    /// The catalog's metadata, all required for a pack in the community catalog (`--check --catalog`).
    static let catalogFields = ["version", "author", "license", "description"]

    private(set) static var loaded: [Loaded] = []
    private(set) static var problems: [String] = []
    /// What the packs registered (to undo it on a reload).
    private(set) static var themeIds: [String] = []
    /// Which pack each pack theme came from (theme id → pack id).
    private(set) static var themePack: [String: String] = [:]
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
        folderOverride ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fishbots/packs", isDirectory: true)
    }
    /// Another packs folder (the screen saver keeps a copy of the app's, which it can't read: GET /packs/files).
    static var folderOverride: URL?

    /// Every pack's text files (pack.json and the Metal drawings), for the screen saver to copy:
    /// {"signature": …, "packs": {"<folder>": {"<file>": "<text>"}}}. Recorded sounds and pictures stay out (it's silent).
    /// `sounds`: the packs' sound files too (base64), for a mirror that plays them (the iPhone; the screen saver is silent).
    static func filesJSON(sounds: Bool = false) -> Data {
        let fm = FileManager.default
        var packs: [String: [String: String]] = [:]
        var audio: [String: [String: String]] = [:]
        for dir in ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []) {
            var files: [String: String] = [:]
            var sound: [String: String] = [:]
            for f in ((try? fm.contentsOfDirectory(at: dir.resolvingSymlinksInPath(), includingPropertiesForKeys: nil)) ?? []) {
                let ext = f.pathExtension.lowercased()
                if ["json", "metal"].contains(ext), let t = try? String(contentsOf: f, encoding: .utf8) { files[f.lastPathComponent] = t }
                if sounds, soundExtensions.contains(ext), let d = try? Data(contentsOf: f), d.count < 5_000_000 {
                    sound[f.lastPathComponent] = d.base64EncodedString()
                }
            }
            if files["pack.json"] != nil {
                packs[dir.lastPathComponent] = files
                if !sound.isEmpty { audio[dir.lastPathComponent] = sound }
            }
        }
        var obj: [String: Any] = ["signature": signature(), "packs": packs]
        if sounds { obj["sounds"] = audio }
        return (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
    }

    static let soundExtensions = ["wav", "aif", "aiff", "caf"]

    /// A mirror (the screen saver, the iPhone): writes the app's packs (from filesJSON) into its own folder and reads them.
    /// Folder and file names come from the app, checked anyway (no paths, only pack files).
    @discardableResult
    static func mirror(_ data: Data, into dir: URL) -> Bool {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let packs = obj["packs"] as? [String: [String: String]] else { return false }
        let fm = FileManager.default
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        func safe(_ n: String) -> Bool { !n.isEmpty && !n.contains("/") && !n.contains("..") && !n.hasPrefix(".") }
        for (name, files) in packs where safe(name) {
            let pd = dir.appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: pd, withIntermediateDirectories: true)
            for (file, text) in files where safe(file) && ["json", "metal"].contains((file as NSString).pathExtension.lowercased()) {
                try? text.write(to: pd.appendingPathComponent(file), atomically: true, encoding: .utf8)
            }
            for (file, b64) in (obj["sounds"] as? [String: [String: String]])?[name] ?? [:]
            where safe(file) && soundExtensions.contains((file as NSString).pathExtension.lowercased()) {
                try? Data(base64Encoded: b64)?.write(to: pd.appendingPathComponent(file))
            }
        }
        folderOverride = dir
        reload()
        return true
    }

    /// Reads every pack. Call before the renderer compiles the shader (fish kinds go into it) and before applying the theme.
    /// Undoes everything the packs registered and reads them again. The app then recompiles the shader and applies the theme.
    static func reload() {
        Themes.unregister(themeIds)
        Generator.unregister(styleIds)
        FishKinds.dropPacks()
        SceneryKinds.all = []
        for k in FaunaKinds.all { FaunaKinds.drop(k.id) }
        PackPresences.all = []
        PackBackgrounds.all = []
        Scene.unregisterPacks()
        SampleBank.reset()
        soundTimbres = [:]
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

    #if os(macOS)
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
        let allowed: Set<String> = ["json", "metal", "md", "txt", "png", "wav", "aif", "aiff", "caf"]
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
    #endif

    /// An entry's name in the interface's language ("names": {"en": "…"}), or its "name", or its id.
    static func localName(_ d: [String: Any], _ id: String) -> String {
        (d["names"] as? [String: String])?[L10n.resolved] ?? d["name"] as? String ?? id
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
        var pack = Loaded(id: json["id"] as? String ?? name,
                          name: (json["names"] as? [String: String])?[L10n.resolved] ?? json["name"] as? String ?? name)
        for k in ["version", "author", "license", "description", "homepage", "minApp"] { if let v = json[k] as? String { pack.meta[k] = v } }
        if let d = (json["descriptions"] as? [String: String])?[L10n.resolved] { pack.meta["description"] = d }
        if let min = pack.meta["minApp"], older(appVersion, than: min) {
            problems.append(tr("%@: precisa do Fishbots %@ ou mais novo", pack.name, min))
            return
        }
        if let reason = paused[pack.id] {
            pausedFound.append((pack.id, pack.name, reason))
            problems.append(tr("%@: pausado, %@ (Tema → Reativar)", pack.name, reasonText(reason)))
            return
        }

        for t in json["themes"] as? [[String: Any]] ?? [] {
            if var theme = Theme(json: t, base: Themes.named("classic")) {
                // its own background, drawn by the pack
                if let bg = t["background"] as? [String: Any] {
                    if let file = bg["metal"] as? String, let fn = bg["function"] as? String, !file.contains("/"),
                       fn.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
                       let src = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) {
                        PackBackgrounds.all.removeAll { $0.id == theme.id }
                        PackBackgrounds.all.append(PackBackground(id: theme.id, source: src, function: fn, pack: pack.id))
                        theme.uniforms.pack = [Float(PackBackgrounds.all.count), bg["replaceReef"] as? Bool ?? true ? 1 : 0, theme.floor ? 0 : 1, theme.surface ? 0 : 1]
                    } else {
                        problems.append(tr("%@: fundo incompleto (%@)", name, theme.id))
                    }
                }
                if theme.description.isEmpty, theme.descriptions.isEmpty {     // a theme without its own: the pack's
                    theme.description = json["description"] as? String ?? ""
                    theme.descriptions = json["descriptions"] as? [String: String] ?? [:]
                }
                Themes.register(theme); themeIds.append(theme.id); themePack[theme.id] = pack.id
                pack.contents.append(tr("tema %@", theme.displayName))
            }
            else { problems.append(tr("%@: tema sem \"id\"", name)) }
        }

        // sounds first: the styles below may play them
        for snd in json["sounds"] as? [[String: Any]] ?? [] {
            guard let id = snd["id"] as? String, let file = snd["file"] as? String, !file.contains("/"),
                  ["wav", "aif", "aiff", "caf"].contains((file as NSString).pathExtension.lowercased()) else {
                problems.append(tr("%@: som incompleto (%@)", name, snd["id"] as? String ?? "?"))
                continue
            }
            guard builtInTimbres[id] == nil else { problems.append(tr("%@: o som %@ já existe", name, id)); continue }
            guard let timbre = SampleBank.load(dir.appendingPathComponent(file), root: frequency(snd["root"]) ?? 440,
                                               gain: (snd["gain"] as? NSNumber)?.floatValue ?? 1) else {
                problems.append(tr("%@: não consegui ler o som %@", name, file))
                continue
            }
            soundTimbres[id] = timbre
            pack.contents.append(tr("som %@", localName(snd, id)))
        }
        let chords = (json["chords"] as? [String: [NSNumber]] ?? [:]).mapValues { $0.map { $0.intValue % 12 } }
        let progressions = json["progressions"] as? [String: [String]] ?? [:]
        for s in json["styles"] as? [[String: Any]] ?? [] {
            if let style = style(s) {
                Generator.register(style, chords: chords, progressions: progressions)
                styleIds.append(style.id)
                if let v = s["visualizer"] as? String { Visualizers.setDefault(v, forStyle: style.id) }
                pack.contents.append(tr("estilo %@", localName(s, style.name)))
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
            FishKinds.register(FishKind(id: id, name: localName(f, id), source: src, call: "\(fn)(c, phase, glow, col, extra)",
                                        pack: pack.id, swim: FishSwim(json: f["swim"] as? [String: Any])))
            pack.contents.append(tr("peixe %@", localName(f, id)))
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
                id: id, name: localName(sc, id), source: src, function: fn, pack: pack.id, anchor: anchor,
                extent: ext.flatMap { $0.count == 2 ? SIMD2($0[0], $0[1]) : nil } ?? [1, 1],
                size: max(0.005, min(0.5, num("size", 0.06))), color: col, at: at.map { max(0, min(1, $0)) },
                height: max(0, min(1, num("height", 0.5))), glowAtNight: sc["glowAtNight"] as? Bool ?? false,
                drift: sc["drift"] as? Bool ?? (anchor == .surface), solid: sc["solid"] as? Bool ?? (anchor != .surface),
                bury: max(0, min(0.6, num("bury", 0.05)))))
            pack.contents.append(tr("cenário %@", localName(sc, id)))
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
                id: id, name: localName(fa, id), source: src, function: fn, pack: pack.id, behavior: behavior,
                size: max(4, min(400, num("size", 16))), count: max(1, cnt.lowerBound)...min(30, max(1, cnt.upperBound)),
                speed: max(1, min(400, num("speed", 20))), height: max(0.05, hgt.lowerBound)...min(0.95, hgt.upperBound),
                when: FaunaKind.When(rawValue: fa["when"] as? String ?? "any") ?? .any,
                color: Theme.color(fa["color"]).map { SIMD3($0.x, $0.y, $0.z) } ?? [0.6, 0.6, 0.6],
                extent: ext.flatMap { $0.count == 2 ? SIMD2($0[0], $0[1]) : nil } ?? [1, 1],
                every: max(5, every.lowerBound)...max(5, every.upperBound), shy: fa["shy"] as? Bool ?? false,
                on: fa["on"] as? String, front: fa["front"] as? Bool ?? false))
            pack.contents.append(tr("criatura %@", localName(fa, id)))
        }
        for pr in json["presences"] as? [[String: Any]] ?? [] {
            guard let id = pr["id"] as? String, let file = pr["metal"] as? String, let fn = pr["function"] as? String,
                  fn.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil,
                  !file.contains("/"), let src = try? String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8) else {
                problems.append(tr("%@: presença incompleta (%@)", name, pr["id"] as? String ?? "?"))
                continue
            }
            guard Scene.kinds[id] == nil || Scene.kinds[id]?.pack != nil else {
                problems.append(tr("%@: a presença %@ já existe", name, id))
                continue
            }
            let motions: [String: PresenceKind.Motion] = ["swim": .swim, "drift": .drift, "hover": .hover, "walk": .walk, "sit": .sit, "float": .float, "glass": .glass]
            func num(_ k: String, _ def: Float) -> Float { (pr[k] as? NSNumber)?.floatValue ?? def }
            let band = (pr["band"] as? [NSNumber]).flatMap { $0.count == 2 && $0[0].floatValue <= $0[1].floatValue
                ? max(0.05, $0[0].floatValue)...min(0.95, $0[1].floatValue) : nil } ?? 0.3...0.6
            let ext = (pr["extent"] as? [NSNumber]).flatMap { $0.count == 2 ? SIMD2($0[0].floatValue, $0[1].floatValue) : nil } ?? [1, 1]
            PackPresences.all.removeAll { $0.id == id }
            PackPresences.all.append(PackPresence(id: id, source: src, function: fn, pack: pack.id))
            var k = PresenceKind(id: id, sprite: 37, motion: motions[pr["motion"] as? String ?? "swim"] ?? .swim,
                                 size: max(6, min(200, num("size", 30))),
                                 color: Theme.color(pr["color"]).map { SIMD3($0.x, $0.y, $0.z) } ?? [0.7, 0.7, 0.7], band: band)
            k.meter = pr["meter"] as? Bool ?? false
            k.drops = pr["drops"] as? Bool ?? false
            if let snd = pr["sound"] as? String, Scene.voices.contains(snd) { k.sound = snd }
            k.pack = PackPresences.all.count - 1
            k.extent = ext
            Scene.register(k)
            pack.contents.append(tr("presença %@", localName(pr, id)))
        }
        // the themes' effects: known names, and "as" one of them
        for t in json["themes"] as? [[String: Any]] ?? [] {
            for (k, v) in t["effects"] as? [String: Any] ?? [:] {
                let other = (v as? [String: Any])?["as"] as? String
                for n in [k] + (other.map { [$0] } ?? []) where !Scene.effects.contains(n) {
                    problems.append(tr("%@: o tema tem um efeito que não existe: %@", name, n))
                }
            }
        }
        // the themes' looks for presences: the drawing must be a pack's presence that moves the same way
        for t in json["themes"] as? [[String: Any]] ?? [] {
            for (from, to) in t["looks"] as? [String: String] ?? [:] {
                // (a look for a piece of scenery or a fish kind isn't a presence's: "chest" is both a piece and a presence)
                guard let k = Scene.kinds[from], k.pack == nil, SceneryKinds.index(of: to) == nil,
                      !FishKinds.all.contains(where: { $0.id == to }) else { continue }
                if let d = Scene.kinds[to], d.pack != nil, d.motion == k.motion { continue }
                if Scene.variants[to]?.of == from { continue }           // a built-in variant ("shark": "hammerhead")
                problems.append(tr("%@: no tema, %@ não pode virar %@ (precisa ser uma presença de pacote que se move igual)", name, from, to))
            }
        }
        loaded.append(pack)
    }

    /// The renderer couldn't compile a pack theme's background: the theme stays, with the usual background.
    static func backgroundFailed(_ bg: PackBackground, _ error: String) {
        let line = error.split(separator: "\n").first { $0.contains("error") } ?? Substring(error)
        problems.append(tr("%@: o fundo do tema %@ não compilou (%@)", bg.pack, bg.id, String(line.prefix(140))))
    }

    /// The renderer couldn't compile a pack's presence: it's dropped and reported.
    static func presenceFailed(_ kind: PackPresence, _ error: String) {
        let line = error.split(separator: "\n").first { $0.contains("error") } ?? Substring(error)
        problems.append(tr("%@: a presença %@ não compilou (%@)", kind.pack, kind.id, String(line.prefix(140))))
        Scene.unregister(kind.id)
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

    private static let builtInTimbres: [String: Timbre] = [
        "pluck": .pluck, "bell": .bell, "pad": .pad, "bass": .bass, "glass": .glass, "bubble": .bubble,
        "soft": .soft, "rhodes": .rhodes, "flute": .flute, "kalimba": .kalimba, "tap": .tap,
    ]
    /// The built-in timbres and the packs' sounds, by name (a style's "lead" and "accompTimbre").
    private(set) static var soundTimbres: [String: Timbre] = [:]
    private static var timbres: [String: Timbre] { builtInTimbres.merging(soundTimbres) { a, _ in a } }

    /// A note name ("A3", "C#4") or a MIDI number to a frequency.
    private static func frequency(_ v: Any?) -> Float? {
        if let n = v as? NSNumber { return 440 * powf(2, (n.floatValue - 69) / 12) }
        guard let s = v as? String, let m = s.range(of: #"^([A-Ga-g])([#b]?)(-?\d)$"#, options: .regularExpression) else { return nil }
        let t = String(s[m]), letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        var semis = letters[Character(t.prefix(1).uppercased())] ?? 0
        if t.contains("#") { semis += 1 } else if t.dropFirst().hasPrefix("b") { semis -= 1 }
        guard let oct = Int(t.filter { $0.isNumber || $0 == "-" }) else { return nil }
        return 440 * powf(2, Float((oct + 1) * 12 + semis - 69) / 12)
    }

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
        return Style(id: id, name: localName(s, id), bpm: range("bpm", 56...72), progs: progs, scale: scale,
                     barsPerChord: max(1, (s["barsPerChord"] as? NSNumber)?.intValue ?? 2),
                     lead: timbreList("lead", [.soft]), accomp: accomp, accompTimbre: timbreList("accompTimbre", [.soft]),
                     notesPerBar: Int(notes.lowerBound)...Int(notes.upperBound), swing: range("swing", 0...0.1),
                     keys: keys.isEmpty ? [0] : keys, energy: min(1, max(0, (s["energy"] as? NSNumber)?.doubleValue ?? 0.3)),
                     rest: min(0.9, max(0, (s["rest"] as? NSNumber)?.doubleValue ?? 0.35)))
    }
}
