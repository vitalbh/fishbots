import MetalKit
import SwiftUI
import UIKit

/// The Mac's tank, drawn here by the same engine (Renderer, the shaders, TankMirror): the fish swim on their own,
/// the Mac only says who's there and how they are. Touching a fish opens its card.
struct AquariumView: UIViewRepresentable {
    let mirror: TankMirror
    var showLabels = true
    /// What the water's touches open (the rest, food, knocks and currents, the view does by itself).
    var touched: (AquariumUIView.Touch) -> Void

    func makeUIView(context: Context) -> AquariumUIView { AquariumUIView(mirror: mirror) }
    func updateUIView(_ v: AquariumUIView, context: Context) {
        v.touched = touched
        v.showLabels = showLabels
    }
}

final class AquariumUIView: UIView {
    private let mirror: TankMirror
    private let mtk: MTKView
    private var renderer: Renderer?
    private let labels = CALayer()
    private var layers: [String: CATextLayer] = [:]
    /// Something in the water was touched that opens something: a fish's card, the eggs (a new session), the chest
    /// (the last hours), a presence (its text or link), or a knock on the glass (its sound).
    enum Touch {
        case fish(String), eggs, chest, assistant, presence(source: String, id: String), knock(x: Float)
    }
    var touched: ((Touch) -> Void)?
    /// The names under the fish (the menu's switch).
    var showLabels = true { didSet { labels.isHidden = !showLabels } }

    init(mirror: TankMirror) {
        self.mirror = mirror
        mtk = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        super.init(frame: .zero)
        backgroundColor = .black
        mtk.colorPixelFormat = .bgra8Unorm
        mtk.autoResizeDrawable = true
        mtk.preferredFramesPerSecond = 60
        mtk.isUserInteractionEnabled = false
        addSubview(mtk)
        layer.addSublayer(labels)
        labels.zPosition = 10
        if let r = Renderer(view: mtk) {
            renderer = r
            mirror.renderer = r
            mtk.delegate = r
            r.frame = { [weak self] dt in
                guard let self else { return (Uniforms(res: .zero, time: 0, turbidity: 0, light: 1, alert: 0, pix: .zero), []) }
                let out = self.mirror.frame(dt: dt, size: [Float(self.mtk.bounds.width), Float(self.mtk.bounds.height)])
                self.updateLabels()
                return out
            }
        }
        // as on the Mac: a tap feeds (or startles who's near), two knock on the glass, a drag nudges a fish or
        // makes a current, holding sprinkles food
        let double = UITapGestureRecognizer(target: self, action: #selector(knocked(_:)))
        double.numberOfTapsRequired = 2
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        tap.require(toFail: double)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        pan.maximumNumberOfTouches = 1
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.35
        for g in [double, tap, pan, hold] { addGestureRecognizer(g) }
        #if DEBUG
        // fishbots://test?do=tap:x,y | knock:x,y | hold:x,y (points, from the top left): what a finger would do
        NotificationCenter.default.addObserver(forName: .fishbotsTest, object: nil, queue: .main) { [weak self] n in
            guard let self, let url = n.object as? URL,
                  let d = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "do" })?.value,
                  let colon = d.firstIndex(of: ":") else { return }
            let xy = d[d.index(after: colon)...].split(separator: ",").compactMap { Double($0) }
            guard xy.count == 2 else { return }
            let p = CGPoint(x: xy[0], y: xy[1])
            switch d[..<colon] {
            case "tap": self.tap(at: p)
            case "knock": self.knock(at: p)
            case "hold": for i in 0..<12 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.12) { self.mirror.tank.sprinkle(at: self.tank(p), amount: 6) } }
            default: break
            }
        }
        #endif
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    /// The Mac's tank is made for a window a thousand points wide and more; a phone held upright is under 400, and
    /// the scenery, the presences and the assistant's burrow crowd into it. So the tank here is a wider one (560
    /// points at least), drawn shrunk to fit: everything gets its room. On its side, the phone draws it as it is.
    /// The names stay at their size (they're drawn over it, not in it).
    private var zoom: CGFloat { bounds.width > 0 ? min(1, bounds.width / 560) : 1 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let z = zoom
        mtk.transform = .identity
        mtk.bounds = CGRect(x: 0, y: 0, width: bounds.width / z, height: bounds.height / z)
        mtk.center = CGPoint(x: bounds.midX, y: bounds.midY)
        mtk.transform = CGAffineTransform(scaleX: z, y: z)
        // the drawable at the screen's own pixels, not the bigger tank's
        mtk.contentScaleFactor = traitCollection.displayScale * z
        labels.frame = bounds
    }

    /// The tank's y grows upward (as on the Mac); UIKit's grows downward. The tank is the bigger one (`zoom`).
    private func point(_ p: SIMD2<Float>) -> CGPoint {
        CGPoint(x: CGFloat(p.x) * zoom, y: (mtk.bounds.height - CGFloat(p.y)) * zoom)
    }

    /// A label's center, kept on screen (a fish or a presence near the side glass would cut its name in half).
    private func onScreen(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: max(size.width / 2 + 4, min(bounds.width - size.width / 2 - 4, p.x)), y: p.y)
    }

    /// A point of the view in the tank's coordinates.
    private func tank(_ p: CGPoint) -> SIMD2<Float> { [Float(p.x / zoom), Float(mtk.bounds.height - p.y / zoom)] }

    /// The Mac's click (AppDelegate.click), on the phone: a fish opens its card; a presence, its text or link; the
    /// eggs, a new session; the chest, the last hours; the water, food (or a start, near fish).
    @objc private func tapped(_ g: UITapGestureRecognizer) { tap(at: g.location(in: self)) }

    private func tap(at p: CGPoint) {
        let q = tank(p)
        let t = mirror.tank
        if let f = nearestFish(q) {
            touched?(.fish(f.id))
        } else if let p = t.scene.presence(at: q) {
            t.ring(at: q, color: [1, 1, 1], size: p.kind.size * 0.4, grow: 120, life: 0.6)
            touched?(p.id == "fishbots:assistant" ? .assistant : .presence(source: p.source, id: String(p.id.dropFirst(p.source.count + 1))))
        } else if t.scenery.eggsHit(t, at: q) {
            touched?(.eggs)
        } else if t.scenery.chestHit(t, at: q) {
            touched?(.chest)
        } else if !t.scare(q) {
            t.feed(at: q)
        }
    }

    /// A fish under the finger (a finger is wider than a cursor: within its size, or 44 points).
    private func nearestFish(_ q: SIMD2<Float>) -> Fish? {
        mirror.tank.fish.filter { !$0.decor && !$0.leaving }
            .map { ($0, simd_distance($0.pos, q)) }
            .filter { $0.1 < max(44 / Float(zoom), $0.0.size * 0.9) }
            .min { $0.1 < $1.1 }?.0
    }

    @objc private func knocked(_ g: UITapGestureRecognizer) { knock(at: g.location(in: self)) }

    private func knock(at p: CGPoint) {
        let q = tank(p)
        guard nearestFish(q) == nil else { return }
        mirror.tank.knock(at: q)
        touched?(.knock(x: q.x / max(1, mirror.tank.size.x)))
    }

    private var dragFrom: SIMD2<Float>?

    @objc private func dragged(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            dragFrom = tank(g.location(in: self) - g.translation(in: self))
        case .changed:
            if let from = dragFrom { mirror.tank.drag(from: from, to: tank(g.location(in: self))) }
        default:
            mirror.tank.endDrag()
            dragFrom = nil
        }
    }

    private var sprinkler: Timer?

    @objc private func held(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            let q = tank(g.location(in: self))
            if sprinkler == nil {
                sprinkler = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self, weak g] _ in
                    guard let self, let g else { return }
                    self.mirror.tank.sprinkle(at: self.tank(g.location(in: self)), amount: 6)
                }
            }
            mirror.tank.sprinkle(at: q, amount: 6)
        default:
            sprinkler?.invalidate()
            sprinkler = nil
        }
    }

    private func label(_ key: String) -> CATextLayer {
        if let l = layers[key] { return l }
        let t = CATextLayer()
        t.contentsScale = traitCollection.displayScale
        t.alignmentMode = .center
        t.shadowOpacity = 0.9
        t.shadowRadius = 2
        t.shadowOffset = .zero
        labels.addSublayer(t)
        layers[key] = t
        return t
    }

    /// Name and, when it needs you, a colored second line under each fish (as in the screen saver).
    private func updateLabels() {
        guard showLabels else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var alive = Set<String>()
        // who gets a place first when names would overlap: what needs you, then the sessions, then the rest
        var placing: [(layer: CATextLayer, rank: Int)] = []
        for f in mirror.tank.fish where !f.decor {
            alive.insert(f.id)
            let l = label(f.id)
            let base = f.isAgent ? (f.displayTitle ?? f.label) : f.label
            let name = base.count > 24 ? String(base.prefix(23)) + "…" : base
            let s = NSMutableAttributedString(string: name, attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: UIColor(white: 1, alpha: 0.75)])
            if f.state == .waiting || f.state == .error {
                let color = f.state == .waiting ? UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1) : UIColor(red: 1, green: 0.45, blue: 0.4, alpha: 1)
                let t = f.state == .waiting ? (f.asked.map { "✋ " + String($0.prefix(40)) } ?? tr("✋ esperando você")) : tr("✗ erro")
                s.append(NSAttributedString(string: "\n" + t, attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: color]))
            }
            l.string = s
            let sz = s.size()
            l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
            let at = point([f.pos.x, f.pos.y - f.size * 0.75])
            l.position = onScreen(CGPoint(x: at.x, y: at.y + l.bounds.height / 2), l.bounds.size)
            l.opacity = f.leaving ? 0.3 : 1
            placing.append((l, f.state == .waiting || f.state == .error ? 0 : 1))
        }
        for p in mirror.tank.scene.presences {
            let key = "presence:" + p.id
            // a light on the glass that's fine says it with its color: its name only when it needs you
            if p.kind.motion == .glass && !p.needsYou { continue }
            alive.insert(key)
            let l = label(key)
            let name = p.label.count > 24 ? String(p.label.prefix(23)) + "…" : p.label
            let s = NSMutableAttributedString(string: name, attributes: [
                .font: UIFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: UIColor(white: 1, alpha: 0.65)])
            if p.needsYou {
                let color = p.state == .waiting ? UIColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
                    : p.state == .alert ? UIColor(red: 1, green: 0.75, blue: 0.3, alpha: 1) : UIColor(red: 1, green: 0.45, blue: 0.4, alpha: 1)
                let icon = p.state == .waiting ? "✋ " : p.state == .alert ? "⚠︎ " : "✗ "
                let text = p.detail.map { icon + String($0.prefix(40)) } ?? p.state.label
                s.append(NSAttributedString(string: "\n" + text, attributes: [.font: UIFont.systemFont(ofSize: 10.5), .foregroundColor: color]))
            }
            l.string = s
            let sz = s.size()
            l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
            let (anchor, above) = mirror.tank.scene.labelAnchor(p)
            let at = point(anchor)
            l.position = onScreen(CGPoint(x: at.x, y: at.y + (above ? -1 : 1) * l.bounds.height / 2), l.bounds.size)
            l.opacity = p.alpha
            placing.append((l, p.needsYou ? 0 : 2))
        }
        // a name that would land on one already placed waits for room (what needs you always shows)
        var taken: [CGRect] = []
        for (l, rank) in placing.sorted(by: { $0.rank < $1.rank }) {
            let r = l.frame.insetBy(dx: 2, dy: 1)
            if rank > 0 && taken.contains(where: { $0.intersects(r) }) { l.opacity = 0; continue }
            if l.opacity > 0 { taken.append(r) }
        }
        for (id, l) in layers where !alive.contains(id) {
            l.removeFromSuperlayer()
            layers[id] = nil
        }
        CATransaction.commit()
    }
}

private func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
