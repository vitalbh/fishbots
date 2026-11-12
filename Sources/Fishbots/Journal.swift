import AppKit
import CoreGraphics

/// What happened in the aquarium (for the "Enquanto você estava fora" summary).
struct Happening: Codable {
    enum Kind: String, Codable { case done, error, waiting, merge, event }
    let when: Date
    let kind: Kind
    let label: String
    let fishId: String?
}

final class Journal {
    private(set) var items: [Happening] = []
    /// When you left (no Mac activity for 10 min); nil if you're here.
    private(set) var awaySince: Date?
    /// Summary ready to show when you come back.
    private(set) var pending: (since: Date, until: Date)?
    var returned: (() -> Void)?
    private var timer: Timer?
    private let limit: TimeInterval = 600 * Tank.scale

    init() {
        // the last day's happenings come back when the app reopens ("what happened today?" still has an answer)
        let day = Date().addingTimeInterval(-86400)
        if let d = try? Data(contentsOf: Self.url), let saved = try? JSONDecoder().decode([Happening].self, from: d) {
            items = saved.filter { $0.when > day }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.gaze() }
    }

    /// Where the day's happenings are kept between runs.
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fishbots/journal.json")
    }
    private var saveAt: DispatchWorkItem?

    /// Writes the last day to disk, a few seconds after the last thing that happened (or right now, on quitting).
    func save(now: Bool = false) {
        saveAt?.cancel()
        let write = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let day = Date().addingTimeInterval(-86400)
            guard let d = try? JSONEncoder().encode(self.items.filter { $0.when > day }) else { return }
            try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? d.write(to: Self.url, options: .atomic)
        }
        saveAt = write
        if now { write.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: write) }
    }

    func record(_ kind: Happening.Kind, _ label: String, fish: String? = nil) {
        items.append(Happening(when: Date(), kind: kind, label: label, fishId: fish))
        let day = Date().addingTimeInterval(-86400)
        if items.count > 2000 { items.removeAll { $0.when < day } }
        save()
    }

    /// What happened since `since`, for GET /journal and the assistant: when, what, and whose.
    func json(since: Date) -> Data {
        let f = ISO8601DateFormatter()
        let list: [[String: Any]] = items.filter { $0.when >= since }.map {
            ["when": f.string(from: $0.when), "kind": $0.kind.rawValue, "label": $0.label, "fish": $0.fishId ?? ""]
        }
        return (try? JSONSerialization.data(withJSONObject: ["journal": list], options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    func between(_ a: Date, _ b: Date) -> [Happening] { items.filter { $0.when >= a && $0.when <= b } }

    func discardPending() { pending = nil }

    /// Tempo sem teclado nem mouse.
    private var idle: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private func gaze() {
        let o = idle
        if awaySince == nil, o > limit {
            awaySince = Date().addingTimeInterval(-o)
        } else if let since = awaySince, o < 5 {
            awaySince = nil
            // only worth showing if something happened
            if !between(since, Date()).isEmpty {
                pending = (since, Date())
                returned?()
            }
        }
    }

    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m < 60 { return "\(max(1, m)) min" }
        return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h\(String(format: "%02d", m % 60))"
    }

    /// The summary as text, grouped.
    func text(_ list: [Happening]) -> [String] {
        func names(_ t: Happening.Kind) -> [String] {
            var seen = Set<String>(), out: [String] = []
            for a in list where a.kind == t && !seen.contains(a.label) { seen.insert(a.label); out.append(a.label) }
            return out
        }
        func joinList(_ l: [String]) -> String { l.count <= 3 ? l.joined(separator: ", ") : l.prefix(3).joined(separator: ", ") + tr(" e mais %d", l.count - 3) }
        var lines: [String] = []
        let t = list.filter { $0.kind == .done }.count
        if t > 0 { lines.append(tr(t == 1 ? "✓ %d tarefa terminou: %@" : "✓ %d tarefas terminaram: %@", t, joinList(names(.done)))) }
        let e = names(.error)
        if !e.isEmpty { lines.append(tr("✗ %d com erro: %@", e.count, joinList(e))) }
        let w = names(.waiting)
        if !w.isEmpty { lines.append(tr(w.count == 1 ? "✋ %d ficou esperando você: %@" : "✋ %d ficaram esperando você: %@", w.count, joinList(w))) }
        let m = names(.merge)
        if !m.isEmpty { lines.append(tr(m.count == 1 ? "🎉 %d PR mergeado: %@" : "🎉 %d PRs mergeados: %@", m.count, joinList(m))) }
        let ev = names(.event)
        if !ev.isEmpty { lines.append("🍤 \(joinList(ev))") }
        return lines.isEmpty ? [tr("Nada de novo. O aquário ficou tranquilo.")] : lines
    }
}

/// The summary card, on top of the aquarium: a logbook. A header (title, the time range, a close button), a
/// scoreboard of what mattered (tasks done, errors, waiting for you, merged PRs) and a timeline of what happened,
/// newest first, each with its time, a dot in its fish's color and an icon.
final class SummaryView: NSView {
    var close: (() -> Void)?
    private let w: CGFloat = 460

    init(title: String, since: Date, until: Date, list: [Happening], color: (String?) -> NSColor?) {
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        layer?.masksToBounds = true
        let bg = CAGradientLayer()
        bg.colors = [NSColor(calibratedRed: 0.05, green: 0.16, blue: 0.22, alpha: 0.95).cgColor,
                     NSColor(calibratedRed: 0.02, green: 0.06, blue: 0.11, alpha: 0.95).cgColor]
        bg.startPoint = CGPoint(x: 0.5, y: 1); bg.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(bg)
        gradient = bg

        func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .white, mono: Bool = false) -> NSTextField {
            let t = NSTextField(labelWithString: s)
            t.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : rounded(size, weight)
            t.textColor = color
            t.lineBreakMode = .byTruncatingTail
            return t
        }

        // header: an icon, the title and the time range; a close button
        let icon = NSImageView(image: NSImage(systemSymbolName: "water.waves", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .semibold)) ?? NSImage())
        icon.contentTintColor = NSColor(calibratedRed: 0.45, green: 0.9, blue: 0.95, alpha: 1)
        let fmt = DateFormatter(); fmt.timeStyle = .short; fmt.dateStyle = .none; fmt.locale = L10n.locale
        let head = NSStackView(views: [label(title, 16, .semibold), label(fmt.string(from: since) + " – " + fmt.string(from: until), 11, .medium, NSColor(white: 1, alpha: 0.5))])
        head.orientation = .vertical; head.alignment = .leading; head.spacing = 2
        let x = ClosureButton { [weak self] in self?.close?() }
        x.isBordered = false
        x.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: tr("Fechar"))?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
        x.contentTintColor = NSColor(white: 1, alpha: 0.45)
        x.keyEquivalent = "\u{1b}"
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let top = NSStackView(views: [icon, head, spacer, x])
        top.alignment = .centerY; top.spacing = 10
        top.widthAnchor.constraint(equalToConstant: w).isActive = true
        var views: [NSView] = [top]

        // the scoreboard
        func unique(_ k: Happening.Kind) -> Int { Set(list.filter { $0.kind == k }.map(\.label)).count }
        let tiles: [(Int, String, String, NSColor)] = [
            (list.filter { $0.kind == .done }.count, "checkmark.circle.fill", tr("terminadas"), .systemGreen),
            (unique(.error), "xmark.octagon.fill", tr("com erro"), .systemRed),
            (unique(.waiting), "hand.raised.fill", tr("esperaram você"), .systemOrange),
            (unique(.merge), "party.popper.fill", tr("PRs mergeados"), .systemPurple),
        ].filter { $0.0 > 0 }
        if !tiles.isEmpty {
            let row = NSStackView(views: tiles.map { n, sym, name, c in
                let num = label("\(n)", 24, .bold, c)
                let ic = NSImageView(image: NSImage(systemSymbolName: sym, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold)) ?? NSImage())
                ic.contentTintColor = c
                let line = NSStackView(views: [ic, label(name, 11, .medium, NSColor(white: 1, alpha: 0.7))])
                line.spacing = 4
                let box = NSStackView(views: [num, line])
                box.orientation = .vertical; box.alignment = .leading; box.spacing = 0
                box.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 10, right: 12)
                box.wantsLayer = true
                box.layer?.backgroundColor = c.withAlphaComponent(0.13).cgColor
                box.layer?.cornerRadius = 10
                box.layer?.borderWidth = 1
                box.layer?.borderColor = c.withAlphaComponent(0.25).cgColor
                return box
            })
            row.distribution = .fillEqually
            row.spacing = 8
            row.widthAnchor.constraint(equalToConstant: w).isActive = true
            views.append(row)
        }

        // the timeline, newest first
        let shown = list.filter { $0.kind != .event || list.count < 12 }.reversed().prefix(10)
        if shown.isEmpty {
            let calm = label(tr("🫧  Nada de novo. O aquário ficou tranquilo."), 13, .medium, NSColor(white: 1, alpha: 0.75))
            let box = NSStackView(views: [calm])
            box.edgeInsets = NSEdgeInsets(top: 18, left: 14, bottom: 18, right: 14)
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor(white: 1, alpha: 0.05).cgColor
            box.layer?.cornerRadius = 10
            box.widthAnchor.constraint(equalToConstant: w).isActive = true
            views.append(box)
        } else {
            let line = NSBox(); line.boxType = .separator
            line.widthAnchor.constraint(equalToConstant: w).isActive = true
            views.append(line)
            let kindIcon: [Happening.Kind: (String, NSColor)] = [.done: ("✓", .systemGreen), .error: ("✗", .systemRed), .waiting: ("✋", .systemOrange),
                                                                 .merge: ("🎉", .systemPurple), .event: ("🍤", NSColor(white: 1, alpha: 0.6))]
            for h in shown {
                let time = label(fmt.string(from: h.when), 11, .regular, NSColor(white: 1, alpha: 0.4), mono: true)
                time.widthAnchor.constraint(equalToConstant: 66).isActive = true
                let dot = NSView()
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 4
                dot.layer?.backgroundColor = (color(h.fishId) ?? kindIcon[h.kind]!.1).cgColor
                dot.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([dot.widthAnchor.constraint(equalToConstant: 8), dot.heightAnchor.constraint(equalToConstant: 8)])
                let (ch, c) = kindIcon[h.kind]!
                let mark = label(ch, 12, .bold, c)
                mark.widthAnchor.constraint(equalToConstant: 18).isActive = true
                let name = label(h.label, 13, .regular, NSColor(white: 1, alpha: 0.88))
                name.setContentCompressionResistancePriority(.init(1), for: .horizontal)
                let r = NSStackView(views: [time, dot, mark, name])
                r.spacing = 8; r.alignment = .centerY
                r.widthAnchor.constraint(equalToConstant: w).isActive = true
                views.append(r)
            }
            if list.count > shown.count {
                views.append(label(tr("+ %d antes disso", list.count - shown.count), 11, .medium, NSColor(white: 1, alpha: 0.4)))
            }
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(14, after: top)
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        shadow = { let s = NSShadow(); s.shadowBlurRadius = 24; s.shadowColor = NSColor.black.withAlphaComponent(0.5); return s }()
    }
    private var gradient: CAGradientLayer?
    override func layout() { super.layout(); gradient?.frame = bounds }
    required init?(coder: NSCoder) { fatalError() }
}
