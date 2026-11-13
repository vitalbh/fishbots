import AppKit

/// What the summary's lines do.
struct SummaryActions {
    /// Opens the session's card (closing the summary).
    var open: (Fish) -> Void = { _ in }
    /// Takes you to its pane or terminal.
    var go: (Fish) -> Void = { _ in }
    var canGo: (Fish) -> Bool = { _ in false }
    /// Opens a plugin's link (a pull request, a deploy).
    var link: (String) -> Void = { _ in }
    /// Asks the resident assistant to tell it in words (nil: there's no assistant).
    var tell: ((SummaryRange) -> Void)?
    /// The range changed: the fish it talks about come forward.
    var shown: (Digest, SummaryRange) -> Void = { _, _ in }
}

/// The summary that opens from the treasure chest: a card of dark glass over the water, like a fish's card. On top,
/// the range (since you left, today) and one line that says it all in colored numbers; then, each in its own color,
/// who waits for you and for what, what broke, what got done by project, what still runs and how far along. Every
/// line about a session shows that fish, small, and opens its card; the arrow beside goes to its pane. Long lists
/// show their first lines and the rest a click away.
final class SummaryView: NSView {
    var close: (() -> Void)?
    /// How long you were away (for "since you left").
    private let awayFor: TimeInterval?
    private(set) var range: SummaryRange
    private(set) var digest: Digest
    private let ranges: [SummaryRange]
    private let make: (SummaryRange) -> Digest
    private let actions: SummaryActions
    private let maxHeight: CGFloat
    private var expanded = Set<String>()
    /// Too tall for the window: fewer tasks per project and fewer projects before "+ more", before anything scrolls.
    private var compact = false
    private let w: CGFloat = 468
    private let clip = NSView()
    private var body: NSView?

    static let orange = NSColor(red: 1, green: 0.7, blue: 0.32, alpha: 1)
    static let red = NSColor(red: 1, green: 0.46, blue: 0.42, alpha: 1)
    static let green = NSColor(red: 0.45, green: 0.9, blue: 0.62, alpha: 1)
    static let teal = NSColor(red: 0.42, green: 0.85, blue: 0.96, alpha: 1)
    static let violet = NSColor(red: 0.76, green: 0.64, blue: 1, alpha: 1)
    private static let backdrop = NSColor(red: 0.035, green: 0.07, blue: 0.105, alpha: 0.97)
    private static let water = NSColor(red: 0.3, green: 0.72, blue: 0.82, alpha: 1)

    init(range: SummaryRange, ranges: [SummaryRange], awayFor: TimeInterval?, maxHeight: CGFloat, actions: SummaryActions,
         make: @escaping (SummaryRange) -> Digest) {
        self.range = range
        self.awayFor = awayFor
        self.ranges = ranges
        self.make = make
        self.actions = actions
        self.maxHeight = maxHeight
        self.digest = make(range)
        super.init(frame: .zero)
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        // the shadow on the outside, the glass clipped round inside it (a clipped layer can't cast a round shadow)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.55
        layer?.shadowRadius = 22
        layer?.shadowOffset = CGSize(width: 0, height: -6)
        clip.wantsLayer = true
        clip.layer?.cornerRadius = 18
        clip.layer?.masksToBounds = true
        clip.layer?.borderWidth = 1
        clip.layer?.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
        clip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clip)
        NSLayoutConstraint.activate([
            clip.leadingAnchor.constraint(equalTo: leadingAnchor), clip.trailingAnchor.constraint(equalTo: trailingAnchor),
            clip.topAnchor.constraint(equalTo: topAnchor), clip.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        render()
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 18, cornerHeight: 18, transform: nil)
    }

    // MARK: - opening and closing

    /// It rises from below, as if out of the chest, and settles.
    func appear() {
        guard let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = 0.22
        let rise = CASpringAnimation(keyPath: "transform")
        rise.fromValue = CATransform3DScale(CATransform3DMakeTranslation(0, -26, 0), 0.97, 0.97, 1)
        rise.toValue = CATransform3DIdentity
        rise.damping = 16; rise.stiffness = 170; rise.mass = 1
        rise.duration = rise.settlingDuration
        layer.add(fade, forKey: "fade")
        layer.add(rise, forKey: "rise")
    }

    /// Fades away, then goes.
    func dismiss(_ then: @escaping () -> Void) {
        guard let layer, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { then(); return }
        CATransaction.begin()
        CATransaction.setCompletionBlock(then)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.14
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "out")
        CATransaction.commit()
    }

    // MARK: - building

    private func render() {
        body?.removeFromSuperview()
        let glass = GlassView(backdrop: Self.backdrop, tint: Self.water, bubbles: false)
        glass.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: clip.leadingAnchor), glass.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            glass.topAnchor.constraint(equalTo: clip.topAnchor), glass.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
        ])
        body = glass

        let top = header()
        let sections = NSStackView(views: digest.quiet ? calm() : content())
        sections.orientation = .vertical
        sections.alignment = .leading
        sections.spacing = 4
        let foot = footer()

        let stack = NSStackView(views: [top, sections] + (foot.map { [$0] } ?? []))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        glass.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: glass.leadingAnchor), stack.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
            stack.topAnchor.constraint(equalTo: glass.topAnchor), stack.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
        ])
        // taller than the window allows: first tighter, then the sections scroll (the header and the footer stay)
        let total = stack.fittingSize.height
        if total > maxHeight && !compact && expanded.isEmpty {
            compact = true
            render()
            return
        }
        if total > maxHeight {
            let h = sections.fittingSize.height - (total - maxHeight)
            let i = stack.arrangedSubviews.firstIndex(of: sections)!
            sections.removeFromSuperview()
            let doc = Flipped()
            sections.translatesAutoresizingMaskIntoConstraints = false
            doc.addSubview(sections)
            NSLayoutConstraint.activate([
                sections.leadingAnchor.constraint(equalTo: doc.leadingAnchor), sections.topAnchor.constraint(equalTo: doc.topAnchor),
                sections.trailingAnchor.constraint(equalTo: doc.trailingAnchor), sections.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            ])
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.documentView = doc
            doc.translatesAutoresizingMaskIntoConstraints = false
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
            scroll.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalToConstant: w), scroll.heightAnchor.constraint(equalToConstant: max(120, h))])
            stack.insertArrangedSubview(scroll, at: i)
        }
    }

    private final class Flipped: NSView { override var isFlipped: Bool { true } }

    /// The range, the time span, the line that says it all, and ✕.
    private func header() -> NSView {
        let title = label(Self.title(range), 18, .semibold, .white)
        let fmt = DateFormatter(); fmt.timeStyle = .short; fmt.dateStyle = .none; fmt.locale = L10n.locale
        var span = fmt.string(from: range.since) + " – " + (Date().timeIntervalSince(range.until) < 60 ? tr("agora") : fmt.string(from: range.until))
        if case .away = range, let away = awayFor { span += "  ·  " + tr("fora %@", Journal.duration(away)) }
        let sub = label(span, 11, .medium, NSColor(white: 1, alpha: 0.48))
        let names = NSStackView(views: [title, sub])
        names.orientation = .vertical; names.alignment = .leading; names.spacing = 1

        let x = ClosureButton { [weak self] in self?.close?() }
        x.isBordered = false
        x.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: tr("Fechar"))?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular))
        x.contentTintColor = NSColor(white: 1, alpha: 0.4)
        x.keyEquivalent = "\u{1b}"
        x.toolTip = tr("Fechar")
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        var rowViews: [NSView] = [ChestMark(), names, spacer]
        if ranges.count > 1 { rowViews.append(chips()) }
        rowViews.append(x)
        let row = NSStackView(views: rowViews)
        row.alignment = .centerY; row.spacing = 10
        row.setCustomSpacing(12, after: rowViews[0])
        row.widthAnchor.constraint(equalToConstant: w).isActive = true

        var views: [NSView] = [row]
        if let h = headline() {
            let t = NSTextField(labelWithAttributedString: h)
            t.lineBreakMode = .byWordWrapping
            t.maximumNumberOfLines = 2
            t.preferredMaxLayoutWidth = w
            views.append(t)
        }
        let col = NSStackView(views: views)
        col.orientation = .vertical; col.alignment = .leading; col.spacing = 12
        return col
    }

    static func title(_ r: SummaryRange) -> String {
        switch r {
        case .away: return tr("Desde que você saiu")
        case .today: return tr("Hoje")
        case .around(let d):
            return tr("Por volta das %@", DateFormatter.localizedString(from: d, dateStyle: .none, timeStyle: .short))
        }
    }

    /// The ranges to switch between, as a small segmented capsule.
    private func chips() -> NSView {
        let views: [NSView] = ranges.map { r in
            let on = sameKind(r, range)
            let b = ClosureButton { [weak self] in self?.pick(r) }
            b.isBordered = false
            let name: String
            switch r {
            case .away: name = tr("Desde que saiu")
            case .today: name = tr("Hoje")
            case .around(let d): name = DateFormatter.localizedString(from: d, dateStyle: .none, timeStyle: .short)
            }
            b.attributedTitle = NSAttributedString(string: name, attributes: [
                .font: rounded(11, on ? .semibold : .medium), .foregroundColor: NSColor(white: 1, alpha: on ? 0.95 : 0.55)])
            let box = NSStackView(views: [b])
            box.edgeInsets = NSEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)
            box.wantsLayer = true
            box.layer?.cornerRadius = 10
            box.layer?.backgroundColor = on ? NSColor(white: 1, alpha: 0.14).cgColor : NSColor.clear.cgColor
            return box
        }
        let s = NSStackView(views: views)
        s.spacing = 2
        s.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        s.wantsLayer = true
        s.layer?.cornerRadius = 12
        s.layer?.backgroundColor = NSColor(white: 0, alpha: 0.25).cgColor
        s.layer?.borderWidth = 1
        s.layer?.borderColor = NSColor(white: 1, alpha: 0.07).cgColor
        return s
    }

    private func sameKind(_ a: SummaryRange, _ b: SummaryRange) -> Bool {
        switch (a, b) {
        case (.away, .away), (.today, .today), (.around, .around): return true
        default: return false
        }
    }

    private func pick(_ r: SummaryRange) {
        guard !sameKind(r, range) else { return }
        range = r
        digest = make(r)
        expanded = []
        compact = false
        render()
        actions.shown(digest, r)
    }

    /// The whole of it in one line: the numbers in their sections' colors.
    private func headline() -> NSAttributedString? {
        guard !digest.quiet else { return nil }
        var parts: [(String, NSColor)] = []
        let d = digest
        if !d.waiting.isEmpty { parts.append((tr(d.waiting.count == 1 ? "%d espera você" : "%d esperam você", d.waiting.count), Self.orange)) }
        if !d.broke.isEmpty { parts.append((tr("%d com erro", d.broke.count), Self.red)) }
        if d.tasksDone > 0 {
            let n = d.tasksDone, p = d.done.count
            parts.append((p > 1 ? tr(n == 1 ? "%d tarefa feita em %d projetos" : "%d tarefas feitas em %d projetos", n, p)
                                : tr(n == 1 ? "%d tarefa feita" : "%d tarefas feitas", n), Self.green))
        }
        if !d.shipped.isEmpty { parts.append((tr(d.shipped.count == 1 ? "%d entregue" : "%d entregues", d.shipped.count), Self.violet)) }
        if !d.running.isEmpty { parts.append((tr("%d ainda trabalhando", d.running.count), Self.teal)) }
        guard !parts.isEmpty else { return nil }
        let s = NSMutableAttributedString()
        for (i, (text, c)) in parts.enumerated() {
            if i > 0 { s.append(NSAttributedString(string: "  ·  ", attributes: [.font: rounded(13), .foregroundColor: NSColor(white: 1, alpha: 0.25)])) }
            // the number stands out, the words after it are quieter
            // each part stays whole on its line: only the dots between them break
            let text = text.replacingOccurrences(of: " ", with: "\u{00A0}")
            let num = text.prefix { $0.isNumber }
            s.append(NSAttributedString(string: String(num), attributes: [.font: rounded(15, .bold), .foregroundColor: c]))
            s.append(NSAttributedString(string: String(text.dropFirst(num.count)), attributes: [.font: rounded(12.5, .medium), .foregroundColor: c.withAlphaComponent(0.85)]))
        }
        return s
    }

    // MARK: - the sections

    private func content() -> [NSView] {
        let d = digest
        var v: [NSView] = []
        func add(_ part: [NSView]) {
            guard !part.isEmpty else { return }
            if !v.isEmpty { v.append(gap()) }
            v += part
        }
        add(section("waiting", "hand.raised.fill", tr("Esperando você"), Self.orange, d.waiting.count,
                    rows: d.waiting.map { line($0, Self.orange) }, limit: 5))
        var broke = d.broke.map { line($0, Self.red) }
        if !d.recovered.isEmpty { broke.append(quiet("↺  " + tr("tiveram erro e seguiram: %@", list(d.recovered)))) }
        add(section("broke", "xmark.octagon.fill", d.broke.isEmpty ? tr("Erros") : tr("Com erro"), Self.red, d.broke.count, rows: broke,
                    limit: d.recovered.isEmpty ? 3 : 4))
        var done: [NSView] = []
        let showProjects = expanded.contains("done") ? d.done.count : min(d.done.count, compact ? 3 : 4)
        for p in d.done.prefix(showProjects) { done += project(p) }
        if d.done.count > showProjects { done.append(more("done", d.done.count - showProjects, tr("projetos"))) }
        done += d.shipped.prefix(expanded.contains("shipped") ? 99 : 3).map { line($0, Self.violet) }
        if d.shipped.count > 3 && !expanded.contains("shipped") { done.append(more("shipped", d.shipped.count - 3, nil)) }
        add(section("done", "checkmark.circle.fill", tr("Feito"), Self.green, d.tasksDone + d.shipped.count, rows: done, limit: 99))
        add(section("running", "figure.pool.swim", tr("Ainda trabalhando"), Self.teal, d.running.count,
                    rows: d.running.map { line($0, Self.teal) }, limit: 4))
        if !d.notices.isEmpty { add([quiet("🫧  " + d.notices.prefix(3).joined(separator: "  ·  "))]) }
        return v
    }

    /// Nothing happened: the water, and how long it stayed calm.
    private func calm() -> [NSView] {
        let waves = NSImageView(image: NSImage(systemSymbolName: "water.waves", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 26, weight: .light)) ?? NSImage())
        waves.contentTintColor = Self.water.withAlphaComponent(0.6)
        let fmt = DateFormatter(); fmt.timeStyle = .short; fmt.dateStyle = .none; fmt.locale = L10n.locale
        let a = label(tr("Nada de novo desde %@.", fmt.string(from: range.since)), 14, .semibold, NSColor(white: 1, alpha: 0.85))
        let b = label(tr("O aquário ficou tranquilo: ninguém terminou, ninguém quebrou, ninguém espera você."), 12, .regular, NSColor(white: 1, alpha: 0.5))
        b.maximumNumberOfLines = 2
        b.lineBreakMode = .byWordWrapping
        b.preferredMaxLayoutWidth = w - 70
        let words = NSStackView(views: [a, b])
        words.orientation = .vertical; words.alignment = .leading; words.spacing = 3
        let row = NSStackView(views: [waves, words])
        row.spacing = 14
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor(white: 1, alpha: 0.045).cgColor
        row.layer?.cornerRadius = 12
        row.widthAnchor.constraint(equalToConstant: w).isActive = true
        return [row]
    }

    /// A section: its symbol and name in its color, how many, then its lines (the first few; the rest a click away).
    private func section(_ key: String, _ symbol: String, _ title: String, _ color: NSColor, _ count: Int, rows: [NSView], limit: Int) -> [NSView] {
        guard !rows.isEmpty else { return [] }
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .bold)) ?? NSImage())
        icon.contentTintColor = color
        let name = NSTextField(labelWithAttributedString: NSAttributedString(string: title.uppercased(), attributes: [
            .font: rounded(10.5, .bold), .foregroundColor: color, .kern: 0.9]))
        var head: [NSView] = [icon, name]
        if count > 0 { head.append(label("\(count)", 10.5, .bold, color.withAlphaComponent(0.55))) }
        let h = NSStackView(views: head)
        h.spacing = 6
        h.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        let open = expanded.contains(key)
        var v: [NSView] = [h]
        v += rows.prefix(open ? rows.count : limit)
        if rows.count > limit && !open { v.append(more(key, rows.count - limit, nil)) }
        return v
    }

    /// The water's line between two sections.
    private func gap() -> NSView {
        let line = WaveLine(width: w, tint: Self.water.withAlphaComponent(0.6))
        let box = NSStackView(views: [line])
        box.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        return box
    }

    /// "+ 3 more": the rest of a list, opened in place.
    private func more(_ key: String, _ n: Int, _ what: String?) -> NSView {
        let b = ClosureButton { [weak self] in
            guard let self else { return }
            self.expanded.insert(key)
            self.render()
        }
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: "+ " + (what.map { "\(n) " + $0 } ?? tr("mais %d", n)), attributes: [
            .font: rounded(11, .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.5)])
        let box = NSStackView(views: [b])
        box.edgeInsets = NSEdgeInsets(top: 0, left: 50, bottom: 0, right: 0)
        return box
    }

    private func quiet(_ s: String) -> NSView {
        let t = label(s, 11, .medium, NSColor(white: 1, alpha: 0.45))
        t.lineBreakMode = .byTruncatingTail
        t.preferredMaxLayoutWidth = w - 50
        let box = NSStackView(views: [t])
        box.edgeInsets = NSEdgeInsets(top: 2, left: 50, bottom: 2, right: 8)
        box.widthAnchor.constraint(equalToConstant: w).isActive = true
        return box
    }

    private func list(_ names: [String]) -> String {
        names.count <= 3 ? names.joined(separator: ", ") : names.prefix(3).joined(separator: ", ") + tr(" e mais %d", names.count - 3)
    }

    /// A line about a session: the fish, small; who and where; what (the question, the task); its own words; when.
    private func line(_ l: Digest.Line, _ accent: NSColor) -> NSView {
        let badge = FishBadge(fish: l.fish, color: l.color, symbol: l.symbol, accent: accent)
        let textW = w - FishBadge.size.width - 120
        let who = NSMutableAttributedString(string: l.who, attributes: [.font: rounded(13, .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.95)])
        if let p = l.place, p != l.who {
            who.append(NSAttributedString(string: "   " + p, attributes: [.font: rounded(11, .medium), .foregroundColor: NSColor(white: 1, alpha: 0.42)]))
        }
        let whoField = NSTextField(labelWithAttributedString: who)
        whoField.lineBreakMode = .byTruncatingTail
        whoField.maximumNumberOfLines = 1
        whoField.cell?.usesSingleLineMode = true
        whoField.preferredMaxLayoutWidth = textW
        let what = label(l.what, 12.5, .regular, NSColor(white: 1, alpha: 0.86))
        what.lineBreakMode = .byWordWrapping
        what.maximumNumberOfLines = 2
        what.preferredMaxLayoutWidth = textW
        var col: [NSView] = [whoField, what]
        if let n = l.note, !n.isEmpty {
            let note = label(n, 11, .regular, NSColor(white: 1, alpha: 0.5))
            note.lineBreakMode = .byTruncatingTail
            note.preferredMaxLayoutWidth = textW
            col.append(note)
        }
        let texts = NSStackView(views: col)
        texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 2
        texts.widthAnchor.constraint(equalToConstant: textW).isActive = true

        // on the right: when; the todo list as a little bar; the way to its pane
        var right: [NSView] = []
        if let t = l.when { right.append(label(t, 10.5, .medium, NSColor(white: 1, alpha: 0.45), mono: true)) }
        if let p = l.progress, p.total > 0 {
            right.append(Pebbles(done: p.done, total: p.total, color: accent))
            right.append(label("\(p.done)/\(p.total)", 10, .medium, accent.withAlphaComponent(0.8), mono: true))
        }
        if let f = l.fish, actions.canGo(f) {
            let go = ClosureButton { [weak self] in self?.actions.go(f) }
            go.isBordered = false
            go.image = NSImage(systemSymbolName: "arrow.up.forward.square", accessibilityDescription: tr("ir até a sessão"))?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            go.contentTintColor = NSColor(white: 1, alpha: 0.5)
            go.toolTip = tr("ir até a sessão (o painel dela)")
            right.append(go)
        }
        let rcol = NSStackView(views: right)
        rcol.orientation = .vertical; rcol.alignment = .trailing; rcol.spacing = 4
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [badge, texts, spacer, rcol])
        row.alignment = .top
        row.spacing = 10

        let action: (() -> Void)?
        if let f = l.fish { action = { [weak self] in self?.actions.open(f) } }
        else if let link = l.link { action = { [weak self] in self?.actions.link(link) } }
        else { action = nil }
        let tip = l.fish != nil ? tr("abrir o cartão dela") : l.link != nil ? tr("abrir") : nil
        return SummaryRow(content: row, width: w, tint: accent, action: action, tip: tip)
    }

    /// A project's finished tasks: the project with its fish and how long it worked, then each task, newest first.
    private func project(_ p: Digest.Project) -> [NSView] {
        let key = "project:" + p.name
        let badge = FishBadge(fish: p.fish, color: p.color, symbol: nil, accent: Self.green)
        let name = label(p.name, 13, .semibold, NSColor(white: 1, alpha: 0.95))
        var facts = tr(p.tasks.count == 1 ? "%d tarefa" : "%d tarefas", p.tasks.count)
        if p.took >= 60 { facts += "  ·  " + Journal.duration(p.took) }
        let count = label(facts, 10.5, .medium, NSColor(white: 1, alpha: 0.45), mono: true)
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let head = NSStackView(views: [badge, name, spacer, count])
        head.alignment = .centerY
        head.spacing = 10
        let f = p.fish
        var v: [NSView] = [SummaryRow(content: head, width: w, tint: Self.green, action: f.map { f in { [weak self] in self?.actions.open(f) } },
                                      tip: f != nil ? tr("abrir o cartão dela") : nil)]
        let open = expanded.contains(key)
        let room = compact ? 2 : 3
        for t in p.tasks.prefix(open ? p.tasks.count : room) { v.append(task(t)) }
        if p.tasks.count > room && !open { v.append(more(key, p.tasks.count - room, nil)) }
        return v
    }

    /// One finished task, under its project: ✓, what it was asked, what it says it did, how long and when.
    private func task(_ l: Digest.Line) -> NSView {
        let textW = w - 50 - 120
        let check = label("✓", 12, .bold, Self.green)
        let what = label(l.what, 12.5, .regular, NSColor(white: 1, alpha: 0.86))
        what.lineBreakMode = .byTruncatingTail
        what.maximumNumberOfLines = 1
        what.preferredMaxLayoutWidth = textW
        var col: [NSView] = [what]
        var under: [String] = []
        if l.who != digest.done.first(where: { $0.tasks.contains { $0.what == l.what } })?.name { under.append(l.who) }
        if let p = l.place { under.append(p) }
        if let n = l.note, !n.isEmpty { under.append(n) }
        if !under.isEmpty {
            let note = label(under.joined(separator: "  ·  "), 11, .regular, NSColor(white: 1, alpha: 0.5))
            note.lineBreakMode = .byTruncatingTail
            note.preferredMaxLayoutWidth = textW
            col.append(note)
        }
        let texts = NSStackView(views: col)
        texts.orientation = .vertical; texts.alignment = .leading; texts.spacing = 1
        texts.widthAnchor.constraint(equalToConstant: textW).isActive = true
        let when = label(l.when ?? "", 10.5, .medium, NSColor(white: 1, alpha: 0.42), mono: true)
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [check, texts, spacer, when])
        row.alignment = .firstBaseline
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 30, bottom: 0, right: 0)
        let f = l.fish
        // the whole of what it said, when the line cuts it
        let tip = [l.what, l.note].compactMap { $0 }.joined(separator: "\n\n")
        return SummaryRow(content: row, width: w, tint: Self.green, action: f.map { f in { [weak self] in self?.actions.open(f) } },
                          tip: tip, inset: 2)
    }

    /// How much work it was, and the way to hear it told.
    private func footer() -> NSView? {
        var views: [NSView] = []
        var facts: [String] = []
        if digest.worked >= 60 { facts.append(tr("%@ de trabalho", Journal.duration(digest.worked))) }
        if digest.steps > 0 { facts.append(tr(digest.steps == 1 ? "%d passo" : "%d passos", digest.steps)) }
        if !facts.isEmpty { views.append(label(facts.joined(separator: "  ·  "), 10.5, .medium, NSColor(white: 1, alpha: 0.38))) }
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        views.append(spacer)
        if let tell = actions.tell, !digest.quiet {
            let r = range
            let b = ClosureButton { tell(r) }
            b.isBordered = false
            b.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            b.imagePosition = .imageLeading
            b.contentTintColor = Self.teal
            b.attributedTitle = NSAttributedString(string: " " + tr("Me conta como foi"), attributes: [.font: rounded(11.5, .semibold), .foregroundColor: Self.teal])
            b.toolTip = tr("o assistente conta em palavras")
            views.append(b)
        }
        guard views.count > 1 else { return nil }
        let row = NSStackView(views: views)
        row.alignment = .centerY
        row.widthAnchor.constraint(equalToConstant: w).isActive = true
        return row
    }

    private func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ color: NSColor = .white, mono: Bool = false) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : rounded(size, weight)
        t.textColor = color
        t.lineBreakMode = .byTruncatingTail
        t.cell?.truncatesLastVisibleLine = true
        t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return t
    }
}

/// A line of the summary that can be clicked: it lights up under the mouse.
final class SummaryRow: NSView {
    private let action: (() -> Void)?
    private let tint: NSColor
    private var area: NSTrackingArea?

    init(content: NSView, width: CGFloat, tint: NSColor, action: (() -> Void)?, tip: String?, inset: CGFloat = 5) {
        self.action = action
        self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        toolTip = tip
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4), content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            content.topAnchor.constraint(equalTo: topAnchor, constant: inset), content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
            widthAnchor.constraint(equalToConstant: width),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        guard action != nil else { return }
        let a = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(a)
        area = a
    }
    override func resetCursorRects() { if action != nil { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = tint.withAlphaComponent(0.1).cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = nil }
    override func mouseDown(with event: NSEvent) { if action == nil { super.mouseDown(with: event) } }
    override func mouseUp(with event: NSEvent) {
        guard let action, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        action()
    }
}

/// The fish a line is about, small, behind a round window rimmed in its color; a plugin's thing shows its symbol, a
/// session that's gone shows a fish's outline in its color.
final class FishBadge: NSView {
    static let size = NSSize(width: 46, height: 30)
    private let picture = CALayer()
    private weak var fish: Fish?

    init(fish: Fish?, color: NSColor, symbol: String?, accent: NSColor) {
        self.fish = fish
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: Self.size.width), heightAnchor.constraint(equalToConstant: Self.size.height)])
        wantsLayer = true
        guard let layer else { return }
        layer.cornerRadius = Self.size.height / 2
        layer.masksToBounds = true
        layer.borderWidth = 1.2
        layer.borderColor = (symbol == nil ? color : accent).withAlphaComponent(0.65).cgColor
        let water = CAGradientLayer()
        water.frame = bounds
        water.colors = [NSColor(red: 0.09, green: 0.24, blue: 0.28, alpha: 1).cgColor, NSColor(red: 0.04, green: 0.12, blue: 0.16, alpha: 1).cgColor]
        layer.addSublayer(water)
        picture.frame = bounds
        picture.contentsGravity = .resizeAspectFill
        picture.contentsRect = CGRect(x: 0.18, y: 0.14, width: 0.64, height: 0.72)    // closer: the fish fills its window
        layer.addSublayer(picture)
        if let f = fish, symbol == nil, let img = FishPortraits.image(for: f, ready: {}) {
            picture.contents = img
        } else {
            // being drawn (perhaps for another badge): look again in a moment
            if fish != nil, symbol == nil { wait(8) }
            // a symbol in its color (the plugin's, or a fish's outline) until (or instead of) the portrait
            let name = symbol ?? "fish.fill"
            let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .bold).applying(.init(hierarchicalColor: symbol == nil ? color : accent)))
            let v = NSImageView(image: img ?? NSImage())
            v.frame = bounds
            v.imageScaling = .scaleNone
            addSubview(v)
            symbolView = v
        }
        let shine = CAGradientLayer()
        shine.frame = bounds
        shine.colors = [NSColor.white.withAlphaComponent(0.16).cgColor, NSColor.clear.cgColor]
        shine.locations = [0, 0.55]
        shine.startPoint = CGPoint(x: 0.5, y: 1)
        shine.endPoint = CGPoint(x: 0.5, y: 0)
        layer.addSublayer(shine)
    }
    required init?(coder: NSCoder) { fatalError() }
    private var symbolView: NSView?

    /// Until the portrait is drawn, a look every half second (the fish's outline stands in meanwhile).
    private func wait(_ tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.window != nil || tries == 8, let f = self.fish else { return }
            if let img = FishPortraits.image(for: f, ready: {}) {
                let fade = CATransition(); fade.duration = 0.25
                self.picture.add(fade, forKey: "fade")
                self.picture.contents = img
                self.symbolView?.removeFromSuperview()
            } else if tries > 0 {
                self.wait(tries - 1)
            }
        }
    }
}

/// A todo list as pebbles: the done ones lit in the section's color.
final class Pebbles: NSView {
    private let done: Int, total: Int, color: NSColor
    init(done: Int, total: Int, color: NSColor) {
        self.done = min(done, total); self.total = total; self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 64), heightAnchor.constraint(equalToConstant: 6)])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        // up to 8 pebbles; more than that, a bar
        if total <= 8 {
            let gap: CGFloat = 2, d = min(6, (bounds.width - gap * CGFloat(total - 1)) / CGFloat(total))
            var x = bounds.width - CGFloat(total) * d - CGFloat(total - 1) * gap
            for i in 0..<total {
                (i < done ? color : NSColor(white: 1, alpha: 0.14)).setFill()
                NSBezierPath(ovalIn: NSRect(x: x, y: (bounds.height - d) / 2, width: d, height: d)).fill()
                x += d + gap
            }
            return
        }
        let r = bounds.insetBy(dx: 0, dy: 1)
        NSColor(white: 1, alpha: 0.14).setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        color.setFill()
        let lit = NSRect(x: r.minX, y: r.minY, width: max(r.height, r.width * CGFloat(done) / CGFloat(total)), height: r.height)
        NSBezierPath(roundedRect: lit, xRadius: r.height / 2, yRadius: r.height / 2).fill()
    }
}

/// The chest's little mark in the summary's corner: a gold chest, its lid open, a glint inside.
final class ChestMark: NSView {
    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 34, height: 30))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 34), heightAnchor.constraint(equalToConstant: 30)])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let wood = NSColor(red: 0.42, green: 0.27, blue: 0.15, alpha: 1), gold = NSColor(red: 0.98, green: 0.78, blue: 0.35, alpha: 1)
        // the glow from inside
        if let g = NSGradient(colors: [gold.withAlphaComponent(0.55), gold.withAlphaComponent(0)]) {
            g.draw(in: NSBezierPath(ovalIn: NSRect(x: 3, y: 9, width: 28, height: 20)), relativeCenterPosition: .zero)
        }
        // the box
        let box = NSBezierPath(roundedRect: NSRect(x: 4, y: 2, width: 26, height: 13), xRadius: 2.5, yRadius: 2.5)
        wood.setFill(); box.fill()
        gold.withAlphaComponent(0.9).setStroke(); box.lineWidth = 1.2; box.stroke()
        gold.setFill()
        NSBezierPath(rect: NSRect(x: 4, y: 10, width: 26, height: 1.6)).fill()
        NSBezierPath(roundedRect: NSRect(x: 15, y: 6, width: 4, height: 5), xRadius: 1, yRadius: 1).fill()
        // the lid, open and leaning back
        let lid = NSBezierPath()
        lid.move(to: NSPoint(x: 5, y: 16)); lid.line(to: NSPoint(x: 8, y: 26))
        lid.curve(to: NSPoint(x: 32, y: 24), controlPoint1: NSPoint(x: 15, y: 30), controlPoint2: NSPoint(x: 27, y: 29))
        lid.line(to: NSPoint(x: 29, y: 16)); lid.close()
        wood.blended(withFraction: 0.15, of: .black)?.setFill(); lid.fill()
        gold.withAlphaComponent(0.9).setStroke(); lid.lineWidth = 1.2; lid.stroke()
        // treasure: two pearls
        NSColor(white: 0.97, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 11, y: 14, width: 5, height: 5)).fill()
        NSBezierPath(ovalIn: NSRect(x: 17, y: 15, width: 4, height: 4)).fill()
    }
}
