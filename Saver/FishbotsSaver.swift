import AppKit
import MetalKit
import QuartzCore
import ScreenSaver

/// Fishbots screen saver: the same engine (Renderer, Shaders, Tank), without sound.
/// Asks the app (127.0.0.1:7777/state) who is in the tank; without the app, shows just the decorative aquarium.
/// Log in the screen saver's container (…/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/tmp/fishbots-saver.log).
func journal(_ msg: String) {
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fishbots-saver.log")
    let line = "\(Date()) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.write(to: url, atomically: true, encoding: .utf8) }
}

@objc(FishbotsSaverView)
final class FishbotsSaverView: ScreenSaverView {
    private var mtk: MTKView?
    private var renderer: Renderer?
    private let tank = Tank()
    private let visual = Visual()
    private let labels = CALayer()
    private var layers: [String: CATextLayer] = [:]
    private var poll: Timer?
    private var running = false
    private var connected = false
    /// The app's packs, copied here (the saver can't read the app's folder): their signature, and the theme applied.
    private var packsSignature = ""
    private var fetchingPacks = false
    private var appliedTheme = ""

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        journal("init preview=\(isPreview) frame=\(frame.size)")
        animationTimeInterval = 1.0 / 30
        wantsLayer = true
        tank.pearls.keep = false
        let v = MTKView(frame: bounds, device: MTLCreateSystemDefaultDevice())
        v.autoresizingMask = [.width, .height]
        v.colorPixelFormat = .bgra8Unorm
        v.preferredFramesPerSecond = 30
        v.isPaused = true
        v.enableSetNeedsDisplay = false
        addSubview(v)
        mtk = v
        if let r = Renderer(view: v) {
            renderer = r
            v.delegate = r
            journal("metal ok")
            r.frame = { [weak self] dt in self?.quadro(dt) ?? (Uniforms(res: .zero, time: 0, turbidity: 0, light: 1, alert: 0, pix: .zero), []) }
        }
        // no music: the visualizers react when a fish changes state (arrived, finished, waiting…)
        tank.onState = { [weak self] f, _ in
            guard let self else { return }
            let m = 60 + [0, 2, 4, 7, 9][Int.random(in: 0..<5)] + (f.state == .idle ? -12 : 0)
            self.visual.note(pos: f.pos, midi: m, vel: f.state == .waiting || f.state == .done ? 0.4 : 0.25, color: f.color, projectKey: f.id)
        }
        labels.frame = bounds
        labels.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(labels)
        labels.zPosition = 10

        // Sonoma onward: the screen saver process sometimes stays alive after it disappears. Stop everything when it stops.
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(saverStopped), name: .init("com.apple.screensaver.willstop"), object: nil)
        dnc.addObserver(self, selector: #selector(saverStopped), name: .init("com.apple.screensaver.didstop"), object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    override func startAnimation() {
        super.startAnimation()
        guard !running else { return }
        running = true
        journal("start")
        mtk?.isPaused = false
        fetch()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.fetch() }
    }

    override func stopAnimation() {
        super.stopAnimation()
        stop()
    }

    @objc private func saverStopped() { stop() }

    private func stop() {
        running = false
        mtk?.isPaused = true
        poll?.invalidate()
        poll = nil
    }

    override func animateOneFrame() {}   // the MTKView does the drawing
    override var hasConfigureSheet: Bool { false }

    // MARK: app state

    private func fetch() {
        guard let url = URL(string: "http://127.0.0.1:7777/state") else { return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        req.httpMethod = "GET"
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            let obj = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            journal(obj != nil ? "state ok: \((obj?["fish"] as? [Any])?.count ?? 0) fish" : "state failed: \(error.map { "\($0)" } ?? "no data")")
            DispatchQueue.main.async {
                guard let self else { return }
                if let obj { self.connected = true; self.apply(obj) }
                else if self.connected || error != nil {
                    self.connected = false
                    for f in self.tank.fish where !f.decor { self.tank.remove(source: f.source, entity: String(f.id.dropFirst(f.source.count + 1))) }
                }
            }
        }.resume()
    }

    /// The app's packs changed (or were never copied): fetch their files, read them here, compile the shader again.
    private func syncPacks(_ signature: String) {
        guard signature != packsSignature, !fetchingPacks, let url = URL(string: "http://127.0.0.1:7777/packs/files") else { return }
        fetchingPacks = true
        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetchingPacks = false
                guard let data else { journal("packs: fetch failed"); return }
                let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fishbots-saver-packs", isDirectory: true)
                guard Packs.mirror(data, into: dir) else { journal("packs: bad data"); return }
                journal("packs: \(Packs.loaded.map(\.id)) problems: \(Packs.problems.count)")
                self.packsSignature = signature
                self.renderer?.reload()
                self.appliedTheme = ""                   // apply it again, with what the packs brought
            }
        }.resume()
    }

    /// The app's theme, as the app applies it: water, seaweed, scenery and its looks, creatures, schools.
    private func applyTheme(_ id: String?) {
        let theme = Themes.named(id)
        renderer?.theme = theme.uniforms
        guard theme.id != appliedTheme else { return }
        appliedTheme = theme.id
        Themes.current = theme
        tank.weedCount = theme.weedCount
        tank.rayStrength = theme.uniforms.params.z
        visual.themeVisualizer = theme.visualizer
        tank.fauna.select(theme.fauna)
        tank.weedShapes = theme.weedShapes
        tank.sceneryLooks = theme.looks
        tank.sceneryKinds = theme.scenery
        tank.scene.themeLooks = theme.looks
        tank.scene.dressByTheme = FishKinds.dressByTheme
        tank.setSchools(theme.schools ?? School.usual)
    }

    private func apply(_ obj: [String: Any]) {
        // the app's packs (copied when they change) and its theme
        if let sig = obj["packsSignature"] as? String { syncPacks(sig) }
        applyTheme(obj["theme"] as? String)
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

    // MARK: frame

    private func quadro(_ dt: Float) -> (Uniforms, [Sprite]) {
        tank.size = [Float(bounds.width), Float(bounds.height)]
        tank.update(dt: dt)
        visual.size = tank.size
        visual.update(dt: min(dt, 0.05))
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let h = Float(c.hour ?? 12) + Float(c.minute ?? 0) / 60
        tank.light = 0.62 + 0.38 * smoothstep(5.5, 8, h) * (1 - smoothstep(18, 20.5, h))
        visual.light = tank.light
        if !isPreview { updateLabels() }
        renderer?.weeds = tank.weedUniforms()
        if let r = renderer { tank.shaderTime = r.shaderTime }
        return (Uniforms(res: .zero, time: 0, turbidity: tank.turbidity, light: tank.light, alert: 0, pix: .zero, grade: Sky().grade(hour: h),
                         scene: [tank.gauges.highest("waves") ?? 0, tank.gauges.highest("rain") ?? 0,
                                 tank.gauges.highest("temperature") ?? 0.5, tank.gauges.highest("fog") ?? 0],
                         sky: Sky().disc(hour: h)),
                visual.sprites() + tank.sprites())
    }

    /// Name and state under each fish; whoever is waiting for you shows up in yellow.
    private func updateLabels() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = window?.backingScaleFactor ?? 2
        var alive = Set<String>()
        for f in tank.fish where !f.decor {
            alive.insert(f.id)
            let l = layers[f.id] ?? {
                let t = CATextLayer()
                t.contentsScale = scale
                t.alignmentMode = .center
                t.shadowOpacity = 0.9
                t.shadowRadius = 2
                t.shadowOffset = .zero
                labels.addSublayer(t)
                layers[f.id] = t
                return t
            }()
            // minimal: the short title (or name) and, only if it needs you, a colored second line
            let base = f.isAgent ? (f.displayTitle ?? f.label) : f.label
            let name = base.count > 24 ? String(base.prefix(23)) + "…" : base
            let s = NSMutableAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.7)])
            if f.state == .waiting || f.state == .error {
                let color: NSColor = f.state == .waiting ? NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1) : NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1)
                let t = f.state == .waiting ? (f.asked.map { "✋ " + String($0.prefix(40)) } ?? tr("✋ esperando você")) : tr("✗ erro")
                s.append(NSAttributedString(string: "\n" + t, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: color]))
            }
            l.string = s
            let sz = s.size()
            l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
            l.position = CGPoint(x: CGFloat(f.pos.x), y: CGFloat(f.pos.y - f.size * 0.75) - l.bounds.height / 2)
            l.opacity = f.leaving ? 0.3 : 1
        }
        // the presences: their label, and the detail in the state's color while they need you
        for p in tank.scene.presences {
            let key = "presence:" + p.id
            alive.insert(key)
            let l = layers[key] ?? {
                let t = CATextLayer()
                t.contentsScale = scale
                t.alignmentMode = .center
                t.shadowOpacity = 0.9
                t.shadowRadius = 2
                t.shadowOffset = .zero
                labels.addSublayer(t)
                layers[key] = t
                return t
            }()
            let name = p.label.count > 24 ? String(p.label.prefix(23)) + "…" : p.label
            let s = NSMutableAttributedString(string: name, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(white: 1, alpha: 0.65)])
            if p.needsYou {
                let color: NSColor = p.state == .waiting ? NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
                    : p.state == .alert ? NSColor(red: 1, green: 0.75, blue: 0.3, alpha: 1) : NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1)
                let icon = p.state == .waiting ? "✋ " : p.state == .alert ? "⚠︎ " : "✗ "
                let text = p.detail.map { icon + String($0.prefix(40)) } ?? p.state.label
                s.append(NSAttributedString(string: "\n" + text, attributes: [.font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: color]))
            }
            l.string = s
            let sz = s.size()
            l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
            let (at, above) = tank.scene.labelAnchor(p)
            l.position = CGPoint(x: CGFloat(at.x), y: CGFloat(at.y) + (above ? 1 : -1) * l.bounds.height / 2)
            l.opacity = p.alpha
        }
        for (id, l) in layers where !alive.contains(id) {
            l.removeFromSuperlayer()
            layers[id] = nil
        }
        CATransaction.commit()
    }
}
