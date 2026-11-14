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
    /// The app's tank, copied from its /state (TankMirror.swift).
    private let mirror = TankMirror()
    private var tank: Tank { mirror.tank }
    private let labels = CALayer()
    private var layers: [String: CATextLayer] = [:]
    private var poll: Timer?
    private var running = false
    private var connected = false

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        journal("init preview=\(isPreview) frame=\(frame.size)")
        animationTimeInterval = 1.0 / 30
        wantsLayer = true
        mirror.log = journal
        // the saver can't read the app's folder: the packs are copied from it
        mirror.packsFolder = FileManager.default.temporaryDirectory.appendingPathComponent("fishbots-saver-packs", isDirectory: true)
        mirror.fetchPacks = { done in
            guard let url = URL(string: "http://127.0.0.1:7777/packs/files") else { return done(nil) }
            URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)) { data, _, _ in done(data) }.resume()
        }
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
            mirror.renderer = r
            v.delegate = r
            journal("metal ok")
            r.frame = { [weak self] dt in self?.quadro(dt) ?? (Uniforms(res: .zero, time: 0, turbidity: 0, light: 1, alert: 0, pix: .zero), []) }
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
                if let obj { self.connected = true; self.mirror.apply(obj) }
                else if self.connected || error != nil {
                    self.connected = false
                    self.mirror.clear()
                }
            }
        }.resume()
    }

    // MARK: frame

    private func quadro(_ dt: Float) -> (Uniforms, [Sprite]) {
        let out = mirror.frame(dt: dt, size: [Float(bounds.width), Float(bounds.height)])
        if !isPreview { updateLabels() }
        return out
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
