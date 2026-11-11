import AppKit

/// "Nova sessão…": the person starts a session from the aquarium itself, with its task, its folder and its agent.
/// It opens in a terminal host through the launchers, like one a session launches, but it's nobody's child; asked
/// to, it starts with the orchestrator skill in hand, so it can launch its own.
extension AppDelegate {
    @objc func newSession() {
        let agents = Providers.all.values.filter { $0.launchCommand(prompt: nil, model: nil) != nil }.sorted { $0.name < $1.name }
        guard !agents.isEmpty, Launchers.pick(nil, near: nil) != nil else {
            let a = NSAlert()
            a.messageText = tr("Não há onde abrir uma sessão")
            a.informativeText = tr("O aquário abre sessões no Rex, no Herdr ou no tmux, e nenhum deles está instalado.")
            a.runModal()
            return
        }
        let defaults = UserDefaults.standard
        let width: CGFloat = 440

        let task = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 96))
        task.font = .systemFont(ofSize: 13)
        task.isRichText = false
        task.textContainerInset = NSSize(width: 4, height: 6)
        task.autoresizingMask = [.width]
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 96))
        scroll.documentView = task
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let folder = NSPathControl()
        folder.pathStyle = .popUp
        folder.allowedTypes = ["public.folder"]
        folder.url = URL(fileURLWithPath: defaults.string(forKey: "newSessionFolder") ?? NSHomeDirectory())

        let agent = NSPopUpButton()
        for p in agents { agent.addItem(withTitle: p.name) }
        if let last = defaults.string(forKey: "newSessionAgent"), let i = agents.firstIndex(where: { $0.id == last }) { agent.selectItem(at: i) }

        let model = NSTextField(string: "")
        model.placeholderString = tr("modelo (vazio: o da conta)")

        let leads = NSButton(checkboxWithTitle: tr("Pode lançar outras sessões e comandá-las (orquestrar)"), target: nil, action: nil)
        leads.state = SessionControl.enabled && defaults.object(forKey: "newSessionLeads") as? Bool ?? true ? .on : .off
        leads.isEnabled = SessionControl.enabled
        if !SessionControl.enabled { leads.toolTip = tr("Ligue \"Sessões podem comandar outras\" em Preferências → Geral") }

        let pick = NSStackView(views: [agent, model])
        pick.orientation = .horizontal
        pick.spacing = 8
        let stack = NSStackView(views: [scroll, folder, pick, leads])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: width, height: 210)
        for v in [scroll, folder, pick] as [NSView] { v.widthAnchor.constraint(equalToConstant: width).isActive = true }
        scroll.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let a = NSAlert()
        a.messageText = tr("Nova sessão")
        a.informativeText = tr("O que ela deve fazer, em que pasta e com qual agente. Ela abre no terminal e aparece aqui como um peixe.")
        a.addButton(withTitle: tr("Abrir"))
        a.addButton(withTitle: tr("Cancelar"))
        a.accessoryView = stack
        a.window.initialFirstResponder = task
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn, let dir = folder.url?.path else { return }

        let chosen = agents[max(0, agent.indexOfSelectedItem)]
        let words = task.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let leading = leads.state == .on && SessionControl.enabled
        defaults.set(dir, forKey: "newSessionFolder")
        defaults.set(chosen.id, forKey: "newSessionAgent")
        if SessionControl.enabled { defaults.set(leading, forKey: "newSessionLeads") }
        var prompt: String? = words.isEmpty ? nil : words
        if leading {
            prompt = "Use the fishbots-orchestrator skill: where it helps, split this work across sessions with `fishbots spawn`, "
                + "follow them and bring their results together." + (words.isEmpty ? " Ask me what the work is." : "\n\n" + words)
        }
        let named = model.stringValue.trimmingCharacters(in: .whitespaces)
        sessionControl.open(agent: chosen.id, cwd: dir, prompt: prompt, model: named.isEmpty ? nil : named) { failure in
            guard let failure else { return }
            let e = NSAlert()
            e.messageText = tr("Não consegui abrir a sessão")
            e.informativeText = failure
            e.runModal()
        }
    }
}
