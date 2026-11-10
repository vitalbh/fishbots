import AppKit
import simd

/// Themes, visualizers and packs in the app: their menus and what the menu items do (the work is ThemeKeeper's).
extension AppDelegate {
    /// Visualizer submenu: automatic, random, off and each one.
    func menuVisualizer() -> NSMenuItem {
        let item = NSMenuItem(title: tr("Visualizador"), action: nil, keyEquivalent: "")
        let m = NSMenu()
        let background = NSMenuItem(title: tr("✨ Aurora de fundo"), action: #selector(toggleAuroraBackground), keyEquivalent: "")
        background.target = self
        m.addItem(background)
        m.addItem(.separator())
        let options: [(String, String)] = [("auto", "Automático (pelo estilo)"), ("random", "Aleatório (troca a cada peça)"), ("off", "Só a aurora / nenhum")]
            + Visualizers.all.map { ($0.id, $0.title) }
        for (i, (id, t)) in options.enumerated() {
            if i == 3 { m.addItem(.separator()) }
            let it = NSMenuItem(title: tr(t), action: #selector(chooseVisual(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = id
            m.addItem(it)
        }
        item.submenu = m
        return item
    }

    @objc func toggleAuroraBackground() { visual.auroraBackground.toggle() }

    func menuTheme() -> NSMenuItem {
        let item = NSMenuItem(title: tr("Tema"), action: nil, keyEquivalent: "")
        let m = NSMenu()
        for t in Themes.all {
            let it = NSMenuItem(title: t.displayName, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = t.id
            if let img = themeKeeper.swatches[t.id] { it.image = NSImage(cgImage: img, size: NSSize(width: 54, height: 36)) }
            m.addItem(it)
        }
        themeKeeper.drawSwatches()
        m.addItem(.separator())
        for p in Packs.loaded {
            let it = NSMenuItem(title: "📦 \(p.name)" + (p.contents.isEmpty ? "" : ": " + p.contents.joined(separator: ", ")), action: nil, keyEquivalent: "")
            it.isEnabled = false
            m.addItem(it)
        }
        for problem in Packs.problems {
            let it = NSMenuItem(title: "⚠︎ " + problem, action: nil, keyEquivalent: "")
            it.isEnabled = false
            m.addItem(it)
        }
        let pick = NSMenuItem(title: tr("Escolher tema…"), action: #selector(openThemePicker), keyEquivalent: "e")
        pick.target = self
        m.insertItem(pick, at: 0)
        m.insertItem(.separator(), at: 1)
        let explore = NSMenuItem(title: tr("Explorar pacotes…") + (themeKeeper.catalogUpdates > 0 ? "  " + tr("(%@ atualização)", "\(themeKeeper.catalogUpdates)") : ""),
                                 action: #selector(explorePacks), keyEquivalent: "")
        explore.target = self
        m.addItem(explore)
        let open = NSMenuItem(title: tr("Abrir pasta de pacotes…"), action: #selector(openPacks), keyEquivalent: "")
        open.target = self
        m.addItem(open)
        let reload = NSMenuItem(title: tr("Recarregar pacotes"), action: #selector(reloadPacks), keyEquivalent: "")
        reload.target = self
        m.addItem(reload)
        for p in Packs.pausedFound {
            let it = NSMenuItem(title: tr("Reativar %@", p.name), action: #selector(resumePack(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = p.id
            m.addItem(it)
        }
        item.submenu = m
        return item
    }
    @objc func openPacks() { NSWorkspace.shared.open(Packs.folder) }

    @objc func reloadPacks() { themeKeeper.reloadPacks() }

    @objc func explorePacks() { catalogWindow.show() }

    @objc func resumePack(_ i: NSMenuItem) {
        if let id = i.representedObject as? String { themeKeeper.resume(id) }
    }

    /// Reads agents/*.json again (the Agents section's button, POST /agents/reload): manifests rarely change, so
    /// there's no watching; the app also reads them when it opens.
    func reloadAgents() {
        AgentManifests.load(fish: tank.fish)
        let n = AgentManifests.problems.count
        tank.notice = (n == 0 ? tr("agentes recarregados") : tr("agentes recarregados, %@ problema(s): veja Preferências → Geral", "\(n)"), tank.time)
    }

    /// A .fishbotspack opened in the Finder (or dragged onto the app): installed and loaded.
    func application(_ application: NSApplication, open urls: [URL]) { themeKeeper.install(urls) }

    @objc func chooseTheme(_ i: NSMenuItem) {
        if let id = i.representedObject as? String { themeKeeper.use(id) }
    }

    @objc func openThemePicker() { themePicker.show() }

    @objc func chooseVisual(_ i: NSMenuItem) {
        if let id = i.representedObject as? String { visual.choice = id }
    }
}
