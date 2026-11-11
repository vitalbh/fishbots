import AppKit

/// "Nova sessão…": the person starts a session from the aquarium itself, with its task, its folder and its agent.
/// It opens in a terminal host through the launchers, like one a session launches, but it's nobody's child; asked
/// to, it starts with the orchestrator skill in hand, so it can launch its own. A card of the aquarium's own glass
/// (as a fish's), rising from the clutch of eggs its fish will hatch from; the aquarium keeps running behind it.
extension AppDelegate {
    @objc func newSession() {
        newSessionCard?.close()
        let agents = Providers.all.values.filter { $0.launchCommand(prompt: nil, model: nil) != nil }.sorted { $0.name < $1.name }
        guard !agents.isEmpty, Launchers.pick(nil, near: nil) != nil else {
            let a = NSAlert()
            a.messageText = tr("Não há onde abrir uma sessão")
            a.informativeText = tr("O aquário abre sessões no Rex, no Herdr ou no tmux, e nenhum deles está instalado.")
            show()
            a.beginSheetModal(for: window)
            return
        }
        show()
        NSApp.activate(ignoringOtherApps: true)
        // the folder picked last time; the first time, where the most recent session works
        let recent = tank.fish.filter { $0.isAgent && !$0.decor && $0.whereabouts["cwd"] != nil }.max { $0.bornAt < $1.bornAt }?.whereabouts["cwd"]
        let pop = NSPopover()
        pop.behavior = .semitransient     // a click elsewhere in the aquarium closes it (the folder panel doesn't)
        pop.animates = false
        pop.appearance = NSAppearance(named: .darkAqua)
        let card = NewSessionCard(agents: agents, folder: UserDefaults.standard.string(forKey: "newSessionFolder") ?? recent ?? NSHomeDirectory())
        card.cancel = { [weak pop] in pop?.close() }
        card.send = { [weak self, weak pop] chosen, dir, task, model, leading in
            pop?.close()
            self?.open(chosen, in: dir, task: task, model: model, leading: leading)
        }
        pop.contentViewController = card
        pop.delegate = card
        // over the clutch of eggs, where there is one; else low in the middle of the tank
        var at = NSRect(x: view.bounds.midX - 20, y: view.bounds.height * 0.2, width: 40, height: 40)
        if let eggs = tank.scenery.eggs {
            let (c, sz) = tank.scenery.place(tank, eggs)
            at = NSRect(x: CGFloat(c.x - sz), y: CGFloat(c.y - sz * 0.3), width: CGFloat(sz * 2), height: CGFloat(sz * 1.1))
        }
        pop.show(relativeTo: at, of: view, preferredEdge: .maxY)
        newSessionCard = pop
    }

    func open(_ chosen: SessionProvider, in dir: String, task: String, model: String?, leading: Bool) {
        let defaults = UserDefaults.standard
        let words = task.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(dir, forKey: "newSessionFolder")
        defaults.set(chosen.id, forKey: "newSessionAgent")
        if SessionControl.enabled { defaults.set(leading, forKey: "newSessionLeads") }
        var prompt: String? = words.isEmpty ? nil : words
        if leading {
            prompt = "Use the fishbots-orchestrator skill: where it helps, split this work across sessions with `fishbots spawn`, "
                + "follow them and bring their results together." + (words.isEmpty ? " Ask me what the work is." : "\n\n" + words)
        }
        // the host's session is named after the task itself, not after the orchestrator's preamble
        let name = words.split(whereSeparator: { $0.isWhitespace }).prefix(5).joined(separator: " ")
        sessionControl.open(agent: chosen.id, cwd: dir, prompt: prompt, model: model, label: name.isEmpty ? nil : String(name.prefix(32))) { [weak self] failure in
            guard let self, let failure else { return }
            let e = NSAlert()
            e.messageText = tr("Não consegui abrir a sessão")
            e.informativeText = failure
            e.beginSheetModal(for: self.window)
        }
    }

    /// The card's "encerrar sessão": asks first (it stops whatever the session is doing), and with a school asks
    /// whether the school goes too.
    func endSession(_ f: Fish) {
        let school = tank.school(of: f)
        let a = NSAlert()
        a.messageText = tr("Encerrar %@?", f.nickname ?? f.displayTitle ?? f.label)
        a.informativeText = tr("O painel dela no terminal fecha, e o que ela estiver fazendo é interrompido.")
        a.addButton(withTitle: tr("Encerrar"))
        a.addButton(withTitle: tr("Cancelar"))
        if !school.isEmpty { a.addButton(withTitle: tr("Encerrar com o cardume (%d)", school.count)) }
        a.buttons.first?.hasDestructiveAction = true
        cards.close()
        show()
        a.beginSheetModal(for: window) { [weak self, weak f] answer in
            guard let self, let f, answer != .alertSecondButtonReturn else { return }
            var failures: [String] = []
            let going = (answer == .alertThirdButtonReturn ? school : []) + [f]
            for one in going {
                self.sessionControl.end(one) { failure in
                    guard let failure else { return }
                    failures.append(failure)
                    if failures.count == 1 { self.tank.notice = (failure, self.tank.time) }
                }
            }
        }
    }
}

/// The card: what the session should do, where, with which agent and model, and whether it may lead others.
final class NewSessionCard: NSViewController, NSTextFieldDelegate, NSPopoverDelegate {
    /// Dragged by its glass, it comes off the eggs and stays where it's put.
    func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }
    private var escape: Any?

    private let agents: [SessionProvider]
    private var folder: String
    var cancel: (() -> Void)?
    var send: ((SessionProvider, String, String, String?, Bool) -> Void)?

    private let width: CGFloat = 360
    /// The eggs' own orange: the card is a piece of their water.
    private let tint = NSColor(red: 1, green: 0.62, blue: 0.3, alpha: 1)
    private var task: NSTextField!
    private var taskHeight: NSLayoutConstraint!
    private var where_: NSButton!
    private var agent: NSPopUpButton!
    private var model: NSTextField!
    private var leads: NSButton!
    private var microphone: NSButton!
    /// ↩ while the microphone is on: open once the transcription has its last words.
    private var sendWhenDone = false

    init(agents: [SessionProvider], folder: String) {
        self.agents = agents
        self.folder = folder
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var backdrop: NSColor { NSColor(red: 0.07, green: 0.075, blue: 0.1, alpha: 0.97) }

    private func label(_ s: String, _ size: CGFloat = 12, _ weight: NSFont.Weight = .regular, color: NSColor = .labelColor) -> NSTextField {
        let t = NSTextField(wrappingLabelWithString: s)
        t.font = rounded(size, weight)
        t.textColor = color
        t.preferredMaxLayoutWidth = width
        return t
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.spacing = 8
        for x in views where type(of: x) == NSView.self { x.setContentHuggingPriority(.init(1), for: .horizontal) }
        r.widthAnchor.constraint(equalToConstant: width).isActive = true
        return r
    }

    private func patch(_ inner: NSView) -> NSView {
        let box = NSStackView(views: [inner])
        box.edgeInsets = NSEdgeInsets(top: 3, left: 9, bottom: 3, right: 9)
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        box.layer?.cornerRadius = 9
        return box
    }

    private func folderTitle() -> NSAttributedString {
        let short = (folder as NSString).abbreviatingWithTildeInPath
        let shown = short.count > 44 ? "…" + short.suffix(43) : short
        return NSAttributedString(string: "📁 " + shown, attributes: [.font: rounded(11.5), .foregroundColor: NSColor.secondaryLabelColor])
    }

    override func loadView() {
        let title = label(tr("Nova sessão"), 15, .semibold)
        let sub = label(tr("Ela abre no terminal e nasce aqui, dos ovos."), 11, color: tint.blended(withFraction: 0.45, of: .white) ?? tint)

        let c = NSTextField(wrappingLabelWithString: "")
        c.isEditable = true
        c.isSelectable = true
        c.isBordered = true
        c.isBezeled = true
        c.bezelStyle = .roundedBezel
        c.drawsBackground = true
        c.font = .systemFont(ofSize: 13)
        c.maximumNumberOfLines = 0
        c.placeholderString = tr("O que ela deve fazer…")
        c.delegate = self
        c.target = self
        c.action = #selector(sendClicked)
        c.cell?.sendsActionOnEndEditing = false
        c.widthAnchor.constraint(equalToConstant: width).isActive = true
        taskHeight = c.heightAnchor.constraint(equalToConstant: 64)
        taskHeight.isActive = true
        task = c

        let w = ClosureButton { [weak self] in self?.pickFolder() }
        w.isBordered = false
        w.attributedTitle = folderTitle()
        w.toolTip = tr("A pasta em que ela trabalha (clique para escolher outra)")
        where_ = w

        let a = NSPopUpButton()
        for p in agents { a.addItem(withTitle: p.name) }
        if let last = UserDefaults.standard.string(forKey: "newSessionAgent"), let i = agents.firstIndex(where: { $0.id == last }) { a.selectItem(at: i) }
        a.controlSize = .small
        a.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        agent = a

        let m = NSTextField(string: "")
        m.placeholderString = tr("modelo (vazio: o da conta)")
        m.controlSize = .small
        m.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        m.bezelStyle = .roundedBezel
        model = m

        let l = NSButton(checkboxWithTitle: tr("Pode lançar outras sessões e comandá-las (orquestrar)"), target: nil, action: nil)
        l.font = rounded(11.5)
        l.state = SessionControl.enabled && UserDefaults.standard.object(forKey: "newSessionLeads") as? Bool ?? true ? .on : .off
        l.isEnabled = SessionControl.enabled
        if !SessionControl.enabled { l.toolTip = tr("Ligue \"Sessões podem comandar outras\" em Preferências → Geral") }
        leads = l

        // speaking the task, as in a fish's card
        let mic = NSButton(title: FishCard.micTitle(Dictation.shared.listening), target: self, action: #selector(speak))
        mic.bezelStyle = .rounded
        mic.toolTip = tr("Falar (clique de novo para parar)")
        mic.keyEquivalent = "d"
        mic.keyEquivalentModifierMask = .command
        microphone = mic

        let no = NSButton(title: tr("Cancelar"), target: self, action: #selector(cancelClicked))
        no.bezelStyle = .rounded
        no.keyEquivalent = "\u{1b}"
        let go = NSButton(title: tr("Abrir"), target: self, action: #selector(sendClicked))
        go.bezelStyle = .rounded
        go.contentTintColor = .controlAccentColor

        let hint = label(tr("↩ abre  ·  ⌥↩ quebra a linha  ·  ⌘D falar  ·  Esc fecha"), 10, color: .tertiaryLabelColor)
        let stack = NSStackView(views: [title, sub, WaveLine(width: width, tint: tint), c, row([patch(w), NSView()]), row([a, m]),
                                        l, row([mic, NSView(), no, go]), hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.setCustomSpacing(2, after: title)
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 22, bottom: 14, right: 18)
        stack.widthAnchor.constraint(equalToConstant: width + 40).isActive = true

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

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(task)
        // Esc closes it, wherever the keys are going (the card or the aquarium behind it)
        if escape == nil {
            escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self, e.keyCode == 53, self.view.window != nil, !(NSApp.keyWindow is NSOpenPanel) else { return e }
                self.cancel?()
                return nil
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let escape { NSEvent.removeMonitor(escape) }
        escape = nil
        if Dictation.shared.listening { sendWhenDone = false; Dictation.shared.stop() }
    }

    private func cursorAtEnd() {
        view.window?.makeFirstResponder(task)
        task.currentEditor()?.selectedRange = NSRange(location: task.stringValue.count, length: 0)
    }

    /// The microphone on, or off if it's listening: what's said goes after what's already written.
    @objc private func speak() {
        if Dictation.shared.listening { Dictation.shared.stop(); return }
        if Speaker.shared.speaking { Speaker.shared.stop() }     // the Mac's voice would end up transcribed
        microphone.title = FishCard.micTitle(true)
        let placeholder = task.placeholderString
        task.placeholderString = tr("ouvindo…")
        let before = task.stringValue.trimmingCharacters(in: .whitespaces)
        Dictation.shared.begin(partial: { [weak self] text in
                                   guard let self else { return }
                                   self.task.stringValue = before.isEmpty ? text : before + " " + text
                                   self.fit()
                                   self.cursorAtEnd()
                               },
                               onError: { [weak self] e in
                                   self?.microphone.title = FishCard.micTitle(false)
                                   self?.task.placeholderString = e
                               },
                               end: { [weak self] in
                                   guard let self else { return }
                                   self.microphone.title = FishCard.micTitle(false)
                                   self.task.placeholderString = placeholder
                                   self.fit()
                                   self.cursorAtEnd()
                                   if self.sendWhenDone { self.sendWhenDone = false; self.sendClicked() }
                               })
    }

    /// The field grows with what's written in it, up to a point.
    func controlTextDidChange(_ obj: Notification) { fit() }

    private func fit() {
        let fits = task.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 1000)).height ?? 64
        taskHeight.constant = max(64, min(220, fits + 6))
    }

    /// ⌥↩ breaks the line; ↩ alone opens the session.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)), NSEvent.modifierFlags.contains(.option) {
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) { cancel?(); return true }
        return false
    }

    private func pickFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.directoryURL = URL(fileURLWithPath: folder)
        p.prompt = tr("Escolher")
        p.begin { [weak self] answer in
            guard let self, answer == .OK, let u = p.url else { return }
            self.folder = u.path
            self.where_.attributedTitle = self.folderTitle()
        }
    }

    @objc private func cancelClicked() { cancel?() }

    @objc private func sendClicked() {
        // still listening: the last words are on their way
        if Dictation.shared.listening { sendWhenDone = true; Dictation.shared.stop(); return }
        let named = model.stringValue.trimmingCharacters(in: .whitespaces)
        send?(agents[max(0, agent.indexOfSelectedItem)], folder, task.stringValue, named.isEmpty ? nil : named,
              leads.state == .on && SessionControl.enabled)
    }
}
