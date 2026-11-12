import AppKit

/// What a session has been doing, drawn: its latest steps (Fish.history) as beads on a line, oldest at the left and
/// "now" at the right, each a small icon colored by what kind of step it was (reading, editing, running, the web, a
/// sub-agent, its list, or what it was told, in the fish's own color). While it works, a light runs along the line
/// toward "now" and the last bead breathes; a step that just happened pops in. Hovering a bead tells its time and
/// what the session said about it. Used by the fish's card and by the notch's peek.
final class StepTrail: NSView {
    struct Step {
        let when: Date
        let name: String
        let said: String?
    }

    private let steps: [Step]
    private let busy: Bool
    private let tint: NSColor
    private let animated: Bool
    /// Mini: a thin row (the open notch's band): smaller beads, no times under the line.
    private let mini: Bool
    static let height: CGFloat = 40
    static let miniHeight: CGFloat = 20
    private var beadSize: CGFloat { mini ? 14 : 18 }

    /// `animated` off: everything stays still (the notch's "animations" setting, or macOS's Reduce motion).
    init(steps: [Step], busy: Bool, tint: NSColor, width: CGFloat, mini: Bool = false,
         animated: Bool = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
        self.mini = mini
        // the same step several times in a row, with nothing said, is one bead
        var merged: [Step] = []
        for s in steps {
            if s.said == nil, let last = merged.last, last.name == s.name, last.said == nil { merged[merged.count - 1] = s; continue }
            merged.append(s)
        }
        let fit = max(2, Int((width - 30) / ((mini ? 14 : 18) + 5)))
        self.steps = Array(merged.suffix(fit))
        self.busy = busy
        self.tint = tint
        self.animated = animated
        let h = mini ? Self.miniHeight : Self.height
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: h))
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: h).isActive = true
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    // MARK: - kinds of step

    private struct Look { let symbol: String; let color: NSColor }

    private func look(_ name: String) -> Look {
        if name == Fish.toldMark { return Look(symbol: "text.bubble.fill", color: tint.blended(withFraction: 0.3, of: .white) ?? tint) }
        let n = name.lowercased()
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }
        if n.hasPrefix("mcp") { return Look(symbol: "puzzlepiece.fill", color: NSColor(red: 0.75, green: 0.6, blue: 1, alpha: 1)) }
        if has("todo", "plan") { return Look(symbol: "checklist", color: NSColor(red: 0.95, green: 0.9, blue: 0.5, alpha: 1)) }
        if has("edit", "write", "patch", "replace", "notebook") { return Look(symbol: "pencil", color: NSColor(red: 1, green: 0.74, blue: 0.35, alpha: 1)) }
        if has("bash", "shell", "exec", "command", "kill", "run") { return Look(symbol: "terminal.fill", color: NSColor(red: 0.45, green: 0.9, blue: 0.55, alpha: 1)) }
        if has("web", "fetch", "url", "browser") { return Look(symbol: "globe", color: NSColor(red: 0.35, green: 0.85, blue: 0.9, alpha: 1)) }
        if has("task", "agent", "spawn") && !has("todo") { return Look(symbol: "person.2.fill", color: NSColor(red: 1, green: 0.55, blue: 0.75, alpha: 1)) }
        if has("grep", "glob", "search", "find", "ls", "list") { return Look(symbol: "magnifyingglass", color: NSColor(red: 0.55, green: 0.75, blue: 1, alpha: 1)) }
        if has("read", "view", "open", "cat") { return Look(symbol: "doc.text.fill", color: NSColor(red: 0.55, green: 0.75, blue: 1, alpha: 1)) }
        return Look(symbol: "circle.fill", color: NSColor(white: 0.75, alpha: 1))
    }

    // MARK: - building

    private func build() {
        guard let root = layer else { return }
        let w = bounds.width
        let y = mini ? bounds.height / 2 : bounds.height - 6 - beadSize / 2   // the line, near the top; times under it
        let left: CGFloat = 4 + beadSize / 2, right = w - 6
        let n = steps.count
        // working: room between the last bead and "now", where the light runs to
        let lastX = right - (busy ? 30 : beadSize / 2)
        let gap = n > 1 ? min(beadSize + 12, (lastX - left) / CGFloat(n - 1)) : 0
        let xs = (0..<n).map { left + CGFloat($0) * gap }
        let end = busy ? right : (xs.last ?? left)

        // the line, from the first bead to "now"
        let line = CALayer()
        line.frame = CGRect(x: left, y: y - 0.75, width: max(0, end - left), height: 1.5)
        line.backgroundColor = NSColor(white: 1, alpha: 0.18).cgColor
        line.cornerRadius = 0.75
        root.addSublayer(line)

        // working: a light runs along the line toward "now", and "now" is a soft dot at the end
        if busy {
            let runner = CAGradientLayer()
            runner.frame = line.frame
            runner.startPoint = CGPoint(x: 0, y: 0.5)
            runner.endPoint = CGPoint(x: 1, y: 0.5)
            let c = tint.blended(withFraction: 0.35, of: .white) ?? tint
            runner.colors = [c.withAlphaComponent(0).cgColor, c.withAlphaComponent(0.9).cgColor, c.withAlphaComponent(0).cgColor]
            runner.locations = [0.75, 0.88, 1]
            if animated {
                let a = CABasicAnimation(keyPath: "locations")
                a.fromValue = [-0.25, -0.12, 0]
                a.toValue = [1, 1.12, 1.25]
                a.duration = 1.8
                a.repeatCount = .infinity
                runner.add(a, forKey: "run")
            }
            root.addSublayer(runner)
            let now = CALayer()
            now.frame = CGRect(x: right - 3, y: y - 3, width: 6, height: 6)
            now.cornerRadius = 3
            now.backgroundColor = c.cgColor
            if animated {
                let b = CABasicAnimation(keyPath: "opacity")
                b.fromValue = 1; b.toValue = 0.25
                b.duration = 0.7; b.autoreverses = true; b.repeatCount = .infinity
                now.add(b, forKey: "blink")
            }
            root.addSublayer(now)
        }

        // the beads
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        for (i, s) in steps.enumerated() {
            let lk = look(s.name)
            let r = CGRect(x: xs[i] - beadSize / 2, y: y - beadSize / 2, width: beadSize, height: beadSize)
            let b = CALayer()
            b.frame = r
            b.cornerRadius = beadSize / 2
            b.backgroundColor = lk.color.withAlphaComponent(0.22).cgColor
            b.borderColor = lk.color.withAlphaComponent(0.85).cgColor
            b.borderWidth = 1
            let icon = CALayer()
            icon.frame = b.bounds.insetBy(dx: mini ? 3 : 4, dy: mini ? 3 : 4)
            icon.contentsGravity = .resizeAspect
            icon.contentsScale = scale
            icon.contents = NSImage(systemSymbolName: lk.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold).applying(.init(paletteColors: [lk.color])))
            b.addSublayer(icon)
            root.addSublayer(b)
            let last = i == n - 1
            if animated && last && busy {
                // the step it's on breathes
                let a = CABasicAnimation(keyPath: "transform.scale")
                a.fromValue = 1; a.toValue = 1.18
                a.duration = 0.6; a.autoreverses = true; a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                b.add(a, forKey: "breathe")
            }
            if animated && Date().timeIntervalSince(s.when) < 1.5 {
                // just happened: it pops in
                let p = CASpringAnimation(keyPath: "transform.scale")
                p.fromValue = 0.2; p.toValue = 1
                p.damping = 9
                p.duration = p.settlingDuration
                b.add(p, forKey: "pop")
            }
            addToolTip(r, owner: tip(s) as NSString, userData: nil)
        }

        // under the line: how long ago it starts, and "now" (not in the mini row)
        if mini { return }
        let rightText = busy ? tr("agora") : Self.ago(steps.last?.when ?? Date())
        if let first = steps.first, Self.ago(first.when) != rightText {
            addLabel(Self.ago(first.when), x: max(0, (xs.first ?? left) - beadSize / 2), align: .left)
        }
        addLabel(rightText, x: w - 2, align: .right)
    }

    private func addLabel(_ s: String, x: CGFloat, align: NSTextAlignment) {
        let t = CATextLayer()
        t.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        t.string = NSAttributedString(string: s, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular),
                                                             .foregroundColor: NSColor(white: 1, alpha: 0.4)])
        let w = (t.string as! NSAttributedString).size().width + 2
        t.frame = CGRect(x: align == .right ? x - w : x, y: 0, width: w, height: 13)
        layer?.addSublayer(t)
    }

    private func tip(_ s: Step) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        let name = s.name == Fish.toldMark ? tr("você disse") : s.name
        return f.string(from: s.when) + "  " + name + (s.said.map { "\n" + $0 } ?? "")
    }

    static func ago(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return tr("agora") }
        if s < 3600 { return tr("%d min", Int(s / 60)) }
        return tr("%d h", Int(s / 3600))
    }

    /// A fish's steps, as the trail takes them.
    static func steps(of f: Fish) -> [Step] { f.history.map { Step(when: $0.when, name: $0.name, said: $0.said) } }
}
