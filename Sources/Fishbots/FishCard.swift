import AppKit
import QuartzCore

/// The card that shows up when the mouse rests on a fish: everything about the session (or the PR) at once.
final class FishCard: NSViewController, NSTextFieldDelegate {
    private let f: Fish
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
        let width = c.frame.width > 0 ? c.frame.width : 230
        let textHeight = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height
        fieldHeight?.constant = min(110, max(24, ceil(textHeight)))
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

    private func text(_ s: String, _ len: CGFloat = 12, _ weight: NSFont.Weight = .regular, color: NSColor = .labelColor, mono: Bool = false) -> NSTextField {
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
    private func link(_ s: String, _ size: CGFloat = 11, color: NSColor = .secondaryLabelColor, tip: String? = nil,
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
        var v: [NSView] = []
        let open = Self.expanded[f.id] ?? []
        // header: name and where
        let species = ["oval": "Rex", "slender": "terminal", "puffer": "Claude", "angelfish": "editor", "octopus": "GitHub",
                       "stingray": "Codex"][f.kindID].map(tr) ?? tr(FishKinds.all[min(f.species, FishKinds.all.count - 1)].name)
        let name = text(f.nickname ?? f.label, 15, .semibold)
        name.font = rounded(15, .semibold)
        v.append(name)
        if f.nickname != nil { v.append(text(f.label, 11, color: .secondaryLabelColor)) }
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
            let row = NSStackView(views: places)
            row.spacing = 10
            v.append(row)
        }
        if let t = f.displayTitle, !t.isEmpty { v.append(text(t, 12, .medium)) }

        if let q = f.asked, f.state == .waiting { v.append(text(tr("✋ te perguntou: ") + q, 12, .medium, color: .systemOrange)) }
        // state and times
        var state = f.state.label + " " + Self.ha(Date(timeIntervalSinceNow: -(CACurrentMediaTime() - f.since)))
        if f.isAgent {
            let age = Date().timeIntervalSince(f.createdAt)
            state += tr("  ·  ativa %@", age < 60 ? tr("agora") : Journal.duration(age))
        }
        v.append(text(state, 11, color: f.state == .error ? .systemRed : f.state == .waiting ? .systemOrange : .secondaryLabelColor))

        // context
        if let c = f.context {
            let bar = NSLevelIndicator()
            bar.levelIndicatorStyle = .continuousCapacity
            bar.minValue = 0; bar.maxValue = 1
            bar.warningValue = 0.7; bar.criticalValue = 0.9
            bar.doubleValue = Double(c)
            bar.widthAnchor.constraint(equalToConstant: 160).isActive = true
            let rot = text(tr("contexto %d%%", Int((c * 100).rounded())), 11, color: .secondaryLabelColor)
            let line = NSStackView(views: [rot, bar])
            line.spacing = 8
            v.append(line)
        }

        // latest tools (click: the whole recent history, with times)
        let fmt = DateFormatter(); fmt.timeStyle = .medium; fmt.dateStyle = .none
        func toolName(_ n: String) -> String { n.hasPrefix("mcp__") ? "mcp·" + (n.components(separatedBy: "__").dropFirst().first ?? "") : n }
        if !f.history.isEmpty {
            let names = f.history.suffix(6).reversed().map { toolName($0.name) }
            let more = open.contains("tools")
            v.append(link((more ? "▾ " : "▸ ") + "🛠 " + names.joined(separator: " · ") + "  (\(Self.ha(f.history.last!.when)))",
                          tip: tr(more ? "recolher" : "ver o histórico")) { [weak self] in self?.toggle("tools") })
            if more {
                for h in f.history.reversed() { v.append(text("     \(fmt.string(from: h.when))  \(toolName(h.name))", 10.5, color: .tertiaryLabelColor, mono: true)) }
            }
        }

        // today's tasks (click: all of them; click one: copy its title)
        let today = f.finished.filter { Calendar.current.isDateInToday($0.when) }
        if !today.isEmpty {
            let short = DateFormatter(); short.timeStyle = .short; short.dateStyle = .none
            let all = open.contains("tasks")
            v.append(link((all || today.count <= 3 ? "" : "▸ ") + tr(today.count == 1 ? "✓ %d tarefa hoje" : "✓ %d tarefas hoje", today.count),
                          color: .labelColor, tip: today.count > 3 ? tr(all ? "recolher" : "ver todas") : nil) { [weak self] in
                if today.count > 3 { self?.toggle("tasks") }
            })
            for t in (all ? today : Array(today.suffix(3))).reversed() {
                v.append(link("   \(short.string(from: t.when))  \(t.title)", tip: tr("copiar o título")) { [weak self] in self?.copy(t.title) })
            }
        }
        if let e = f.lastError, Date().timeIntervalSince(e) < 3600, f.state != .error {
            v.append(text(tr("✗ teve erro %@", Self.ha(e)), 11, color: .systemRed))
        }

        // last reply (when it stopped): the end, which is where the conclusion is; "ver tudo" opens it whole
        if let r = f.lastReply, !r.isEmpty, [.done, .waiting, .idle, .ok].contains(f.state), request == nil {
            let title = text(tr("💬 última resposta"), 11, .medium, color: .secondaryLabelColor)
            let listen = NSButton(title: Speaker.shared.speaking ? "■" : "🔊", target: self, action: #selector(listenReply))
            listenButton = listen
            listen.bezelStyle = .inline
            listen.controlSize = .small
            listen.toolTip = tr("Ler em voz alta (clique de novo para parar)")
            let header = NSStackView(views: [title, listen])
            header.spacing = 6
            v.append(header)
            let final = Self.textEnding(r, width > 400 ? 800 : 380, lines: width > 400 ? 10 : 6)
            let t = text(final, 12.5, color: .labelColor)
            t.maximumNumberOfLines = 14
            let ps = NSMutableParagraphStyle(); ps.lineSpacing = 2
            t.attributedStringValue = NSAttributedString(string: final, attributes: [.font: NSFont.systemFont(ofSize: 12.5),
                                                                                  .foregroundColor: NSColor.labelColor, .paragraphStyle: ps])
            v.append(t)
            replySummary = t
            if final.hasPrefix("…") {
                let b = NSButton(title: tr("ver tudo"), target: self, action: #selector(showAll))
                b.bezelStyle = .inline
                b.controlSize = .small
                v.append(b)
                showAllButton = b
            }
            fullReply = r
        }

        // permission request: answer right here
        if let p = request {
            v.append(text(tr("✋ quer usar %@", p.tool), 12, .semibold, color: .systemOrange))
            v.append(text(p.summary, 11, color: .secondaryLabelColor, mono: true))
            func b(_ t: String, _ id: String, _ k: String = "") -> NSButton {
                let x = NSButton(title: t, target: self, action: #selector(clicked(_:)))
                x.identifier = NSUserInterfaceItemIdentifier(id); x.keyEquivalent = k; x.bezelStyle = .rounded
                return x
            }
            let buttons = NSStackView(views: [b(tr("Ir até lá"), "go"), NSView(), b(tr("Negar"), "deny"), b(tr("Permitir"), "allow", "\r")])
            buttons.spacing = 8
            v.append(buttons)
            buttons.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else if reply != nil {
            // reply from the aquarium: typed into the session's terminal, with Enter
            let c = NSTextField(wrappingLabelWithString: "")
            c.isEditable = true
            c.isSelectable = true
            c.isBordered = true
            c.isBezeled = true
            c.bezelStyle = .roundedBezel
            c.drawsBackground = true
            c.font = .systemFont(ofSize: 12)
            c.textColor = .labelColor
            c.maximumNumberOfLines = 0
            c.delegate = self
            fieldHeight = c.heightAnchor.constraint(equalToConstant: 24)
            fieldHeight?.isActive = true
            c.placeholderString = tr(f.asked != nil ? "Responder…" : "Mandar uma mensagem…")
            c.target = self
            c.action = #selector(send)
            c.cell?.sendsActionOnEndEditing = false     // closing the card must not send it again
            field = c
            let b = NSButton(title: tr("Enviar"), target: self, action: #selector(send))
            b.bezelStyle = .rounded
            // talk to the little fish: the Mac's transcription
            let mic = NSButton(title: "🎙", target: self, action: #selector(speak))
            mic.bezelStyle = .rounded
            mic.toolTip = tr("Falar (clique de novo para parar)")
            microphone = mic
            c.widthAnchor.constraint(equalToConstant: width - 110).isActive = true
            let line = NSStackView(views: [mic, c, b])
            line.alignment = .top
            line.spacing = 6
            v.append(line)
            v.append(text(tr("vai digitado no terminal da sessão"), 10, color: .tertiaryLabelColor))
        } else if stop != nil {
            let b = NSButton(title: tr("Parar (Esc)"), target: self, action: #selector(stopClicked))
            b.bezelStyle = .rounded
            v.append(b)
        }
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
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 18, bottom: 12, right: 14)
        stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        view = glass(around: stack)
    }

    /// The card's background: deep water with a touch of the fish's color.
    private var backdrop: NSColor {
        let navy = SIMD3<Float>(0.035, 0.065, 0.1)
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
    @objc private func send() {
        guard !sent, let t = field?.stringValue, !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        sent = true                                   // only once
        if Dictation.shared.listening { Dictation.shared.stop() }
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
        microphone?.title = "■"
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
                               self?.microphone?.title = "🎙"
                               self?.field?.placeholderString = e
                           },
                           end: { [weak self] in
                               self?.microphone?.title = "🎙"
                               self?.fitField()
                               self?.cursorAtEnd()
                           })
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        stateTimer?.invalidate()
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            let reading = Speaker.shared.speaking ? "■" : "🔊"
            if self.listenButton?.title != reading { self.listenButton?.title = reading }
            let mic = Dictation.shared.listening ? "■" : "🎙"
            if let m = self.microphone, m.title != mic { m.title = mic }
        }
    }

    override func viewWillDisappear() {
        stateTimer?.invalidate()
        stateTimer = nil
        super.viewWillDisappear()
        if Dictation.shared.listening { Dictation.shared.stop() }
    }
}

/// A borderless button that runs a closure (for the card's links).
final class ClosureButton: NSButton {
    private let run: () -> Void
    init(_ run: @escaping () -> Void) {
        self.run = run
        super.init(frame: .zero)
        target = self
        action = #selector(fire)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func fire() { run() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
