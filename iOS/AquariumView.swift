import MetalKit
import SwiftUI
import UIKit

/// The Mac's tank, drawn here by the same engine (Renderer, the shaders, TankMirror): the fish swim on their own,
/// the Mac only says who's there and how they are. Touching a fish opens its card.
struct AquariumView: UIViewRepresentable {
    let mirror: TankMirror
    var onTap: (String) -> Void

    func makeUIView(context: Context) -> AquariumUIView { AquariumUIView(mirror: mirror) }
    func updateUIView(_ v: AquariumUIView, context: Context) { v.onTap = onTap }
}

final class AquariumUIView: UIView {
    private let mirror: TankMirror
    private let mtk: MTKView
    private var renderer: Renderer?
    private let labels = CALayer()
    private var layers: [String: CATextLayer] = [:]
    var onTap: ((String) -> Void)?

    init(mirror: TankMirror) {
        self.mirror = mirror
        mtk = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        super.init(frame: .zero)
        backgroundColor = .black
        mtk.colorPixelFormat = .bgra8Unorm
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
                let out = self.mirror.frame(dt: dt, size: [Float(self.bounds.width), Float(self.bounds.height)])
                self.updateLabels()
                return out
            }
        }
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        mtk.frame = bounds
        labels.frame = bounds
    }

    /// The tank's y grows upward (as on the Mac); UIKit's grows downward.
    private func point(_ p: SIMD2<Float>) -> CGPoint { CGPoint(x: CGFloat(p.x), y: bounds.height - CGFloat(p.y)) }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let at = g.location(in: self)
        let tank: SIMD2<Float> = [Float(at.x), Float(bounds.height - at.y)]
        let near = mirror.tank.fish.filter { !$0.decor && !$0.leaving }
            .map { ($0, simd_distance($0.pos, tank)) }
            .filter { $0.1 < max(44, $0.0.size * 0.9) }
            .min { $0.1 < $1.1 }
        if let f = near?.0 { onTap?(f.id) }
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var alive = Set<String>()
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
            l.position = CGPoint(x: at.x, y: at.y + l.bounds.height / 2)
            l.opacity = f.leaving ? 0.3 : 1
        }
        for p in mirror.tank.scene.presences {
            let key = "presence:" + p.id
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
            l.position = CGPoint(x: at.x, y: at.y + (above ? -1 : 1) * l.bounds.height / 2)
            l.opacity = p.alpha
        }
        for (id, l) in layers where !alive.contains(id) {
            l.removeFromSuperlayer()
            layers[id] = nil
        }
        CATransaction.commit()
    }
}
