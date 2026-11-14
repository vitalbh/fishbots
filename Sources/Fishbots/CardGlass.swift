import AppKit
import Metal
import QuartzCore
import simd

// What makes a fish's card a piece of the aquarium: the fish behind a round window, the water's surface between the
// card's parts, the context as a water level, and bubbles going up the glass.

/// The fish behind a round window, rimmed in its color.
final class Porthole: NSView {
    static let size = NSSize(width: 84, height: 56)

    init(image: CGImage?, tint: NSColor) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: Self.size.width), heightAnchor.constraint(equalToConstant: Self.size.height)])
        guard let layer else { return }
        layer.cornerRadius = Self.size.height / 2
        layer.masksToBounds = true
        layer.borderWidth = 1.5
        layer.borderColor = tint.withAlphaComponent(0.6).cgColor
        // water until the picture is drawn (and behind it)
        let water = CAGradientLayer()
        water.frame = bounds
        water.colors = [NSColor(red: 0.09, green: 0.24, blue: 0.27, alpha: 1).cgColor, NSColor(red: 0.05, green: 0.14, blue: 0.17, alpha: 1).cgColor]
        layer.addSublayer(water)
        if let image {
            let picture = CALayer()
            picture.frame = bounds
            picture.contents = image
            picture.contentsGravity = .resizeAspectFill
            layer.addSublayer(picture)
        }
        // the glass: a little light from above
        let shine = CAGradientLayer()
        shine.frame = bounds
        shine.colors = [NSColor.white.withAlphaComponent(0.16).cgColor, NSColor.clear.cgColor]
        shine.locations = [0, 0.55]
        shine.startPoint = CGPoint(x: 0.5, y: 1)
        shine.endPoint = CGPoint(x: 0.5, y: 0)
        layer.addSublayer(shine)
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// The water's surface, as a thin line of little waves: what separates the card's parts.
final class WaveLine: NSView {
    private let tint: NSColor

    init(width: CGFloat, tint: NSColor) {
        self.tint = tint
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 7))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: width), heightAnchor.constraint(equalToConstant: 7)])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        let mid = bounds.midY, amp: CGFloat = 1.6, length: CGFloat = 22
        path.move(to: NSPoint(x: 0, y: mid))
        var x: CGFloat = 0
        while x < bounds.width {
            x += 2
            path.line(to: NSPoint(x: x, y: mid + sin(x / length * 2 * .pi) * amp))
        }
        path.lineWidth = 1
        tint.withAlphaComponent(0.38).setStroke()
        path.stroke()
    }
}

/// How full the context is, as water in a glass tube: its color turns amber, then red, as it fills up.
final class WaterGauge: NSView {
    private let level: CGFloat
    private let tint: NSColor

    init(level: CGFloat, tint: NSColor) {
        self.level = max(0, min(1, level))
        self.tint = tint
        super.init(frame: NSRect(x: 0, y: 0, width: 120, height: 12))
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 12).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let tube = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.white.withAlphaComponent(0.07).setFill()
        tube.fill()
        NSGraphicsContext.saveGraphicsState()
        tube.addClip()
        let water: NSColor = level > 0.9 ? .systemRed : level > 0.7 ? .systemOrange : tint
        let w = max(bounds.height, bounds.width * level)
        // the water's edge is a little wave
        let fill = NSBezierPath()
        fill.move(to: NSPoint(x: 0, y: 0))
        fill.line(to: NSPoint(x: w, y: 0))
        var y: CGFloat = 0
        while y <= bounds.height {
            fill.line(to: NSPoint(x: w + sin(y / bounds.height * 2 * .pi) * 1.8, y: y))
            y += 1.5
        }
        fill.line(to: NSPoint(x: 0, y: bounds.height))
        fill.close()
        NSGradient(colors: [water.withAlphaComponent(0.95), water.blended(withFraction: 0.45, of: .white)?.withAlphaComponent(0.9) ?? water])?
            .draw(in: fill, angle: 90)
        // light along the top of the glass
        NSColor.white.withAlphaComponent(0.2).setFill()
        NSBezierPath(roundedRect: NSRect(x: 3, y: bounds.height - 4, width: bounds.width - 6, height: 1.5), xRadius: 1, yRadius: 1).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        tube.lineWidth = 1
        tube.stroke()
    }
}

/// The card's background: water in the fish's color, lighter toward the surface, light drifting through it and
/// bubbles going up along the left. It follows the card when the card grows (the whole reply, a longer field).
final class GlassView: NSView {
    private let water = CAGradientLayer()
    private var light: CALayer?
    private var bubbles: CALayer?
    private let tint: NSColor
    private let rising: Bool
    private var laidOutFor = CGSize.zero

    /// `bubbles` off: just the water and its light (a tall panel full of lines, where bubbles along the edge clutter).
    init(backdrop: NSColor, tint: NSColor, bubbles: Bool = true) {
        self.tint = tint
        self.rising = bubbles
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.backgroundColor = backdrop.cgColor
        layer?.masksToBounds = true
        water.colors = [tint.withAlphaComponent(0.26).cgColor, tint.withAlphaComponent(0.07).cgColor, NSColor.clear.cgColor]
        water.locations = [0, 0.35, 1]
        water.startPoint = CGPoint(x: 0.5, y: 1)
        water.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(water)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        guard bounds.size != laidOutFor, bounds.width > 0, bounds.height > 0 else { return }
        laidOutFor = bounds.size
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        water.frame = bounds
        // made again for the new size, behind the text: the light, then the bubbles (they rise the whole height)
        light?.removeFromSuperlayer()
        bubbles?.removeFromSuperlayer()
        let l = CardWater.light(in: bounds)
        layer?.insertSublayer(l, above: water)
        light = l
        if rising {
            let b = CardWater.bubbles(height: bounds.height, tint: tint)
            b.frame = bounds
            layer?.insertSublayer(b, above: l)
            bubbles = b
        }
        CATransaction.commit()
    }
}

enum CardWater {
    /// Light moving slowly through the water: two soft diagonal bands that drift back and forth.
    static func light(in bounds: CGRect) -> CALayer {
        let band = CAGradientLayer()
        band.frame = bounds
        band.startPoint = CGPoint(x: 0, y: 1)
        band.endPoint = CGPoint(x: 1, y: 0)
        let clear = NSColor.clear.cgColor, lit = NSColor.white.withAlphaComponent(0.055).cgColor
        band.colors = [clear, lit, clear, clear, lit, clear]
        band.locations = [0.05, 0.16, 0.27, 0.5, 0.6, 0.72]
        let drift = CABasicAnimation(keyPath: "locations")
        drift.toValue = [0.2, 0.33, 0.45, 0.62, 0.74, 0.9]
        drift.duration = 7
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        band.add(drift, forKey: "drift")
        return band
    }

    /// Bubbles going up along the left of the glass, in the fish's color.
    static func bubbles(height: CGFloat, tint: NSColor) -> CALayer {
        let e = CAEmitterLayer()
        e.emitterPosition = CGPoint(x: 10, y: 6)
        e.emitterShape = .point
        let cell = CAEmitterCell()
        cell.contents = ring(tint)
        cell.birthRate = 1.1
        cell.velocity = 15
        cell.velocityRange = 6
        cell.emissionLongitude = .pi / 2          // up
        cell.emissionRange = 0.12
        cell.lifetime = Float(max(2, (height - 14) / 15))
        cell.scale = 0.42
        cell.scaleRange = 0.2
        cell.alphaSpeed = -0.5 / cell.lifetime
        e.emitterCells = [cell]
        return e
    }

    /// One bubble: a ring with a glint.
    private static func ring(_ tint: NSColor) -> CGImage? {
        let s = 16
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let light = tint.blended(withFraction: 0.5, of: .white) ?? tint
        ctx.setStrokeColor(light.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1.6)
        ctx.strokeEllipse(in: CGRect(x: 2, y: 2, width: s - 4, height: s - 4))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.7).cgColor)
        ctx.fillEllipse(in: CGRect(x: 9, y: 9, width: 3, height: 3))
        return ctx.makeImage()
    }
}
