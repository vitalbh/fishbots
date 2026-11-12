import AppKit
import simd

/// The resident assistant's card: the conversation, a field to write or speak into, and what it asks leave for.
/// The same dark glass as the fish's card (CardGlass.swift). It stays one card while it's open and redraws as the
/// answer arrives (`refresh`).
final class AssistantCard: NSViewController, NSTextFieldDelegate {
    private let assistant: Assistant
    /// A fish the answer talks about was picked (the app opens its card).
    var openFish: ((String) -> Void)?
    var close: (() -> Void)?
    var notice: ((String) -> Void)?

    private let width: CGFloat = 348
    private let tint = NSColor(red: 0.5, green: 0.86, blue: 0.74, alpha: 1)
    private let backdrop = NSColor(red: 0.04, green: 0.082, blue: 0.105, alpha: 0.97)
    private let text = NSTextView()
    private let scroll = NSScrollView()
    private let tray = NSStackView()
    private let field = NSTextField()
    private var mic: NSButton!
    private var send: NSButton!
    private var listen: NSButton!
    private var terminal: NSButton!
    private let pill = NSTextField(labelWithString: "")
    private let pillBox = NSStackView()
    private let subtitle = NSTextField(labelWithString: "")
    private var trayShows = ""
    private var textShows = ""
    /// What's in the field was spoken (its answer is read aloud).
    private var dictated = false
    /// Opened by the shortcut: what's heard is sent when the talking stops, hands off the keyboard.
    private var handsFree = false
    private var sendWhenHeard = false
    private var stateTimer: Timer?

    init(assistant: Assistant) {
        self.assistant = assistant
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = rounded(size, weight)
        t.textColor = color
        t.lineBreakMode = .byTruncatingTail
        return t
    }

    /// A small rounded button with text (a suggestion, a fish, a footer action).
    private func chip(_ title: String, color: NSColor = NSColor(white: 1, alpha: 0.86), filled: Bool = true, size: CGFloat = 11.5,
                      _ run: @escaping () -> Void) -> NSButton {
        let b = ClosureButton(run)
        b.isBordered = false
        b.attributedTitle = NSAttributedString(string: title, attributes: [.font: rounded(size, .medium), .foregroundColor: color])
        b.wantsLayer = true
        b.layer?.cornerRadius = 10
        if filled { b.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor }
        b.translatesAutoresizingMaskIntoConstraints = false
        let w = min(width, ceil(b.attributedTitle.size().width) + (filled ? 18 : 4))
        NSLayoutConstraint.activate([b.widthAnchor.constraint(equalToConstant: w), b.heightAnchor.constraint(equalToConstant: filled ? 22 : 18)])
        b.lineBreakMode = .byTruncatingTail
        return b
    }

    /// Chips side by side, on as many rows as they need.
    private func flow(_ chips: [NSButton]) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 5
        var row: NSStackView?, used: CGFloat = 0
        for c in chips {
            let w = c.constraints.first { $0.firstAttribute == .width }?.constant ?? 80
            if row == nil || used + w + 6 > width {
                let r = NSStackView()
                r.spacing = 6
                rows.addArrangedSubview(r)
                row = r
                used = 0
            }
            row?.addArrangedSubview(c)
            used += w + 6
        }
        return rows
    }

    override func loadView() {
        // the header: the burrow's porthole, who it is and how it is
        let hole = Porthole(image: nil, tint: tint)
        let glyph = NSImageView(image: NSImage(systemSymbolName: "bubble.left.and.text.bubble.right.fill", accessibilityDescription: nil) ?? NSImage())
        glyph.contentTintColor = tint.withAlphaComponent(0.85)
        glyph.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        hole.addSubview(glyph)
        NSLayoutConstraint.activate([glyph.centerXAnchor.constraint(equalTo: hole.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: hole.centerYAnchor)])
        subtitle.font = rounded(10.5)
        subtitle.textColor = .tertiaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        let title = NSStackView(views: [label(tr("Assistente do aquário"), 15, .semibold, .labelColor), subtitle])
        title.orientation = .vertical; title.alignment = .leading; title.spacing = 2
        let spacer = NSView(); spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        pill.font = rounded(11, .semibold)
        pillBox.addArrangedSubview(pill)
        pillBox.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        pillBox.wantsLayer = true
        pillBox.layer?.cornerRadius = 9
        pillBox.setContentCompressionResistancePriority(.required, for: .horizontal)
        let head = NSStackView(views: [hole, title, spacer, pillBox])
        head.spacing = 10
        head.alignment = .top
        head.widthAnchor.constraint(equalToConstant: width).isActive = true

        // the conversation
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 0, height: 2)
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.isVerticallyResizable = true
        text.autoresizingMask = [.width]
        text.frame = NSRect(x: 0, y: 0, width: width, height: 10)
        scroll.documentView = text
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: width).isActive = true
        scroll.setContentHuggingPriority(.init(1), for: .vertical)
        scroll.setContentCompressionResistancePriority(.init(1), for: .vertical)

        tray.orientation = .vertical
        tray.alignment = .leading
        tray.spacing = 6

        // the field, the microphone and the arrow that sends (a square that stops, while it thinks)
        field.placeholderString = tr("pergunte ao aquário…")
        field.font = rounded(13)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = .labelColor
        field.delegate = self
        field.lineBreakMode = .byTruncatingHead
        field.cell?.usesSingleLineMode = true
        mic = chip("🎙", filled: false, size: 14) { [weak self] in self?.toggleDictation() }
        send = chip("↑", color: .black, size: 13) { [weak self] in self?.sendOrStop() }
        send.layer?.backgroundColor = tint.cgColor
        send.layer?.cornerRadius = 11
        let entry = NSStackView(views: [field, mic, send])
        entry.spacing = 6
        entry.edgeInsets = NSEdgeInsets(top: 6, left: 11, bottom: 6, right: 6)
        entry.wantsLayer = true
        entry.layer?.cornerRadius = 15
        entry.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        entry.layer?.borderWidth = 1
        entry.layer?.borderColor = tint.withAlphaComponent(0.25).cgColor
        entry.widthAnchor.constraint(equalToConstant: width).isActive = true

        // small things underneath
        let dim = NSColor(white: 1, alpha: 0.5)
        listen = chip(tr("🔊 ouvir"), color: dim, filled: false, size: 10.5) { [weak self] in self?.readAloud() }
        terminal = chip(tr("abrir no terminal"), color: dim, filled: false, size: 10.5) { [weak self] in self?.openInTerminal() }
        let fresh = chip(tr("nova conversa"), color: dim, filled: false, size: 10.5) { [weak self] in self?.assistant.newConversation() }
        let notes = chip(tr("notas"), color: dim, filled: false, size: 10.5) {
            DispatchQueue.global().async {
                Assistant.prepareFolder()
                DispatchQueue.main.async { NSWorkspace.shared.open(Assistant.folder.appendingPathComponent("notes.md")) }
            }
        }
        notes.toolTip = tr("O que ele lembra entre as conversas: um arquivo que ele lê e escreve, e você também pode.")
        terminal.toolTip = tr("Continua esta conversa num terminal, onde dá para ver tudo o que ele faz.")
        let foot = NSStackView(views: [listen, fresh, terminal, notes])
        foot.spacing = 12

        let stack = NSStackView(views: [head, WaveLine(width: width, tint: tint), scroll, tray, entry, foot])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 22, bottom: 12, right: 18)
        let bg = GlassView(backdrop: backdrop, tint: tint)
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor), stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor),
            stack.topAnchor.constraint(equalTo: bg.topAnchor), stack.bottomAnchor.constraint(equalTo: bg.bottomAnchor),
        ])
        bg.frame = NSRect(x: 0, y: 0, width: width + 40, height: 440)
        view = bg
        preferredContentSize = bg.frame.size
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if let frame = view.window?.contentView?.superview {
            frame.wantsLayer = true
            frame.layer?.backgroundColor = backdrop.cgColor
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(field)
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
    }

    override func viewWillDisappear() {
        stateTimer?.invalidate()
        stateTimer = nil
        super.viewWillDisappear()
        if Dictation.shared.listening { Dictation.shared.stop() }
    }

    private func tick() {
        let m = Dictation.shared.listening ? "⏺" : "🎙"
        if mic.attributedTitle.string != m { retitle(mic, m, size: 14, color: Dictation.shared.listening ? .systemRed : NSColor(white: 1, alpha: 0.86)) }
        let l = Speaker.shared.speaking ? tr("◼︎ parar") : tr("🔊 ouvir")
        if listen.attributedTitle.string != l { retitle(listen, l, size: 10.5, color: NSColor(white: 1, alpha: 0.5)) }
    }

    private func retitle(_ b: NSButton, _ s: String, size: CGFloat, color: NSColor) {
        b.attributedTitle = NSAttributedString(string: s, attributes: [.font: rounded(size, .medium), .foregroundColor: color])
    }

    // MARK: - showing

    /// Redraws from the assistant: called whenever something changed there.
    func refresh() {
        guard isViewLoaded else { return }
        let brain = assistant.brain
        let model = (assistant.answeringModel ?? brain.map { Assistant.model($0.id) } ?? "").replacingOccurrences(of: "claude-", with: "")
        subtitle.stringValue = [brain?.name ?? tr("sem cérebro"), model].filter { !$0.isEmpty }.joined(separator: " · ")
        let (word, color): (String, NSColor) = assistant.request != nil ? (tr("pede licença"), .systemYellow)
            : assistant.thinking ? (tr("pensando…"), .systemTeal)
            : assistant.turns.last?.failed == true ? (tr("não deu"), .systemOrange) : (tr("às ordens"), .systemGreen)
        pill.stringValue = word
        pill.textColor = color
        pillBox.layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        retitle(send, assistant.thinking ? "◼︎" : "↑", size: 13, color: .black)
        terminal.isHidden = !assistant.canOpenInTerminal
        showConversation()
        showTray()
    }

    private func showConversation() {
        let out = NSMutableAttributedString()
        let dim = NSColor(white: 1, alpha: 0.5)
        func line(_ s: String, _ font: NSFont, _ color: NSColor, before: CGFloat = 0, after: CGFloat = 4) {
            let p = NSMutableParagraphStyle()
            p.paragraphSpacingBefore = before
            p.paragraphSpacing = after
            p.lineSpacing = 2
            out.append(NSAttributedString(string: s + "\n", attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p]))
        }
        if assistant.turns.isEmpty {
            line(tr("Pergunte sobre o aquário: quem espera por você, o que aconteceu hoje. Ou peça para responder, parar ou abrir uma sessão."),
                 rounded(12.5), NSColor(white: 1, alpha: 0.62))
            if assistant.hasBrain == false { line(tr("Não achei o agente escolhido neste Mac (Preferências → Assistente)."), rounded(12), .systemOrange, before: 6) }
        }
        for (i, t) in assistant.turns.enumerated() {
            line(t.question, rounded(12.5, .semibold), tint, before: i == 0 ? 0 : 12)
            if !t.answer.isEmpty {
                if t.failed { line("⚠︎ " + t.answer, rounded(12), .systemOrange) }
                else {
                    out.append(ReplyText.attributed(t.answer, markdown: true, tint: tint, size: 12.5))
                    if !out.string.hasSuffix("\n") { out.append(NSAttributedString(string: "\n")) }
                }
            }
            if i == assistant.turns.count - 1, assistant.thinking {
                line(t.doing ?? (t.answer.isEmpty ? tr("pensando…") : "…"), rounded(11.5), dim, before: t.answer.isEmpty ? 0 : 4)
            }
        }
        // (the same text again: nothing to do, and the person may be selecting some of it)
        guard out.string != textShows else { return }
        textShows = out.string
        text.textStorage?.setAttributedString(out)
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        text.scrollToEndOfDocument(nil)
    }

    /// Under the conversation: what it asks leave for, or the fish it talked about and questions worth a click.
    private func showTray() {
        let last = assistant.turns.last
        let suggestions = assistant.thinking ? [] : assistant.suggestions
        let shows = assistant.request.map { "ask:" + $0.id } ?? ((last?.mentions ?? []) + suggestions).joined(separator: "|")
        guard shows != trayShows else { return }
        trayShows = shows
        tray.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if let r = assistant.request {
            let what = label(tr("quer usar %@", Assistant.toolName(r.tool)), 12, .semibold, .systemYellow)
            let how = NSTextField(wrappingLabelWithString: String(r.summary.prefix(400)))
            how.font = .monospacedSystemFont(ofSize: 10.5, weight: .regular)
            how.textColor = NSColor(white: 1, alpha: 0.75)
            how.maximumNumberOfLines = 4
            how.preferredMaxLayoutWidth = width
            how.isSelectable = false
            var answers = [chip(tr("Permitir"), color: .black) { [weak self] in self?.assistant.decide(allow: true) }]
            answers[0].layer?.backgroundColor = tint.cgColor
            // "always", as narrow or as wide as the person wants: this command or the whole program, this tool or
            // the whole connector
            for k in Assistant.ruleKeys(r) {
                let name = Assistant.ruleName(k)
                let always = chip(tr("Sempre: %@", name)) { [weak self] in self?.assistant.decide(allow: true, always: k) }
                always.toolTip = tr("Daqui em diante, sem perguntar: %@ (dá para desfazer nas Preferências)", name)
                answers.append(always)
            }
            answers.append(chip(tr("Negar")) { [weak self] in self?.assistant.decide(allow: false) })
            tray.addArrangedSubview(what)
            if !r.summary.isEmpty { tray.addArrangedSubview(how) }
            tray.addArrangedSubview(flow(answers))
            return
        }
        var chips: [NSButton] = []
        for id in last?.mentions ?? [] {
            guard let name = fishName?(id) else { continue }
            chips.append(chip("→ " + String(name.prefix(28)), color: tint) { [weak self] in self?.openFish?(id) })
        }
        for s in suggestions { chips.append(chip(s) { [weak self] in self?.assistant.ask(s) }) }
        if !chips.isEmpty { tray.addArrangedSubview(flow(chips)) }
    }

    /// A fish's name for its chip (the app's to say).
    var fishName: ((String) -> String?)?

    // MARK: - talking

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { sendNow(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { close?(); return true }
        return false
    }

    func controlTextDidChange(_ obj: Notification) { if field.stringValue.isEmpty { dictated = false } }

    private func sendOrStop() { assistant.thinking ? assistant.stop() : sendNow() }

    private func sendNow() {
        // still listening: the last words are on their way, send when they're in
        if Dictation.shared.listening { sendWhenHeard = true; Dictation.shared.stop(); return }
        let q = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !assistant.thinking else { return }
        if Speaker.shared.speaking { Speaker.shared.stop() }
        field.stringValue = ""
        assistant.ask(q, spoken: dictated)
        dictated = false
    }

    /// The microphone, from the shortcut: speak, and it's sent when you stop.
    func startDictation(handsFree: Bool) {
        guard isViewLoaded, !Dictation.shared.listening else { return }
        self.handsFree = handsFree
        toggleDictation()
    }

    func toggleDictation() {
        if Dictation.shared.listening { Dictation.shared.stop(); return }
        if Speaker.shared.speaking { Speaker.shared.stop() }      // the Mac's voice would end up transcribed
        field.placeholderString = tr("ouvindo…")
        let before = field.stringValue.trimmingCharacters(in: .whitespaces)
        Dictation.shared.begin(partial: { [weak self] heard in
                                   guard let self else { return }
                                   self.field.stringValue = before.isEmpty ? heard : before + " " + heard
                                   self.dictated = true
                               },
                               onError: { [weak self] e in self?.field.placeholderString = e },
                               end: { [weak self] in
                                   guard let self else { return }
                                   self.field.placeholderString = tr("pergunte ao aquário…")
                                   let go = self.sendWhenHeard || self.handsFree
                                   self.sendWhenHeard = false
                                   self.handsFree = false
                                   if go { self.sendNow() }
                               })
    }

    private func readAloud() {
        if Speaker.shared.speaking { Speaker.shared.stop(); return }
        guard let a = assistant.turns.last(where: { !$0.answer.isEmpty })?.answer else { return }
        Speaker.shared.speak(ClaudeCodeHook.stripMarkdown(a))
    }

    private func openInTerminal() {
        assistant.openInTerminal { [weak self] problem in
            if let problem { self?.notice?(problem) } else { self?.close?() }
        }
    }
}

/// Where the assistant's card lives: opened from the creature (a click) or the shortcut, pointing at its burrow.
final class AssistantPanel: NSObject, NSPopoverDelegate {
    let assistant: Assistant
    private let tank: Tank
    /// The water's view, where the card points.
    weak var view: NSView?
    /// A fish's card is asked for from this one.
    var openFish: ((Fish) -> Void)?
    private var popover: NSPopover?
    private var card: AssistantCard?

    init(assistant: Assistant, tank: Tank) {
        self.assistant = assistant
        self.tank = tank
        super.init()
        assistant.onOpen = { [weak self] in self?.toggle() }
        assistant.cardOpen = { [weak self] in self?.isOpen ?? false }
        assistant.changed = { [weak self] in self?.card?.refresh() }
    }

    var isOpen: Bool { popover?.isShown == true }

    func toggle() { if isOpen { close() } else { show() } }

    func close() { popover?.close() }

    /// Opens the card at the burrow. `listening`: with the microphone on (the shortcut). false: it isn't in the tank.
    @discardableResult
    func show(listening: Bool = false) -> Bool {
        if isOpen {
            if listening { card?.toggleDictation() }
            return true
        }
        guard let view, let at = assistant.place else {
            tank.notice = (tr("o assistente não está no aquário (Preferências → Assistente)"), tank.time)
            return false
        }
        let c = AssistantCard(assistant: assistant)
        c.close = { [weak self] in self?.close() }
        c.notice = { [weak self] s in guard let self else { return }; self.tank.notice = (s, self.tank.time) }
        c.fishName = { [weak self] id in self?.tank.fish.first { $0.id == id }.map { $0.nickname ?? $0.displayTitle ?? $0.label } }
        c.openFish = { [weak self] id in
            guard let self, let f = self.tank.fish.first(where: { $0.id == id }) else { return }
            self.close()
            self.openFish?(f)
        }
        let pop = NSPopover()
        pop.behavior = .semitransient
        pop.appearance = NSAppearance(named: .darkAqua)
        pop.contentViewController = c
        pop.delegate = self
        pop.show(relativeTo: NSRect(x: CGFloat(at.x) - 12, y: CGFloat(at.y) - 4, width: 24, height: 24), of: view, preferredEdge: .maxY)
        popover = pop
        card = c
        assistant.seen()
        if listening { c.startDictation(handsFree: true) }
        return true
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        card = nil
    }
}

/// The app's side of the assistant: what it needs from the rest, and the shortcut.
extension AppDelegate {
    func setUpAssistant() {
        assistant.pendingPermission = { [unowned self] f in self.permissions.request(ofFish: f.id).map { $0.tool + ": " + $0.summary } }
        assistant.account = { [unowned self] agent in self.sessionControl.account(agent) }
        assistant.port = { [unowned self] in self.port }
        assistant.findFish = { [unowned self] name in self.sessionControl.fish(name) }
        Outputs.register(AssistantEars(assistant))
        assistantPanel.view = view
        assistantPanel.openFish = { [unowned self] f in self.cards.open(f) }
        assistant.settle()
    }

    /// The global shortcut (⌃⌥A by default) and the menu: the aquarium comes forward with the assistant's card
    /// open and the microphone on. Speak; it's sent when you stop.
    @objc func talkToAssistant() {
        show()
        assistantPanel.show(listening: true)
    }

    @objc func openAssistant() {
        show()
        assistantPanel.show()
    }
}
