import AppKit

/// The notch's strip (WindowModes). Left of the notch: a fish per working session (up to three, in each session's
/// own color, swimming) and how many work; with nobody working and music playing, the album's cover. Right: who
/// needs you, by name, with the answer buttons when it's a permission or a short question; or, for a few seconds,
/// who just finished; or, quiet, the name of who has been working longest. A thin light runs along the bottom while
/// anyone works. Compact (the Mac's own notch, closed, mouse away), the right side only says how many need you, so it
/// doesn't cover the menu bar's icons.
final class NotchEars: NSView {
    struct Action: Equatable {
        let label: String
        /// What Cards.decide takes: "allow", "deny", "answer:<option>".
        let action: String
    }
    struct Content: Equatable {
        var working = 0
        /// The working sessions' colors, up to three.
        var colors: [NSColor] = []
        /// The album's cover, while music plays and nobody works.
        var art: CGImage?
        var who: String?
        var whoId: String?
        var urgent = false
        var more = 0
        /// How long who needs you has been waiting, in minutes.
        var waited = 0
        /// The permission request of who needs you, answered by `actions`.
        var request: Int?
        var actions: [Action] = []
        /// Who just finished (shown a few seconds, when nobody needs you).
        var finished: String?
        /// Who has been working the longest (shown, dim, when there's nothing else to say).
        var workingName: String?
    }
    enum Hit { case strip, name, action(Int, String) }

    /// Where the notch is in this view (it moves when the strip grows to the right).
    var notchX: CGFloat = 50 { didSet { needsDisplay = true } }
    var notchWidth: CGFloat = 200
    var stripHeight: CGFloat = 32
    var open = false { didSet { needsDisplay = true; updateShimmer() } }
    /// Off: the fish stay still, no bubbles, no light along the bottom (the pulse for someone new stays).
    var animated = true {
        didSet {
            guard animated != oldValue else { return }
            fishLook = nil
            needsDisplay = true
            updateShimmer()
        }
    }
    private(set) var content = Content()
    /// The right side only says how many need you (see the class's comment).
    var compact = false {
        didSet {
            guard compact != oldValue else { return }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }
    var onClick: (Hit) -> Void = { _ in }
    var onMenu: (NSEvent) -> Void = { _ in }

    static let maxRight: CGFloat = 340
    private static let swimColor = NSColor(red: 0.45, green: 0.85, blue: 1, alpha: 1)
    private static let doneColor = NSColor(red: 0.5, green: 0.9, blue: 0.55, alpha: 1)
    private static let fishSize = NSSize(width: 17, height: 13)

    override var isFlipped: Bool { false }

    func update(_ c: Content) {
        guard c != content else { return }
        content = c
        needsDisplay = true
        updateShimmer()
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - layout

    private static func number(_ c: Content) -> NSAttributedString {
        NSAttributedString(string: c.working > 0 ? "\(c.working)" : "", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: c.working > 0 ? swimColor : NSColor.clear])
    }

    private static func fishCount(_ c: Content) -> Int { c.working > 0 ? max(1, min(3, c.colors.count)) : 1 }
    private static func showsArt(_ c: Content) -> Bool { c.art != nil && c.working == 0 }

    /// How wide the left side is (from its outer edge to the notch).
    static func leftWidth(_ c: Content) -> CGFloat {
        if showsArt(c) { return 50 }
        let n = CGFloat(fishCount(c))
        let fish = n * fishSize.width + (n - 1) * 1
        return max(50, 10 + fish + (c.working > 0 ? 4 + number(c).size().width : 0) + 10)
    }

    private struct Right {
        var width: CGFloat
        var text: NSAttributedString?
        /// Relative to the right side's left edge, and to the strip's middle (y).
        var name: NSRect = .zero
        var buttons: [(NSRect, Action)] = []
    }

    private static func label(_ t: String, _ color: NSColor, size: CGFloat = 12) -> NSAttributedString {
        NSAttributedString(string: t, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color])
    }

    /// A text alone on the right side, at most `max` wide.
    private static func only(_ t: NSAttributedString, max: CGFloat) -> Right {
        let w = min(t.size().width, max)
        return Right(width: w + 22, text: t, name: NSRect(x: 10, y: -t.size().height / 2, width: w, height: t.size().height))
    }

    private static func right(_ c: Content, compact: Bool) -> Right {
        if c.who != nil {
            if compact {
                let t = label((c.urgent ? "✕ " : "✋ ") + "\(c.more + 1)", c.urgent ? .systemRed : .systemOrange)
                return only(t, max: 60)
            }
            let t = whoText(c)
            let nameW = min(t.size().width, c.actions.isEmpty ? maxRight - 22 : 150)
            var r = Right(width: 0, text: t, name: NSRect(x: 10, y: -t.size().height / 2, width: nameW, height: t.size().height))
            var x = r.name.maxX + 8
            for a in c.actions {
                let w = buttonText(a).size().width + 14
                r.buttons.append((NSRect(x: x, y: -9, width: w, height: 18), a))
                x += w + 5
            }
            r.width = min(maxRight, (r.buttons.last?.0.maxX ?? r.name.maxX) + 12)
            return r
        }
        if let done = c.finished { return only(label(compact ? "✓" : "✓ " + done, doneColor), max: 200) }
        if !compact, let name = c.workingName { return only(label(name, NSColor(white: 1, alpha: 0.45)), max: 160) }
        return Right(width: leftWidth(c))                // nothing to say: as wide as the left, so the notch looks even
    }

    static func rightWidth(_ c: Content, compact: Bool) -> CGFloat { right(c, compact: compact).width }

    private static func whoText(_ c: Content) -> NSAttributedString {
        let s = NSMutableAttributedString(string: (c.urgent ? "✕ " : "✋ ") + (c.who ?? ""), attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: c.urgent ? NSColor.systemRed : NSColor.systemOrange])
        if c.more > 0 {
            s.append(NSAttributedString(string: "  +\(c.more)", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                                                               .foregroundColor: NSColor(white: 1, alpha: 0.55)]))
        }
        if c.waited > 0 {
            let t = c.waited < 60 ? tr("%d min", c.waited) : tr("%d h", c.waited / 60)
            s.append(NSAttributedString(string: " · " + t, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular),
                                                                     .foregroundColor: NSColor(white: 1, alpha: 0.45)]))
        }
        return s
    }

    private static func buttonText(_ a: Action) -> NSAttributedString {
        NSAttributedString(string: a.label, attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                                         .foregroundColor: a.action == "allow" ? NSColor.black : NSColor.white])
    }

    private var strip: NSRect {
        let h = open ? stripHeight : bounds.height
        return NSRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
    }
    /// The right side's origin: its left edge, at the strip's middle.
    private var rightOrigin: NSPoint { NSPoint(x: notchX + notchWidth, y: strip.midY) }
    private func placed(_ r: NSRect) -> NSRect { r.offsetBy(dx: rightOrigin.x, dy: rightOrigin.y) }

    // MARK: - clicks

    // only the strip takes clicks (open, the tank under it takes the rest)
    override func hitTest(_ point: NSPoint) -> NSView? {
        strip.contains(convert(point, from: superview)) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let r = Self.right(content, compact: compact)
        if let req = content.request, !compact, let b = r.buttons.first(where: { placed($0.0).insetBy(dx: -2, dy: -4).contains(p) }) {
            onClick(.action(req, b.1.action)); return
        }
        if content.who != nil, placed(r.name).insetBy(dx: -4, dy: -8).contains(p) { onClick(.name); return }
        onClick(.strip)
    }
    override func rightMouseDown(with event: NSEvent) { onMenu(event) }

    override func resetCursorRects() {
        let r = Self.right(content, compact: compact)
        if content.who != nil { addCursorRect(placed(r.name), cursor: .pointingHand) }
        for b in r.buttons { addCursorRect(placed(b.0), cursor: .pointingHand) }
    }

    // MARK: - drawing

    override func draw(_ dirtyRect: NSRect) {
        let c = content
        let s = strip
        let leftW = Self.leftWidth(c)
        let left = NSRect(x: notchX - leftW, y: s.minY, width: leftW, height: s.height)

        // left: the fish (layers, they swim on their own) or the cover, then how many work
        if Self.showsArt(c) {
            placeLeft(fish: [], cover: NSRect(x: left.maxX - 10 - 18, y: left.midY - 9, width: 18, height: 18))
        } else {
            let n = Self.fishCount(c), fs = Self.fishSize
            let num = Self.number(c)
            let fishW = CGFloat(n) * fs.width + CGFloat(n - 1) * 1
            let x0 = left.maxX - 10 - fishW - (c.working > 0 ? 4 + num.size().width : 0)
            let rects = (0..<n).map { i in
                NSRect(x: x0 + CGFloat(i) * (fs.width + 1), y: left.midY - fs.height / 2, width: fs.width, height: fs.height)
            }
            placeLeft(fish: rects, cover: nil)
            num.draw(at: NSPoint(x: x0 + fishW + 4, y: left.midY - num.size().height / 2))
        }

        // right: who needs you (and the answers), or who just finished
        let r = Self.right(c, compact: compact)
        guard let t = r.text else { return }
        t.draw(with: placed(r.name), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        for (rect, a) in r.buttons {
            let b = placed(rect)
            (a.action == "allow" ? Self.doneColor : NSColor(white: 1, alpha: 0.18)).setFill()
            NSBezierPath(roundedRect: b, xRadius: 9, yRadius: 9).fill()
            let bt = Self.buttonText(a), ts = bt.size()
            bt.draw(at: NSPoint(x: b.midX - ts.width / 2, y: b.midY - ts.height / 2))
        }
    }

    // MARK: - the fish

    private var fishLayers: [CALayer] = []
    private var coverLayer: CALayer?
    /// What the layers were made for: remade only when it changes (their animations keep running meanwhile).
    private var fishLook: (colors: [NSColor], working: Bool, cover: CGImage?)?

    /// The fish are layers, so Core Animation moves them on its own (nothing is redrawn): working, each swims in
    /// place, its body wagging, and lets out a bubble now and then; with nobody working one only drifts, dim.
    private func placeLeft(fish rects: [NSRect], cover: NSRect?) {
        wantsLayer = true
        guard let root = layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let working = content.working > 0
        let colors = working ? Array(content.colors.prefix(rects.count)) : []
        let art = cover != nil ? content.art : nil
        let same = fishLook.map { $0.colors == colors && $0.working == working && $0.cover === art && fishLayers.count == rects.count } ?? false
        if !same {
            fishLayers.forEach { $0.removeFromSuperlayer() }
            fishLayers = []
            coverLayer?.removeFromSuperlayer()
            coverLayer = nil
            fishLook = (colors, working, art)
            for i in rects.indices {
                let tint = working ? (colors.indices.contains(i) ? colors[i] : Self.swimColor) : NSColor(white: 1, alpha: 0.35)
                let l = Self.fishLayer(tint: tint, working: working && animated, still: !animated, phase: Double(i) * 0.37,
                                       scale: window?.backingScaleFactor ?? 2)
                root.addSublayer(l)
                fishLayers.append(l)
            }
            if let art {
                let l = CALayer()
                l.contents = art
                l.contentsGravity = .resizeAspectFill
                l.cornerRadius = 4
                l.masksToBounds = true
                root.addSublayer(l)
                coverLayer = l
            }
        }
        for (l, r) in zip(fishLayers, rects) {
            l.bounds = CGRect(origin: .zero, size: r.size)
            l.position = CGPoint(x: r.midX, y: r.midY)
        }
        if let cover, let l = coverLayer { l.frame = cover }
    }

    private static func fishLayer(tint: NSColor, working: Bool, still: Bool, phase: Double, scale: CGFloat) -> CALayer {
        let f = CALayer()
        f.contentsGravity = .resizeAspect
        f.contentsScale = scale
        f.contents = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium).applying(.init(paletteColors: [tint])))
        if still { return f }
        func loop(_ a: CABasicAnimation, _ d: Double) {
            a.duration = d; a.autoreverses = true; a.repeatCount = .infinity
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.timeOffset = phase * d                      // the shoal doesn't move in step
        }
        if working {
            let wag = CABasicAnimation(keyPath: "transform.rotation.z")
            wag.fromValue = -0.16; wag.toValue = 0.16
            loop(wag, 0.32)
            f.add(wag, forKey: "wag")
            let dart = CABasicAnimation(keyPath: "position.x")
            dart.byValue = 2.5
            loop(dart, 0.9)
            f.add(dart, forKey: "dart")
            // a bubble from the mouth, every couple of seconds
            let b = CALayer()
            b.bounds = CGRect(x: 0, y: 0, width: 3, height: 3)
            b.cornerRadius = 1.5
            b.borderWidth = 0.8
            b.borderColor = tint.withAlphaComponent(0.9).cgColor
            b.position = CGPoint(x: fishSize.width + 1, y: fishSize.height * 0.6)
            b.opacity = 0
            f.addSublayer(b)
            let rise = CABasicAnimation(keyPath: "position.y")
            rise.byValue = 9
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            fade.keyTimes = [0, 0.2, 1]
            let g = CAAnimationGroup()
            g.animations = [rise, fade]
            g.duration = 0.9
            let every = CAAnimationGroup()
            every.animations = [g]
            every.duration = 2.3
            every.repeatCount = .infinity
            every.timeOffset = phase * 2.3
            b.add(every, forKey: "bubble")
        } else {
            let bob = CABasicAnimation(keyPath: "position.y")
            bob.byValue = 1.5
            loop(bob, 1.8)
            f.add(bob, forKey: "bob")
        }
        return f
    }

    // MARK: - the light along the bottom

    private var shimmer: CAGradientLayer?

    /// While anyone works and the notch is closed: a soft light runs along its bottom edge, over and over.
    private func updateShimmer() {
        let on = content.working > 0 && !open && animated
        guard on != (shimmer != nil) || on else { return }
        wantsLayer = true
        guard let root = layer else { return }
        if !on { shimmer?.removeFromSuperlayer(); shimmer = nil; return }
        let g = shimmer ?? {
            let g = CAGradientLayer()
            g.startPoint = CGPoint(x: 0, y: 0.5)
            g.endPoint = CGPoint(x: 1, y: 0.5)
            let c = Self.swimColor
            g.colors = [c.withAlphaComponent(0).cgColor, c.withAlphaComponent(0.85).cgColor, c.withAlphaComponent(0).cgColor]
            g.locations = [-0.3, -0.15, 0]
            let a = CABasicAnimation(keyPath: "locations")
            a.fromValue = [-0.3, -0.15, 0]
            a.toValue = [1, 1.15, 1.3]
            a.duration = 2.2
            a.repeatCount = .infinity
            g.add(a, forKey: "run")
            root.addSublayer(g)
            shimmer = g
            return g
        }()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        g.frame = CGRect(x: 12, y: 0.5, width: max(0, bounds.width - 24), height: 1.5)
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        updateShimmer()
    }

    // MARK: - pulse

    /// Someone new needs you: a ring of light around the strip, twice.
    func pulse(urgent: Bool) {
        wantsLayer = true
        guard let layer else { return }
        let ring = CALayer()
        ring.frame = strip.insetBy(dx: 1, dy: 1)
        ring.cornerRadius = 10
        ring.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        ring.borderWidth = 1.5
        ring.borderColor = (urgent ? NSColor.systemRed : NSColor.systemOrange).cgColor
        ring.opacity = 0
        layer.addSublayer(ring)
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, 1, 0.15, 1, 0]
        a.duration = 1.6
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(a, forKey: "pulse")
        CATransaction.commit()
    }
}
