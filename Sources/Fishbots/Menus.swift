import AppKit
import ServiceManagement
import simd

/// The menus: the menu bar's fish, the plugins menu, a fish's right-click menu and the app's main menu.
extension AppDelegate {
    // MARK: - menu bar

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "Fishbots")
            b.imagePosition = .imageLeading
        }
        statusMenu.delegate = self
        statusItem.menu = statusMenu
    }

    private func fillStatusMenu(_ m: NSMenu) {
        m.removeAllItems()
        func item(_ t: String, _ s: Selector, _ k: String = "", on: Bool? = nil) {
            let i = NSMenuItem(title: tr(t), action: s, keyEquivalent: k)
            i.target = self
            if let on { i.state = on ? .on : .off }
            m.addItem(i)
        }
        for p in permissions.pending {
            let name = tank.fish(source: p.source, entity: p.session)?.label ?? p.session
            let title = NSMenuItem(title: tr("✋ %@ quer usar %@", name, p.tool), action: nil, keyEquivalent: "")
            title.toolTip = p.summary
            let sub = NSMenu()
            let summary = NSMenuItem(title: String(p.summary.prefix(70)), action: nil, keyEquivalent: "")
            summary.isEnabled = false
            sub.addItem(summary)
            sub.addItem(.separator())
            for (t, s) in [("Permitir", #selector(menuAllow(_:))), ("Negar", #selector(menuDeny(_:)))] {
                let i = NSMenuItem(title: t, action: s, keyEquivalent: "")
                i.target = self
                i.representedObject = p.id
                sub.addItem(i)
            }
            let go = NSMenuItem(title: tr("Ir até lá"), action: #selector(goFromMenu(_:)), keyEquivalent: "")
            go.target = self
            go.representedObject = p.fishId
            sub.addItem(go)
            title.submenu = sub
            m.addItem(title)
        }
        let attention = tank.fish.filter { !$0.decor && !$0.leaving && Attention.level($0.source, $0.state) >= .attention && permissions.request(ofFish: $0.id) == nil }
        if attention.isEmpty && permissions.pending.isEmpty {
            let i = NSMenuItem(title: tr("Ninguém esperando você"), action: nil, keyEquivalent: "")
            i.isEnabled = false
            m.addItem(i)
        }
        for f in attention {
            let icon = f.state == .waiting ? "✋" : f.state == .error ? "✗" : "⚠︎"
            let i = NSMenuItem(title: "\(icon) \(f.label)" + (f.sub.map { "  ·  " + $0 } ?? ""), action: #selector(goFromMenu(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = f.id
            if let t = f.displayTitle { i.toolTip = t }
            m.addItem(i)
        }
        m.addItem(.separator())
        if journal.pending != nil { item("🌙 Enquanto você estava fora…", #selector(openAwaySummary)) }
        item("Mostrar aquário", #selector(show))
        item("Alimentar", #selector(feed))
        item("Música ambiente", #selector(toggleAmbientMusic), on: UserDefaults.standard.bool(forKey: "ambientMusic"))
        item("Modo foco", #selector(toggleFocus), on: Attention.focus)
        item("Ler as perguntas em voz alta", #selector(toggleReadQuestions), on: readQuestions)
        m.addItem(menuVisualizer())
        m.addItem(menuTheme())
        item("Som", #selector(toggleMute), on: !synth.muted.load(ordering: .relaxed))
        m.addItem(.separator())
        item("Abrir no login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        item("Preferências…", #selector(showPreferences))
        item("Só na barra de menus", #selector(toggleMenuBarOnly), on: UserDefaults.standard.bool(forKey: "menuBarOnly"))
        m.addItem(.separator())
        let quit = NSMenuItem(title: tr("Sair do Fishbots"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        m.addItem(quit)
    }

    @objc private func goFromMenu(_ i: NSMenuItem) {
        if let id = i.representedObject as? String, let f = tank.fish.first(where: { $0.id == id }) { Whereabouts.go(f) }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let a = NSAlert()
            a.messageText = tr("Não consegui mudar a abertura no login")
            a.informativeText = error.localizedDescription + "\n\n" + tr("Rode o Fishbots como app (scripts/app.sh) e confira em Ajustes do Sistema → Geral → Itens de Início.")
            a.runModal()
        }
    }

    @objc func toggleMenuBarOnly() {
        let v = !UserDefaults.standard.bool(forKey: "menuBarOnly")
        UserDefaults.standard.set(v, forKey: "menuBarOnly")
        NSApp.setActivationPolicy(v ? .accessory : .regular)
        if !v { show() }
    }

    // MARK: - plugins menu (rebuilt every time it opens)

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu { fillStatusMenu(menu); return }
        guard menu === menuPlugins else { return }
        menu.removeAllItems()
        let states = (plugins?.states ?? [:]).sorted { $0.key < $1.key }
        if states.isEmpty {
            let i = NSMenuItem(title: tr("Nenhum plugin instalado"), action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = L10n.locale
        for (name, e) in states {
            var t = (e.ok ? "✓ " : "✗ ") + name
            if let d = e.lastRun { t += "  (\(fmt.localizedString(for: d, relativeTo: Date())))" }
            // clicking a plugin opens its log (every run, its stderr, the lines it got wrong)
            let i = NSMenuItem(title: t, action: #selector(openPluginLog(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = name
            i.toolTip = e.error ?? tr("abrir o log")
            menu.addItem(i)
            if let err = e.error {
                let ei = NSMenuItem(title: "    " + String(err.prefix(70)), action: #selector(openPluginLog(_:)), keyEquivalent: "")
                ei.target = self
                ei.representedObject = name
                menu.addItem(ei)
            }
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: tr("Abrir pasta de plugins"), action: #selector(openPlugins), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        if !states.isEmpty {
            let logs = NSMenuItem(title: tr("Abrir pasta de logs"), action: #selector(openPluginLogs), keyEquivalent: "")
            logs.target = self
            menu.addItem(logs)
        }
    }

    @objc func openPlugins() { Plugins.openFolder() }

    // MARK: - fish menu (right click)


    func fishMenu(_ p: CGPoint, _ e: NSEvent) {
        guard let f = tank.fish(at: [Float(p.x), Float(p.y)]) else {
            // on the water: the aquarium's own options
            let m = NSMenu()
            let w = NSMenuItem(title: tr("Modo widget (janelinha no canto)"), action: #selector(toggleWidget), keyEquivalent: "")
            w.target = self
            w.state = tank.compact ? .on : .off
            m.addItem(w)
            let fl = NSMenuItem(title: tr("Alimentar"), action: #selector(feed), keyEquivalent: "")
            fl.target = self
            m.addItem(fl)
            NSMenu.popUpContextMenu(m, with: e, for: view)
            return
        }
        menuFish = f
        let m = NSMenu()
        let title = NSMenuItem(title: f.label + (f.sub.map { "  ·  " + $0 } ?? ""), action: nil, keyEquivalent: "")
        title.isEnabled = false
        m.addItem(title)
        m.addItem(.separator())
        func item(_ t: String, _ s: Selector, tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: tr(t), action: s, keyEquivalent: "")
            i.target = self
            i.tag = tag
            return i
        }
        m.addItem(item(f.link != nil ? "Abrir link" : "Ir até lá", #selector(menuGo)))
        if f.source == NowPlaying.source {
            let ears = item("Visualizadores dançam com essa música", #selector(toggleSongEars))
            ears.state = SongEars.enabled ? .on : .off
            m.addItem(ears)
        }
        // actions from the registry (built-ins, providers and config.json)
        for a in FishActions.all where a.when(f) {
            let it = item(a.title, #selector(menuAction(_:)))
            it.representedObject = a.id
            m.addItem(it)
        }
        m.addItem(.separator())

        // change the motif: hovering plays the option
        let swap = NSMenuItem(title: tr("Trocar motivo"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let current = item("Atual", #selector(menuMotif(_:)), tag: f.motif + 1)
        current.state = .on
        sub.addItem(current)
        let used = Set(tank.fish.filter { !$0.decor }.map(\.motif))
        for (i, mt) in Motifs.options(4, avoiding: used).enumerated() {
            sub.addItem(item(tr("Opção %d", i + 1), #selector(menuMotif(_:)), tag: mt + 1))
        }
        previewMotif.play = { [weak self, weak f] mt in
            guard let self, let f else { return }
            self.music.preview(motif: mt, timbre: f.timbre)
        }
        sub.delegate = previewMotif
        swap.submenu = sub
        m.addItem(swap)

        // the project's fish kind (overrides the session provider's choice)
        let kinds = NSMenuItem(title: tr("Tipo de peixe"), action: nil, keyEquivalent: "")
        let km = NSMenu()
        let auto = item("Automático", #selector(menuFishKind(_:)))
        auto.state = FishKinds.override(for: f.projectKey) == nil ? .on : .off
        km.addItem(auto)
        km.addItem(.separator())
        for k in FishKinds.all {
            let it = item(k.name, #selector(menuFishKind(_:)))
            it.representedObject = k.id
            it.state = FishKinds.override(for: f.projectKey) == k.id ? .on : .off
            km.addItem(it)
        }
        kinds.submenu = km
        m.addItem(kinds)

        if cards.canReply(f) { m.addItem(item("Responder…", #selector(menuReply))) }
        if cards.canStop(f) { m.addItem(item("Parar (Esc)", #selector(menuStop))) }
        m.addItem(item(f.nickname == nil ? "Dar um nome…" : "Mudar o nome…", #selector(menuNickname)))
        if cards.can(.renameChat, f) {
            m.addItem(item("Renomear a conversa…", #selector(menuRenameChat)))
        }
        if f.whereabouts["rex_block"] != nil { m.addItem(item("Renomear o painel no Rex…", #selector(menuRenamePane))) }
        if f.whereabouts["rex_session"] != nil { m.addItem(item("Renomear a sessão no Rex…", #selector(menuRenameRex))) }
        m.addItem(.separator())
        let sil = item("Silenciar este projeto", #selector(menuMute))
        sil.state = Motifs.muted(f.projectKey) ? .on : .off
        m.addItem(sil)
        m.addItem(.separator())
        m.addItem(item("Tirar do aquário", #selector(menuRemove)))
        NSMenu.popUpContextMenu(m, with: e, for: view)
    }

    @objc private func menuFishKind(_ i: NSMenuItem) {
        guard let f = menuFish else { return }
        FishKinds.setOverride(i.representedObject as? String, for: f.projectKey)
        for o in tank.fish where o.projectKey == f.projectKey { Providers.refresh(o) }
    }
    @objc private func openPluginLog(_ i: NSMenuItem) { if let n = i.representedObject as? String { Plugins.openLog(n) } }
    @objc private func openPluginLogs() {
        try? FileManager.default.createDirectory(at: Plugins.logFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Plugins.logFolder)
    }
    @objc private func toggleSongEars() { SongEars.enabled.toggle() }
    @objc private func menuGo() { if let f = menuFish { Whereabouts.go(f) } }
    @objc private func menuAction(_ i: NSMenuItem) {
        guard let f = menuFish, let id = i.representedObject as? String, let a = FishActions.all.first(where: { $0.id == id }) else { return }
        a.run(f)
    }
    @objc private func menuMotif(_ i: NSMenuItem) {
        guard let f = menuFish, i.tag > 0 else { return }
        let mt = i.tag - 1
        Motifs.swap(f.projectKey, to: mt)
        for g in tank.fish where g.projectKey == f.projectKey { g.motif = mt; g.intro = true }
    }
    @objc private func menuMute() {
        guard let f = menuFish else { return }
        Motifs.mute(f.projectKey, !Motifs.muted(f.projectKey))
    }
    @objc private func menuRemove() { menuFish?.leaving = true }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(chooseTheme(_:)): item.state = (item.representedObject as? String) == Themes.current.id ? .on : .off
        case #selector(chooseVisual(_:)): item.state = (item.representedObject as? String) == visual.choice ? .on : .off
        case #selector(toggleAuroraBackground): item.state = visual.auroraBackground ? .on : .off
        case #selector(toggleFocus): item.state = Attention.focus ? .on : .off
        case #selector(toggleReadQuestions): item.state = readQuestions ? .on : .off
        case #selector(toggleAmbientMusic): item.state = UserDefaults.standard.bool(forKey: "ambientMusic") ? .on : .off
        case #selector(toggleToolNotes): item.state = UserDefaults.standard.bool(forKey: "toolNotes") ? .on : .off
        case #selector(toggleNotifyWaiting): item.state = Attention.level("*", .waiting) == .urgent ? .on : .off
        case #selector(toggleNotifyError): item.state = Attention.level("*", .error) == .urgent ? .on : .off
        case #selector(toggleDemo): item.state = demo.on ? .on : .off
        case #selector(toggleFloat): item.state = window.level == .floating ? .on : .off
        case #selector(toggleWidget): item.state = tank.compact ? .on : .off
        case #selector(toggleMute): item.state = synth.muted.load(ordering: .relaxed) ? .off : .on
        case #selector(toggleLogin): item.state = SMAppService.mainApp.status == .enabled ? .on : .off
        case #selector(toggleMenuBarOnly): item.state = UserDefaults.standard.bool(forKey: "menuBarOnly") ? .on : .off
        case #selector(toggleSongEars): item.state = SongEars.enabled ? .on : .off
        default: break
        }
        return true
    }

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        // one menu per kind of thing: the app, editing (the card's reply field), the aquarium's look, the sessions
        // and your attention, sound, plugins, the window
        func add(_ m: NSMenu, _ t: String, _ s: Selector, _ k: String = "", _ mods: NSEvent.ModifierFlags = .command) {
            let i = NSMenuItem(title: tr(t), action: s, keyEquivalent: k)
            i.keyEquivalentModifierMask = mods
            i.target = self
            m.addItem(i)
        }
        func submenu(_ title: String, _ m: NSMenu) {
            let i = NSMenuItem()
            m.title = tr(title)
            i.submenu = m
            main.addItem(i)
        }

        add(appMenu, "Preferências…", #selector(showPreferences), ",")
        appMenu.addItem(.separator())
        add(appMenu, "Abrir no login", #selector(toggleLogin))
        add(appMenu, "Só na barra de menus", #selector(toggleMenuBarOnly))
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Esconder Fishbots"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Sair do Fishbots"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // Editing: without it, ⌘C/⌘V/⌘A/⌘Z don't reach text fields (the card's reply field)
        let edit = NSMenu()
        edit.addItem(withTitle: tr("Desfazer"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: tr("Refazer"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: tr("Recortar"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: tr("Copiar"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: tr("Colar"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: tr("Selecionar tudo"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        submenu("Editar", edit)

        // The aquarium: what it looks like
        let aq = NSMenu()
        add(aq, "Alimentar", #selector(feed), "f")
        aq.addItem(.separator())
        aq.addItem(menuTheme())
        aq.addItem(menuVisualizer())
        add(aq, "Rótulos: mínimo / completo / nenhum", #selector(cycleLabels), "l")
        aq.addItem(.separator())
        add(aq, "Modo demo", #selector(toggleDemo), "d")
        submenu("Aquário", aq)

        // Sessions: who needs you, and how the aquarium calls you
        let sessions = NSMenu()
        add(sessions, "Ir para quem espera há mais tempo", #selector(goToLongestWaiting))
        add(sessions, "Ouvir a pergunta de quem espera", #selector(readLongestWaiting))
        add(sessions, "Responder falando (abre o microfone)", #selector(replyByVoice))
        sessions.addItem(.separator())
        add(sessions, "Resumo das últimas 2 horas", #selector(recentSummary), "r")
        add(sessions, "Modo foco (só o que pede atenção)", #selector(toggleFocus), "s")
        sessions.addItem(.separator())
        add(sessions, "Notificar quando esperarem por você", #selector(toggleNotifyWaiting))
        add(sessions, "Notificar erros", #selector(toggleNotifyError))
        add(sessions, "Abrir configuração de atenção…", #selector(openConfig))
        submenu("Sessões", sessions)

        // Sound: what you hear
        let sound = NSMenu()
        add(sound, "Som ligado", #selector(toggleMute), "m")
        sound.addItem(.separator())
        add(sound, "Música ambiente (tocar o tempo todo)", #selector(toggleAmbientMusic), "a", [.command, .shift])
        add(sound, "Nota a cada ferramenta usada", #selector(toggleToolNotes))
        add(sound, "Ler as perguntas em voz alta", #selector(toggleReadQuestions))
        add(sound, "Visualizadores dançam com essa música", #selector(toggleSongEars))
        submenu("Som", sound)

        let plItem = NSMenuItem()
        main.addItem(plItem)
        menuPlugins.delegate = self
        for i in NSApp.mainMenu?.items ?? [] where i.submenu === menuPlugins { i.submenu = nil }   // rebuilding (new language)
        plItem.submenu = menuPlugins

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let win = NSMenu(title: tr("Janela"))
        add(win, "Flutuar sobre as janelas", #selector(toggleFloat), "t")
        add(win, "Modo widget (janelinha no canto)", #selector(toggleWidget), "w", [.command, .option])
        win.addItem(.separator())
        win.addItem(withTitle: tr("Fechar (continua na barra de menus)"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: tr("Minimizar"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "")
        win.addItem(withTitle: tr("Tela cheia"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }
}
