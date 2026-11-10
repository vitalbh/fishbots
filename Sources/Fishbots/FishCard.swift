import AppKit
import CoreImage
import simd
import QuartzCore

/// The card that shows up when the mouse rests on a fish: everything about the session (or the PR) at once.
final class FishCard: NSViewController, NSTextFieldDelegate {
    let f: Fish
    private let request: Permissions.Request?
    private let decide: (String) -> Void
    /// Reply from the aquarium (only when it is safe to type into the session) and stop (Esc).
    var reply: ((String) -> Void)?
    var stop: (() -> Void)?
    private var field: NSTextField?
    /// Writing a reply: the card doesn't close on its own.
    var typing: Bool {
        if reading { return true }
        guard let c = field else { return false }
        return reading || !c.stringValue.isEmpty || c.currentEditor() != nil || Dictation.shared.listening
    }
    private var microphone: NSButton?
    private var listenButton: NSButton?
    /// Keeps 🔊 and 🎙 showing what's on (■ while reading aloud or listening), however it started or ended.
    private var stateTimer: Timer?
    var songBar: SongBar?
    private var replySummary: NSTextField?
    private var showAllButton: NSButton?
    private var fullReply = ""

    /// The end of the text: the last lines (up to `lines` and ~n characters), with "…" if it was cut.
    static func textEnding(_ t: String, _ n: Int, lines maxLines: Int = 6) -> String {
        let lines = t.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var taken: [String] = []
        var total = 0
        for l in lines.reversed() {
            if taken.count >= maxLines || total + l.count > n {
                if taken.isEmpty { taken.append("…" + String(l.suffix(n))) }   // one huge line: its end
                break
            }
            taken.insert(l, at: 0)
            total += l.count
        }
        let truncated = taken.count < lines.count
        return (truncated && !(taken.first?.hasPrefix("…") ?? false) ? "…\n" : "") + taken.joined(separator: "\n")
    }

    /// Swaps the excerpt for the full reply, scrolling inside the card.
    @objc private func showAll() {
        guard let short = replySummary, let stack = short.superview as? NSStackView else { return }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let tv = NSTextView()
        tv.string = fullReply
        tv.isEditable = false
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 12.5)
        tv.textColor = .labelColor
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // as wide as the card and as tall as the text needs, up to about half the screen
        let screenH = view.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900
        let lines = CGFloat(fullReply.count) / (width / 7) + CGFloat(fullReply.components(separatedBy: "\n").count)
        scroll.widthAnchor.constraint(equalToConstant: width + 20).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: min(screenH * 0.55, max(200, lines * 17))).isActive = true
        if let i = stack.arrangedSubviews.firstIndex(of: short) {
            stack.insertArrangedSubview(scroll, at: i)
            short.removeFromSuperview()
            showAllButton?.removeFromSuperview()
        }
        tv.frame = NSRect(x: 0, y: 0, width: width + 4, height: 10)
        tv.sizeToFit()
        tv.scrollToEndOfDocument(nil)
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
        reading = true
    }
    /// 🔊: reads the excerpt (or the full reply, if you opened "ver tudo").
    @objc private func listenReply() {
        if Speaker.shared.speaking { Speaker.shared.stop(); return }
        Speaker.shared.speak(reading ? fullReply : (replySummary?.stringValue ?? fullReply).replacingOccurrences(of: "…", with: ""))
    }

    /// Reading the full reply: the card doesn't close on its own.
    private(set) var reading = false
    private var fieldHeight: NSLayoutConstraint?

    /// The field grows with the text (wrapping lines), up to about 6 lines; the card follows.
    private func fitField() {
        guard let c = field, let cell = c.cell else { return }
        let w = c.frame.width > 0 ? c.frame.width : width
        let textHeight = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: w, height: 10_000)).height
        fieldHeight?.constant = min(160, max(46, ceil(textHeight) + 8))
        view.layoutSubtreeIfNeeded()
        preferredContentSize = view.fittingSize
    }

    func controlTextDidChange(_ obj: Notification) { fitField() }

    init(fish: Fish, request: Permissions.Request?, reply: ((String) -> Void)? = nil, stop: (() -> Void)? = nil,
         decide: @escaping (String) -> Void) {
        self.f = fish
        self.request = request
        self.decide = decide
        self.reply = reply
        self.stop = stop
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    static func ha(_ d: Date) -> String {
        let s = Date().timeIntervalSince(d)
        if s < 60 { return tr("agora") }
        return tr("há %@", Journal.duration(s))
    }

    func text(_ s: String, _ len: CGFloat = 12, _ weight: NSFont.Weight = .regular, color: NSColor = .labelColor, mono: Bool = false) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = mono ? .monospacedSystemFont(ofSize: len, weight: weight) : .systemFont(ofSize: len, weight: weight)
        t.textColor = color
        t.preferredMaxLayoutWidth = width
        t.isSelectable = false
        return t
    }

    /// What's expanded in each fish's card ("tools", "tasks"); it survives the card being rebuilt.
    private static var expanded: [String: Set<String>] = [:]
    /// Go to the session (the card's "where" line).
    var go: (() -> Void)?

    /// A small clickable piece of text (a link-like borderless button).
    func link(_ s: String, _ size: CGFloat = 11, color: NSColor = .secondaryLabelColor, tip: String? = nil,
                      _ action: @escaping () -> Void) -> NSButton {
        let b = ClosureButton(action)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: s, attributes: [.font: rounded(size), .foregroundColor: color])
        b.toolTip = tip
        b.setContentHuggingPriority(.required, for: .horizontal)
        return b
    }

    /// Rebuild the card (the app swaps the popover's content).
    var rebuild: (() -> Void)?

    private func toggle(_ what: String) {
        var s = Self.expanded[f.id] ?? []
        if s.contains(what) { s.remove(what) } else { s.insert(what) }
        Self.expanded[f.id] = s
        rebuild?()
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    /// How wide the card is: it grows with what there is to read (a long reply, a long command to approve).
    private lazy var width: CGFloat = {
        let longest = max(f.lastReply?.count ?? 0, request?.summary.count ?? 0, (f.displayTitle ?? "").count * 3)
        return longest < 180 ? 340 : longest < 600 ? 440 : 540
    }()

    override func loadView() {
        // the music fish has its own card: "now playing"
        if f.sings { view = musicCard(); return }
        var v: [NSView] = []
        let open = Self.expanded[f.id] ?? []
        let species = ["oval": "Rex", "slender": "terminal", "puffer": "Claude", "angelfish": "editor", "octopus": "GitHub",
                       "stingray": "Codex"][f.kindID].map(tr) ?? tr(FishKinds.all[min(f.species, FishKinds.all.count - 1)].name)

        // ── header: name and title on the left; state and context on the right
        var left: [NSView] = []
        let name = text(f.nickname ?? f.label, 15, .semibold)
        name.font = rounded(15, .semibold)
        name.preferredMaxLayoutWidth = width - 150
        left.append(name)
        if let t = f.displayTitle, !t.isEmpty {
            let title = text(t, 12, .medium, color: .secondaryLabelColor)
            title.preferredMaxLayoutWidth = width - 150
            left.append(title)
        }
        if f.nickname != nil { left.append(text(f.label, 10.5, color: .tertiaryLabelColor)) }
        let leftCol = NSStackView(views: left)
        leftCol.orientation = .vertical
        leftCol.alignment = .leading
        leftCol.spacing = 2

        var right: [NSView] = []
        // a mood says it all (the music fish); a state says since when
        var state = f.mood ?? (f.stateLabel + " · " + Self.ha(Date(timeIntervalSinceNow: -(CACurrentMediaTime() - f.since))))
        if f.compactingSince != nil { state = tr("🫧 compactando…") }
        let stateColor: NSColor = f.state == .error ? .systemRed : f.state == .waiting ? .systemOrange
            : f.state == .busy ? .systemTeal : .secondaryLabelColor
        right.append(pill(state, stateColor))
        if let c = f.context {
            let bar = NSLevelIndicator()
            bar.levelIndicatorStyle = .continuousCapacity
            bar.minValue = 0; bar.maxValue = 1
            bar.warningValue = 0.7; bar.criticalValue = 0.9
            bar.doubleValue = Double(c)
            bar.widthAnchor.constraint(equalToConstant: 70).isActive = true
            let pct = text(tr("contexto %d%%", Int((c * 100).rounded())), 10.5, color: .secondaryLabelColor)
            let line = NSStackView(views: [pct, bar])
            line.spacing = 6
            right.append(line)
        }
        if f.isAgent {
            let age = Date().timeIntervalSince(f.createdAt)
            right.append(text(tr("ativa %@", age < 60 ? tr("agora") : Journal.duration(age)), 10.5, color: .tertiaryLabelColor))
        }
        let rightCol = NSStackView(views: right)
        rightCol.orientation = .vertical
        rightCol.alignment = .trailing
        rightCol.spacing = 4
        if let art = f.art {
            // the album art (the music fish), rounded, beside the name
            let iv = NSImageView(image: NSImage(cgImage: art, size: NSSize(width: 56, height: 56)))
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 6
            iv.layer?.masksToBounds = true
            iv.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([iv.widthAnchor.constraint(equalToConstant: 56), iv.heightAnchor.constraint(equalToConstant: 56)])
            name.preferredMaxLayoutWidth = width - 216
            v.append(row([iv, leftCol, NSView(), rightCol], alignment: .top))
        } else {
            v.append(row([leftCol, NSView(), rightCol], alignment: .top))
        }

        // where it runs (links): the branch, the place (go there), the folder
        var places: [NSView] = []
        if let b = f.branch, !["main", "master", "HEAD"].contains(b) {
            places.append(link("⎇ " + b, tip: tr("copiar o nome da branch")) { [weak self] in self?.copy(b) })
        }
        let place = (f.sub?.isEmpty == false ? f.sub! : (f.isAgent ? species : ""))
        if !place.isEmpty {
            places.append(link(place, tip: tr(f.link != nil ? "abrir" : "ir até lá")) { [weak self] in self?.go?() })
        }
        if let cwd = f.whereabouts["cwd"] {
            places.append(link("📁 " + (cwd as NSString).lastPathComponent, tip: tr("abrir a pasta no Finder")) {
                NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
            })
        }
        if !places.isEmpty {
            let r = NSStackView(views: places)
            r.spacing = 12
            v.append(r)
        }

        // how far along the song is (the music fish)
        if let p = f.progress, p() != nil {
            let bar = SongBar(progress: p)
            bar.widthAnchor.constraint(equalToConstant: width).isActive = true
            songBar = bar
            v.append(bar)
        }

        // ── what it says: the question, highlighted; then the last reply
        if let q = f.asked, f.state == .waiting, request == nil {
            v.append(divider())
            v.append(tinted(text(tr("✋ ") + q, 13, .medium, color: .labelColor), .systemOrange))
        }
        let hasReply = !(f.lastReply ?? "").isEmpty && [.done, .waiting, .idle, .ok].contains(f.state) && request == nil
        if hasReply, let r = f.lastReply {
            if f.asked == nil || f.state != .waiting { v.append(divider()) }
            let final = Self.textEnding(r, width > 400 ? 800 : 380, lines: width > 400 ? 10 : 6)
            var head: [NSView] = [text(tr("💬 última resposta"), 11, .medium, color: .secondaryLabelColor), NSView()]
            if final.hasPrefix("…") {
                let more = link(tr("ver tudo"), color: .linkColor) { [weak self] in self?.showAll() }
                showAllButton = more
                head.append(more)
            }
            v.append(row(head))
            let t = text(final, 12.5, color: .labelColor)
            t.maximumNumberOfLines = 14
            let ps = NSMutableParagraphStyle(); ps.lineSpacing = 2
            t.attributedStringValue = NSAttributedString(string: final, attributes: [.font: NSFont.systemFont(ofSize: 12.5),
                                                                                  .foregroundColor: NSColor.labelColor, .paragraphStyle: ps])
            v.append(t)
            replySummary = t
            fullReply = r
        }

        // ── activity, compact: latest tools (click: the history with times) and today's tasks (click: all of them)
        let fmt = DateFormatter(); fmt.timeStyle = .medium; fmt.dateStyle = .none
        func toolName(_ n: String) -> String { n.hasPrefix("mcp__") ? "mcp·" + (n.components(separatedBy: "__").dropFirst().first ?? "") : n }
        let today = f.finished.filter { Calendar.current.isDateInToday($0.when) }
        var activity: [NSView] = []
        if !f.history.isEmpty {
            let names = f.history.suffix(4).reversed().map { toolName($0.name) }
            let more = open.contains("tools")
            activity.append(link((more ? "▾ " : "▸ ") + "🛠 " + names.joined(separator: " · ") + "  (\(Self.ha(f.history.last!.when)))",
                                 tip: tr(more ? "recolher" : "ver o histórico")) { [weak self] in self?.toggle("tools") })
        }
        if !today.isEmpty {
            let all = open.contains("tasks")
            activity.append(link((all ? "▾ " : "▸ ") + tr(today.count == 1 ? "✓ %d tarefa hoje" : "✓ %d tarefas hoje", today.count),
                                 tip: tr(all ? "recolher" : "ver todas")) { [weak self] in self?.toggle("tasks") })
        }
        if !activity.isEmpty {
            v.append(divider())
            let r = NSStackView(views: activity)
            r.spacing = 14
            v.append(r)
        }
        if open.contains("tools") {
            for h in f.history.reversed() { v.append(text("   \(fmt.string(from: h.when))  \(toolName(h.name))", 10.5, color: .tertiaryLabelColor, mono: true)) }
        }
        if open.contains("tasks") {
            let short = DateFormatter(); short.timeStyle = .short; short.dateStyle = .none
            for t in today.reversed() {
                v.append(link("   \(short.string(from: t.when))  \(t.title)", tip: tr("copiar o título")) { [weak self] in self?.copy(t.title) })
            }
        }
        if let e = f.lastError, Date().timeIntervalSince(e) < 3600, f.state != .error {
            v.append(text(tr("✗ teve erro %@", Self.ha(e)), 11, color: .systemRed))
        }

        // ── a permission request: answer right here
        if let p = request {
            v.append(divider())
            v.append(text(tr("✋ quer usar %@", p.tool), 13, .semibold, color: .systemOrange))
            v.append(tinted(text(p.summary, 11.5, color: .labelColor, mono: true), .secondaryLabelColor))
            func b(_ t: String, _ id: String, _ k: String = "") -> NSButton {
                let x = NSButton(title: t, target: self, action: #selector(clicked(_:)))
                x.identifier = NSUserInterfaceItemIdentifier(id); x.keyEquivalent = k; x.bezelStyle = .rounded
                return x
            }
            v.append(row([b(tr("Ir até lá"), "go"), NSView(), b(tr("Negar"), "deny"), b(tr("Permitir"), "allow", "\r")]))
        }

        // ── the composer: a big field on its own, then the actions below
        if request == nil, reply != nil {
            v.append(divider())
            let c = NSTextField(wrappingLabelWithString: "")
            c.isEditable = true
            c.isSelectable = true
            c.isBordered = true
            c.isBezeled = true
            c.bezelStyle = .roundedBezel
            c.drawsBackground = true
            c.font = .systemFont(ofSize: 13)
            c.textColor = .labelColor
            c.maximumNumberOfLines = 0
            c.delegate = self
            fieldHeight = c.heightAnchor.constraint(equalToConstant: 46)
            fieldHeight?.isActive = true
            c.placeholderString = tr(f.asked != nil ? "Responder…" : "Mandar uma mensagem…")
            c.target = self
            c.action = #selector(send)
            c.cell?.sendsActionOnEndEditing = false     // closing the card must not send it again
            c.widthAnchor.constraint(equalToConstant: width).isActive = true
            field = c
            v.append(c)
        }
        var actions: [NSView] = []
        if hasReply || (f.asked != nil && f.state == .waiting) {
            let listen = NSButton(title: Self.listenTitle(Speaker.shared.speaking), target: self, action: #selector(listenReply))
            listen.bezelStyle = .rounded
            listen.toolTip = tr("Ler em voz alta (clique de novo para parar)")
            listenButton = listen
            actions.append(listen)
        }
        if field != nil {
            let mic = NSButton(title: Self.micTitle(Dictation.shared.listening), target: self, action: #selector(speak))
            mic.bezelStyle = .rounded
            mic.toolTip = tr("Falar (clique de novo para parar)")
            microphone = mic
            actions.append(mic)
        }
        if request == nil, !actions.isEmpty || stop != nil || field != nil {
            actions.append(NSView())
            if stop != nil {
                let b = NSButton(title: tr("Parar (Esc)"), target: self, action: #selector(stopClicked))
                b.bezelStyle = .rounded
                actions.append(b)
            }
            if field != nil {
                let send = NSButton(title: tr("Enviar"), target: self, action: #selector(send))
                send.bezelStyle = .rounded
                send.contentTintColor = .controlAccentColor
                actions.append(send)
            }
            v.append(row(actions))
        }
        if field != nil && !keyboardHint { v.append(text(tr("vai digitado no terminal da sessão"), 10, color: .tertiaryLabelColor)) }

        // ── the keys (opened with Tab) or the clicks
        if (request == nil && reply == nil) || keyboardHint {
            // the keys this fish really takes: speaking and writing only where the session can be replied to
            // (its provider's .reply), hearing only with something to read, allow/deny only with a request
            var keys = [tr("Tab: próximo"), f.link != nil ? tr("⌘↩ abrir") : tr("⌘↩ ir")]
            if f.asked != nil || !(f.lastReply ?? "").isEmpty { keys.append(tr("⌘R ouvir")) }
            if reply != nil { keys += [tr("⌘D falar"), tr("↩ envia")] }
            if request != nil { keys += [tr("A permitir"), tr("N negar")] }
            keys.append(tr("Esc fechar"))
            let hint = keyboardHint
                ? keys.joined(separator: "  ·  ")
                : tr(f.link != nil ? "clique: abrir  ·  botão direito: menu" : "clique: ir até lá  ·  botão direito: menu")
            v.append(text(hint, 10, color: .tertiaryLabelColor))
        }

        let stack = NSStackView(views: v)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        stack.widthAnchor.constraint(equalToConstant: width + 36).isActive = true
        view = glass(around: stack)
    }

    static func listenTitle(_ on: Bool) -> String { on ? tr("■ Parar leitura") : tr("🔊 Ouvir") }
    static func micTitle(_ on: Bool) -> String { on ? tr("■ Parar microfone") : tr("🎙 Falar") }

    /// A row as wide as the card (an empty NSView in it pushes what follows to the right).
    func row(_ views: [NSView], alignment: NSLayoutConstraint.Attribute = .centerY) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.alignment = alignment
        r.spacing = 8
        r.distribution = .fill
        for x in views where type(of: x) == NSView.self { x.setContentHuggingPriority(.init(1), for: .horizontal) }
        r.widthAnchor.constraint(equalToConstant: width).isActive = true
        return r
    }

    private func divider() -> NSView {
        let d = NSBox()
        d.boxType = .separator
        d.widthAnchor.constraint(equalToConstant: width).isActive = true
        return d
    }

    /// A rounded little label with a tint (the state).
    private func pill(_ s: String, _ color: NSColor) -> NSView {
        let t = text(s, 11, .semibold, color: color)
        t.preferredMaxLayoutWidth = 200
        let box = NSStackView(views: [t])
        box.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        box.wantsLayer = true
        box.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        box.layer?.cornerRadius = 9
        return box
    }

    /// Content on a softly tinted, rounded background, as wide as the card (the question, a command to approve).
    private func tinted(_ content: NSTextField, _ color: NSColor) -> NSView {
        content.preferredMaxLayoutWidth = width - 20
        let box = NSStackView(views: [content])
        box.edgeInsets = NSEdgeInsets(top: 7, left: 10, bottom: 7, right: 10)
        box.wantsLayer = true
        box.layer?.backgroundColor = color.withAlphaComponent(0.13).cgColor
        box.layer?.cornerRadius = 7
        box.widthAnchor.constraint(equalToConstant: width).isActive = true
        return box
    }

    /// The card's background: deep water with a touch of the fish's color.
    var backdrop: NSColor {
        let navy = SIMD3<Float>(0.035, 0.065, 0.1)
        // the music fish: the album's color, deep
        if f.sings, let c = AlbumArt.colors?.0 {
            let d = navy + (c - navy) * 0.22
            return NSColor(red: CGFloat(d.x), green: CGFloat(d.y), blue: CGFloat(d.z), alpha: 0.98)
        }
        let c = navy + (f.color - navy) * 0.16
        return NSColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 0.97)
    }

    /// Dark glass in the fish's color: a deep-water background, a soft glow of its color from the top and a
    /// thin stripe of it on the left.
    private func glass(around content: NSView) -> NSView {
        let bg = NSView()
        bg.appearance = NSAppearance(named: .darkAqua)
        bg.wantsLayer = true
        bg.layer?.backgroundColor = backdrop.cgColor
        let tint = NSColor(red: CGFloat(f.color.x), green: CGFloat(f.color.y), blue: CGFloat(f.color.z), alpha: 1)
        let glow = CAGradientLayer()
        glow.colors = [tint.withAlphaComponent(0.2).cgColor, tint.withAlphaComponent(0.03).cgColor, NSColor.clear.cgColor]
        glow.locations = [0, 0.4, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 1)
        glow.endPoint = CGPoint(x: 0.5, y: 0)
        let stripe = CALayer()
        stripe.backgroundColor = tint.withAlphaComponent(0.9).cgColor
        stripe.cornerRadius = 1.5
        bg.layer?.addSublayer(glow)
        bg.layer?.addSublayer(stripe)
        content.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: bg.leadingAnchor), content.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            content.topAnchor.constraint(equalTo: bg.topAnchor), content.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        bg.layoutSubtreeIfNeeded()
        let size = bg.fittingSize
        bg.frame = NSRect(origin: .zero, size: size)
        glow.frame = bg.bounds
        stripe.frame = CGRect(x: 7, y: 12, width: 3, height: max(0, size.height - 24))
        return bg
    }

    /// The popover's own frame (and its arrow) in the same color, so the whole bubble is dark glass.
    override func viewWillAppear() {
        super.viewWillAppear()
        if let frame = view.window?.contentView?.superview {
            frame.wantsLayer = true
            frame.layer?.backgroundColor = backdrop.cgColor
        }
    }

    @objc private func clicked(_ b: NSButton) { decide(b.identifier?.rawValue ?? "") }
    private var sent = false
    /// Enter while the microphone is on: send once the transcription has its final words (or after 2 s).
    private var sendWhenDone = false
    @objc private func send() {
        guard !sent else { return }
        if Dictation.shared.listening {
            sendWhenDone = true
            field?.placeholderString = tr("terminando a transcrição…")
            Dictation.shared.stop()                    // its end handler sends (see speak)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.sendWhenDone else { return }
                self.sendWhenDone = false
                self.sendNow()
            }
            return
        }
        sendNow()
    }

    private func sendNow() {
        guard !sent, let t = field?.stringValue, !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        sent = true                                   // only once
        field?.stringValue = ""
        reply?(t)
    }
    @objc private func stopClicked() { stop?() }

    /// Cursor at the end of the text, nothing selected, and the end in view.
    private func cursorAtEnd() {
        guard let c = field else { return }
        if c.currentEditor() == nil { view.window?.makeFirstResponder(c) }
        if let ed = c.currentEditor() as? NSTextView {
            let n = (ed.string as NSString).length
            ed.setSelectedRange(NSRange(location: n, length: 0))
            ed.scrollRangeToVisible(NSRange(location: n, length: 0))
        }
    }

    /// Opened from the keyboard (Tab): the hint shows the keys instead of the clicks.
    var keyboardHint = false

    /// Puts the cursor in the reply field (E, from the keyboard).
    func focusReply() { cursorAtEnd() }

    /// ⌘D: the microphone on, or off if it's listening.
    func toggleDictation() {
        guard field != nil else { return }
        if !Dictation.shared.listening { cursorAtEnd() }
        speak()
    }

    /// Starts the microphone (the global shortcut "reply by voice").
    func startDictation() {
        guard field != nil, !Dictation.shared.listening else { return }
        cursorAtEnd()
        speak()
    }

    @objc private func speak() {
        if Dictation.shared.listening {
            Dictation.shared.stop()        // the end handler (below) restores the button and puts the cursor at the end
            return
        }
        if Speaker.shared.speaking { Speaker.shared.stop() }     // the Mac's voice would end up transcribed
        microphone?.title = Self.micTitle(true)
        field?.placeholderString = tr("ouvindo…")
        // what you say now goes after what is already written
        let before = field?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        Dictation.shared.begin(partial: { [weak self] text in
                               guard let self else { return }
                               self.field?.stringValue = before.isEmpty ? text : before + " " + text
                               self.fitField()
                               self.cursorAtEnd()
                           },
                           onError: { [weak self] e in
                               self?.microphone?.title = Self.micTitle(false)
                               self?.field?.placeholderString = e
                           },
                           end: { [weak self] in
                               guard let self else { return }
                               self.microphone?.title = Self.micTitle(false)
                               self.fitField()
                               self.cursorAtEnd()
                               // Enter was pressed while listening: now the text is whole
                               if self.sendWhenDone { self.sendWhenDone = false; self.sendNow() }
                           })
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        stateTimer?.invalidate()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let reading = Self.listenTitle(Speaker.shared.speaking)
            if self.listenButton?.title != reading { self.listenButton?.title = reading }
            let mic = Self.micTitle(Dictation.shared.listening)
            if let m = self.microphone, m.title != mic { m.title = mic }
            self.songBar?.refresh()
        }
    }

    override func viewWillDisappear() {
        stateTimer?.invalidate()
        stateTimer = nil
        super.viewWillDisappear()
        if Dictation.shared.listening { Dictation.shared.stop() }
    }
}
