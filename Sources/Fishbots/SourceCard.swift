import AppKit
import simd

/// The card of a light on the side glass: everything its source keeps there (a plugin's clusters, sites, jobs), the
/// ones that need you first, each with its state's color, its text and its link. Made of the fish card's parts
/// (CardGlass.swift): the lights behind a porthole, the water's surface under the header, tinted water and bubbles.
final class SourceCard: NSViewController {
    private let source: String
    private let items: [Presence]
    private let picked: String
    private let color: (State) -> SIMD3<Float>
    /// A row was clicked (the app opens its link).
    var open: ((Presence) -> Void)?

    init(source: String, items: [Presence], picked: String, color: @escaping (State) -> SIMD3<Float>) {
        self.source = source
        // what needs you first, then by name
        func rank(_ p: Presence) -> Int { p.state == .error ? 0 : p.state == .waiting ? 1 : p.state == .alert ? 2 : 3 }
        self.items = items.sorted { (rank($0), $0.label.lowercased()) < (rank($1), $1.label.lowercased()) }
        self.picked = picked
        self.color = color
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private let width: CGFloat = 320

    private func ns(_ c: SIMD3<Float>, _ a: CGFloat = 1) -> NSColor { NSColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: a) }
    /// How the source is doing: its worst light's state (what the card's water, waves and bubbles are tinted with).
    private var mood: State {
        for s in [State.error, .waiting, .alert] where items.contains(where: { $0.state == s }) { return s }
        return items.contains { $0.state != .idle } ? .ok : .idle
    }
    private var tint: NSColor { ns(color(mood)) }
    /// Deep water with a touch of that color, as the fish's card.
    private var backdrop: NSColor {
        let navy = SIMD3<Float>(0.035, 0.065, 0.1)
        return ns(navy + (color(mood) - navy) * 0.14, 0.97)
    }

    private func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = rounded(size, weight)
        t.textColor = color
        t.lineBreakMode = .byTruncatingTail
        return t
    }

    /// The source's lights behind a porthole, as they are on the glass (the first ones, if they're many).
    private func porthole() -> NSView {
        let hole = Porthole(image: nil, tint: tint)
        let shown = Array(items.prefix(10))
        let perRow = shown.count > 5 ? 5 : max(1, shown.count)
        let rows = (shown.count + perRow - 1) / perRow
        let step: CGFloat = 13, d: CGFloat = 8
        for (i, p) in shown.enumerated() {
            let c = ns(color(p.state), p.state == .idle ? 0.55 : 1)
            let lamp = CALayer()
            let inRow = min(perRow, shown.count - (i / perRow) * perRow)
            let x = Porthole.size.width / 2 + (CGFloat(i % perRow) - CGFloat(inRow - 1) / 2) * step
            let y = Porthole.size.height / 2 + (CGFloat(rows - 1) / 2 - CGFloat(i / perRow)) * step
            lamp.frame = CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d)
            lamp.cornerRadius = d / 2
            lamp.backgroundColor = c.cgColor
            lamp.borderWidth = 1
            lamp.borderColor = NSColor(red: 0.72, green: 0.6, blue: 0.38, alpha: 0.8).cgColor
            lamp.shadowColor = c.cgColor
            lamp.shadowOpacity = p.state == .idle ? 0 : 1
            lamp.shadowRadius = p.needsYou ? 5 : 3
            lamp.shadowOffset = .zero
            if p.needsYou {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1; pulse.toValue = 0.45
                pulse.duration = 0.8; pulse.autoreverses = true; pulse.repeatCount = .infinity
                lamp.add(pulse, forKey: "pulse")
            }
            hole.layer?.addSublayer(lamp)
        }
        return hole
    }

    /// A rounded little label with a tint, as the fish card's state.
    private func pill(_ s: String, _ color: NSColor) -> NSView {
        let box = NSStackView(views: [label(s, 11, .semibold, color)])
        box.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        box.wantsLayer = true
        box.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        box.layer?.cornerRadius = 9
        return box
    }

    private func row(_ p: Presence) -> NSView {
        let c = color(p.state)
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4.5
        dot.layer?.backgroundColor = ns(c, p.state == .idle ? 0.6 : 1).cgColor
        dot.layer?.shadowColor = ns(c).cgColor
        dot.layer?.shadowOpacity = p.state == .idle ? 0 : 0.9
        dot.layer?.shadowRadius = 4
        dot.layer?.shadowOffset = .zero
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 9), dot.heightAnchor.constraint(equalToConstant: 9)])
        let name = label(p.label + (p.link != nil ? " ↗" : ""), 12.5, .medium, NSColor(white: 1, alpha: 0.92))
        let text = NSStackView(views: [name])
        text.orientation = .vertical; text.alignment = .leading; text.spacing = 1
        if let d = p.detail ?? (p.state == .ok ? nil : p.state.label) {
            let detail = NSTextField(wrappingLabelWithString: d)
            detail.font = rounded(11)
            detail.textColor = p.needsYou ? (ns(c).blended(withFraction: 0.25, of: .white) ?? ns(c)) : NSColor(white: 1, alpha: 0.5)
            detail.maximumNumberOfLines = p.needsYou ? 4 : 1
            detail.lineBreakMode = p.needsYou ? .byWordWrapping : .byTruncatingTail
            detail.preferredMaxLayoutWidth = width - 44
            detail.isSelectable = false
            text.addArrangedSubview(detail)
        }
        let row = NSStackView(views: [dot, text])
        row.spacing = 9
        row.alignment = .top
        row.edgeInsets = NSEdgeInsets(top: 5, left: 8, bottom: 5, right: 8)
        dot.topAnchor.constraint(equalTo: row.topAnchor, constant: 9.5).isActive = true
        row.wantsLayer = true
        row.layer?.cornerRadius = 7
        // the one in trouble on a patch of its color; the one you clicked, a little lighter
        if p.needsYou { row.layer?.backgroundColor = ns(c, 0.13).cgColor }
        else if p.id == picked { row.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor }
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        if p.link != nil {
            // the whole row opens its link
            let b = ClosureButton { [weak self] in self?.open?(p) }
            b.isBordered = false
            b.title = ""
            b.isTransparent = true
            b.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(b)
            NSLayoutConstraint.activate([b.leadingAnchor.constraint(equalTo: row.leadingAnchor), b.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                                         b.topAnchor.constraint(equalTo: row.topAnchor), b.bottomAnchor.constraint(equalTo: row.bottomAnchor)])
        }
        return row
    }

    override func loadView() {
        // the header: the lights behind a porthole, whose they are, and how they are
        let needing = items.filter(\.needsYou).count
        let title = NSStackView(views: [label(source, 15, .semibold, .labelColor),
                                        label(tr("%@ luzes no vidro", "\(items.count)"), 10.5, .regular, .tertiaryLabelColor)])
        title.orientation = .vertical; title.alignment = .leading; title.spacing = 2
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let state = needing > 0 ? pill(tr("%@ pedem atenção", "\(needing)"), mood == .error ? .systemRed : .systemOrange)
                                : pill(tr("tudo certo"), mood == .idle ? .secondaryLabelColor : .systemGreen)
        let head = NSStackView(views: [porthole(), title, spacer, state])
        head.spacing = 10
        head.alignment = .top
        head.widthAnchor.constraint(equalToConstant: width).isActive = true

        let list = NSStackView(views: items.map(row))
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 2
        var body: NSView = list
        // many lights: the list scrolls
        let fit = list.fittingSize
        if fit.height > 380 {
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            let doc = FlippedView(frame: NSRect(origin: .zero, size: fit))
            list.frame = doc.bounds
            list.translatesAutoresizingMaskIntoConstraints = true
            doc.addSubview(list)
            scroll.documentView = doc
            scroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: width), scroll.heightAnchor.constraint(equalToConstant: 380)])
            body = scroll
        }
        let stack = NSStackView(views: [head, WaveLine(width: width, tint: tint), body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 22, bottom: 14, right: 18)
        stack.widthAnchor.constraint(equalToConstant: width + 40).isActive = true

        // a piece of the aquarium behind glass, as the fish's card: tinted water, drifting light, bubbles up the left
        let bg = GlassView(backdrop: backdrop, tint: tint)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor), stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bg.topAnchor), stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        bg.layoutSubtreeIfNeeded()
        bg.frame = NSRect(origin: .zero, size: bg.fittingSize)
        view = bg
    }

    /// The popover's own frame (and its arrow) in the same color, so the whole bubble is dark glass.
    override func viewWillAppear() {
        super.viewWillAppear()
        if let frame = view.window?.contentView?.superview {
            frame.wantsLayer = true
            frame.layer?.backgroundColor = backdrop.cgColor
        }
    }
}

/// A view that lays out from the top (a scrolling list starts at its first row).
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
