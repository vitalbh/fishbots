import Foundation

/// Settings saved by older versions used Portuguese keys and values. On the first launch of this version they are
/// copied to the English ones (the old keys are removed), so nicknames, motifs, attention rules and preferences survive.
enum Migration {
    private static let doneKey = "migratedToEnglish"

    /// Old key → new key, for values that keep their meaning as they are.
    private static let renamedKeys: [String: String] = [
        "apelidos": "nicknames", "foco": "focus", "motivos": "motifs", "silenciados": "muted",
        "musicaAmbiente": "ambientMusic", "notasFerramenta": "toolNotes", "lerPerguntas": "readQuestions",
        "soBarra": "menuBarOnly", "auroraFundo": "auroraBackground",
    ]

    /// Attention levels and label modes by their old names.
    static let legacyLevels = ["ambiente": "ambient", "atencao": "attention", "urgente": "urgent"]
    private static let legacyLabelModes = ["minimo": "minimal", "completo": "full", "nenhum": "none"]
    private static let legacyVisuals = [
        "aleatorio": "random", "plancton": "plankton", "superficie": "surface", "partitura": "score",
        "constelacao": "constellation", "fogos": "fireworks",
    ]

    static func run() {
        fromOldBundle()   // first: it brings the flags below along
        fromAquario()
        let d = UserDefaults.standard
        guard !d.bool(forKey: doneKey) else { return }
        for (old, new) in renamedKeys {
            if let v = d.object(forKey: old) {
                if d.object(forKey: new) == nil { d.set(v, forKey: new) }
                d.removeObject(forKey: old)
            }
        }
        if let raw = d.dictionary(forKey: "atencao") as? [String: String] {
            if d.object(forKey: "attention") == nil { d.set(attentionRules(raw), forKey: "attention") }
            d.removeObject(forKey: "atencao")
        }
        if let v = d.string(forKey: "rotulos") {
            if d.object(forKey: "labels") == nil { d.set(legacyLabelModes[v] ?? v, forKey: "labels") }
            d.removeObject(forKey: "rotulos")
        }
        if let v = d.string(forKey: "visual") { d.set(legacyVisuals[v] ?? v, forKey: "visual") }
        if let data = d.data(forKey: "perolas") {
            if d.object(forKey: "pearls") == nil { d.set(pearls(data), forKey: "pearls") }
            d.removeObject(forKey: "perolas")
        }
        d.set(true, forKey: doneKey)
    }

    /// The bundle id was io.vital.fishbots (now io.vitalbh.fishbots, the author's domain): the first time, the old
    /// settings come over (nicknames, motifs, attention rules, pearls, window…). Folders didn't change ("Fishbots").
    private static func fromOldBundle() {
        let d = UserDefaults.standard
        guard Bundle.main.bundleIdentifier == "io.vitalbh.fishbots", !d.bool(forKey: "migratedFromOldBundle") else { return }
        if let old = d.persistentDomain(forName: "io.vital.fishbots") {
            for (k, v) in old where d.object(forKey: k) == nil { d.set(v, forKey: k) }
        }
        d.set(true, forKey: "migratedFromOldBundle")
    }

    /// The app used to be called Aquário (bundle io.vital.aquario, folder "Aquario"). The first time Fishbots runs,
    /// it brings over the old settings and moves the old folders (config.json, plugins, goto.sh, logs).
    private static func fromAquario() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedFromAquario") else { return }
        if let old = d.persistentDomain(forName: "io.vital.aquario") {
            for (k, v) in old where d.object(forKey: k) == nil {
                d.set(v, forKey: k == "NSWindow Frame Aquario" ? "NSWindow Frame Fishbots" : k)
            }
        }
        let fm = FileManager.default
        let lib = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        for dir in ["Application Support", "Logs"] {
            let old = lib.appendingPathComponent(dir).appendingPathComponent("Aquario")
            let new = lib.appendingPathComponent(dir).appendingPathComponent("Fishbots")
            if fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }
        }
        d.set(true, forKey: "migratedFromAquario")
    }

    /// {"source:state": "level"} with the state and the level under their current names.
    static func attentionRules(_ raw: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in raw {
            var key = k
            if let i = k.lastIndex(of: ":") {
                let st = String(k[k.index(after: i)...])
                if let s = State.legacy[st] { key = k[..<i] + ":" + s.rawValue }
            }
            out[key] = legacyLevels[v] ?? v
        }
        return out
    }

    /// The saved pearls ({"day": [pearl]}) with the fields under their current names.
    private static func pearls(_ data: Data) -> Data {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: [[String: Any]]] else { return data }
        let names = ["cor": "color", "titulo": "title", "projeto": "project", "hora": "hour"]
        let out = obj.mapValues { list in
            list.map { p in Dictionary(uniqueKeysWithValues: p.map { (names[$0.key] ?? $0.key, $0.value) }) }
        }
        return (try? JSONSerialization.data(withJSONObject: out)) ?? data
    }
}
