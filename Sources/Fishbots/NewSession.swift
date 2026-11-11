import AppKit

/// "Nova sessão…": the person starts a session from the aquarium itself, with its task, its folder and its agent.
/// It opens in a terminal host through the launchers, like one a session launches, but it's nobody's child; asked
/// to, it starts with the orchestrator skill in hand, so it can launch its own. A sheet on the aquarium's window, not
/// a modal dialog: the aquarium keeps running (and hearing its sessions) while the person writes.
extension AppDelegate {
    @objc func newSession() {
        let agents = Providers.all.values.filter { $0.launchCommand(prompt: nil, model: nil) != nil }.sorted { $0.name < $1.name }
        guard !agents.isEmpty, Launchers.pick(nil, near: nil) != nil else {
            let a = NSAlert()
            a.messageText = tr("Não há onde abrir uma sessão")
            a.informativeText = tr("O aquário abre sessões no Rex, no Herdr ou no tmux, e nenhum deles está instalado.")
            show()
            a.beginSheetModal(for: window)
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
        // the folder picked last time; the first time, where the most recent session works
        let recent = tank.fish.filter { $0.isAgent && !$0.decor && $0.whereabouts["cwd"] != nil }.max { $0.bornAt < $1.bornAt }?.whereabouts["cwd"]
        folder.url = URL(fileURLWithPath: defaults.string(forKey: "newSessionFolder") ?? recent ?? NSHomeDirectory())
        let folderLabel = NSTextField(labelWithString: tr("Pasta"))
        folderLabel.textColor = .secondaryLabelColor
        let place = NSStackView(views: [folderLabel, folder])
        place.orientation = .horizontal
        place.spacing = 8

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
        let stack = NSStackView(views: [scroll, place, pick, leads])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: width, height: 210)
        for v in [scroll, place, pick] as [NSView] { v.widthAnchor.constraint(equalToConstant: width).isActive = true }
        scroll.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let a = NSAlert()
        a.messageText = tr("Nova sessão")
        a.informativeText = tr("O que ela deve fazer, em que pasta e com qual agente. Ela abre no terminal e aparece aqui como um peixe.")
        a.addButton(withTitle: tr("Abrir"))
        a.addButton(withTitle: tr("Cancelar"))
        a.accessoryView = stack
        a.window.initialFirstResponder = task
        show()
        NSApp.activate(ignoringOtherApps: true)
        a.beginSheetModal(for: window) { [weak self] answer in
            guard let self, answer == .alertFirstButtonReturn, let dir = folder.url?.path else { return }
            let named = model.stringValue.trimmingCharacters(in: .whitespaces)
            self.open(agents[max(0, agent.indexOfSelectedItem)], in: dir, task: task.string, model: named.isEmpty ? nil : named,
                      leading: leads.state == .on && SessionControl.enabled)
        }
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
}
