import Foundation
import simd

/// A tank that copies the app's: what `GET /state` says is there (fish, presences, gauges, theme, packs) applied to a
/// tank of its own, which swims and draws by itself. The screen saver and the iPhone app are both this; neither
/// runs sessions, they only show the app's.
final class TankMirror {
    let tank = Tank()
    let visual = Visual()
    var renderer: Renderer?
    /// Fetches the app's packs (`GET /packs/files`) when they change; nil data: it failed.
    var fetchPacks: ((@escaping (Data?) -> Void) -> Void)?
    /// Where the packs are copied (each mirror its own folder).
    var packsFolder = FileManager.default.temporaryDirectory.appendingPathComponent("fishbots-mirror-packs", isDirectory: true)
    var log: (String) -> Void = { _ in }

    /// A theme of the mirror's own (the iPhone's choice); nil: the app's.
    var themeOverride: String? {
        didSet { applyTheme(themeOverride ?? appTheme) }
    }
    /// The theme the app is using, from its last state.
    private(set) var appTheme: String?

    private var packsSignature = ""
    private var fetchingPacks = false
    private var appliedTheme = ""

    init() {
        tank.pearls.keep = false
        // no music: the visualizers react when a fish changes state (arrived, finished, waiting…)
        tank.onState = { [weak self] f, _ in
            guard let self else { return }
            let m = 60 + [0, 2, 4, 7, 9][Int.random(in: 0..<5)] + (f.state == .idle ? -12 : 0)
            self.visual.note(pos: f.pos, midi: m, vel: f.state == .waiting || f.state == .done ? 0.4 : 0.25, color: f.color, projectKey: f.id)
        }
    }

    /// The app went away: only the decorative aquarium stays.
    func clear() {
        for f in tank.fish where !f.decor { tank.remove(source: f.source, entity: String(f.id.dropFirst(f.source.count + 1))) }
        for p in tank.scene.presences { tank.scene.remove(source: p.source, id: String(p.id.dropFirst(p.source.count + 1)), party: false, tank) }
    }

    /// The app's packs changed (or were never copied): fetch their files, read them here, compile the shader again.
    private func syncPacks(_ signature: String) {
        guard signature != packsSignature, !fetchingPacks, let fetchPacks else { return }
        fetchingPacks = true
        fetchPacks { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetchingPacks = false
                guard let data else { self.log("packs: fetch failed"); return }
                guard Packs.mirror(data, into: self.packsFolder) else { self.log("packs: bad data"); return }
                self.log("packs: \(Packs.loaded.map(\.id)) problems: \(Packs.problems.count)")
                for p in Packs.problems { self.log("  " + p) }
                self.packsSignature = signature
                self.renderer?.reload()
                self.appliedTheme = ""                   // apply it again, with what the packs brought
            }
        }
    }

    /// The app's theme, as the app applies it: water, seaweed, scenery and its looks, creatures, schools.
    func applyTheme(_ id: String?) {
        let theme = Themes.named(id)
        renderer?.theme = theme.uniforms
        guard theme.id != appliedTheme else { return }
        appliedTheme = theme.id
        Themes.current = theme
        tank.weeds.count = theme.weedCount
        tank.rayStrength = theme.uniforms.params.z
        visual.themeVisualizer = theme.visualizer
        tank.fauna.select(theme.fauna)
        tank.weeds.shapes = theme.weedShapes
        tank.scenery.pack = Packs.themePack[theme.id]
        tank.scenery.looks = theme.looks
        tank.scenery.kinds = theme.scenery
        tank.scene.themeLooks = theme.looks
        tank.scene.dressByTheme = FishKinds.dressByTheme
        tank.setSchools(theme.schools ?? School.usual)
    }

    /// What `/state` returned.
    func apply(_ obj: [String: Any]) {
        // the app's packs (copied when they change) and its theme
        if let sig = obj["packsSignature"] as? String { syncPacks(sig) }
        appTheme = obj["theme"] as? String
        applyTheme(themeOverride ?? appTheme)
        let fishes = obj["fish"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        for p in fishes {
            guard let source = p["source"] as? String, let ent = p["entity"] as? String,
                  let e = (p["state"] as? String).flatMap(State.init(rawValue:)),
                  (p["leaving"] as? Bool) != true else { continue }
            seen.insert("\(source):\(ent)")
            tank.upsert(source: source, entity: ent, state: e, label: p["label"] as? String)
            if let f = tank.fish(source: source, entity: ent) {
                if let o = p["where"] as? [String: String] { f.whereabouts = o }
                let d = p["detail"] as? String ?? ""
                f.sub = d.isEmpty ? nil : d
                if let c = (p["context"] as? NSNumber)?.floatValue, c >= 0 { f.context = c }
                if let a = p["agent"] as? Bool { f.isAgent = a }
                // its kind by name (the app's numbering includes the packs'); missing here: its base kind
                if let k = p["kind"] as? String, FishKinds.all.contains(where: { $0.id == k }) { f.species = FishKinds.index(of: k) }
                else if let b = p["baseKind"] as? String, FishKinds.all.contains(where: { $0.id == b }) { f.species = FishKinds.index(of: b) }
                else if let sp = (p["species"] as? NSNumber)?.intValue, sp < FishKinds.all.count { f.species = sp }
                if let s = p["sings"] as? Bool { f.sings = s }
                let t = p["title"] as? String ?? ""
                f.title = t.isEmpty ? nil : t
            }
        }
        for f in tank.fish where !f.decor && !seen.contains(f.id) {
            tank.remove(source: f.source, entity: String(f.id.dropFirst(f.source.count + 1)))
        }
        for (k, v) in obj["gauges"] as? [String: NSNumber] ?? [:] {
            let parts = k.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 { tank.gauges.set(source: parts[0], name: parts[1], value: v.floatValue) }
        }
        // the presences (docs/scene.md): the same creatures and objects, silent
        var present = Set<String>()
        for p in obj["presences"] as? [[String: Any]] ?? [] {
            guard let source = p["source"] as? String, let id = p["presence"] as? String, let kind = p["kind"] as? String else { continue }
            present.insert("\(source):\(id)")
            let value = (p["value"] as? NSNumber)?.floatValue
            _ = tank.scene.upsert(tank, source: source, id: id, kind: kind, state: (p["state"] as? String).flatMap(State.init(rawValue:)),
                                  label: p["label"] as? String, detail: p["detail"] as? String, link: nil,
                                  value: value.flatMap { $0 >= 0 ? $0 : nil }, color: nil, x: nil, sound: "none")
        }
        for p in tank.scene.presences where !present.contains(p.id) {
            tank.scene.remove(source: p.source, id: String(p.id.dropFirst(p.source.count + 1)), party: false, tank)
        }
    }

    /// One frame, for a view of `size` points: the tank moves on and says what to draw.
    func frame(dt: Float, size: SIMD2<Float>) -> (Uniforms, [Sprite]) {
        tank.size = size
        tank.update(dt: dt)
        visual.size = tank.size
        visual.update(dt: min(dt, 0.05))
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let h = Float(c.hour ?? 12) + Float(c.minute ?? 0) / 60
        tank.light = 0.62 + 0.38 * smoothstep(5.5, 8, h) * (1 - smoothstep(18, 20.5, h))
        visual.light = tank.light
        renderer?.weeds = tank.weeds.uniforms()
        if let r = renderer { tank.shaderTime = r.shaderTime }
        var u = Uniforms(res: .zero, time: 0, turbidity: tank.turbidity, light: tank.light, alert: 0, pix: .zero, grade: Sky().grade(hour: h),
                         scene: [tank.gauges.highest("waves") ?? 0, tank.gauges.highest("rain") ?? 0,
                                 tank.gauges.highest("temperature") ?? 0.5, tank.gauges.highest("fog") ?? 0],
                         sky: Sky().disc(hour: h))
        u.setLamps(tank.fauna.lamps(tank))
        return (u, visual.sprites() + tank.sprites())
    }
}
