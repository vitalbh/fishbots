import AppKit
import simd

/// Themes, visualizers and packs: their menus, applying a theme, reloading and watching the packs, the catalog.
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
            if let img = themeSwatches[t.id] { it.image = NSImage(cgImage: img, size: NSSize(width: 54, height: 36)) }
            m.addItem(it)
        }
        drawThemeSwatches()
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
        let explore = NSMenuItem(title: tr("Explorar pacotes…") + (catalogUpdates > 0 ? "  " + tr("(%@ atualização)", "\(catalogUpdates)") : ""),
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

    private func drawThemeSwatches() {
        let key = Themes.all.map(\.id).joined(separator: ",") + "|" + packsSignature
        guard key != swatchesFor else { return }
        swatchesFor = key
        let job = PackPreview.swatchJob(Themes.all)
        DispatchQueue.global(qos: .utility).async {
            let images = PackPreview.themeSwatches(job)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.swatchesFor == key, !images.isEmpty else { return }
                self.themeSwatches = images
                self.buildMenu()
            }
        }
    }

    /// Reads the packs again, recompiles the shader and applies the theme, without restarting (a pack being made).
    /// The fish keep their kind by its id (the indices may move).
    @objc func reloadPacks() {
        let kinds = tank.fish.map { ($0, $0.kindID) }
        Packs.reload()
        let ok = renderer.reload()
        for (f, id) in kinds { f.species = FishKinds.index(of: id) }
        tank.scene.refreshPackKinds()
        applyTheme()
        buildMenu()
        packsSignature = Packs.signature()
        let n = Packs.problems.count
        tank.notice = (!ok ? tr("pacotes: o shader não compilou, ficou o anterior")
                       : n == 0 ? tr("pacotes recarregados") : tr("pacotes recarregados, %@ problema(s): veja o menu Tema", "\(n)"), tank.time)
    }

    /// The packs, what they bring and their problems, as JSON (GET /packs, and the answer of a reload).
    func packsJSON() -> Data {
        let obj: [String: Any] = ["packs": Packs.loaded.map { ["id": $0.id, "name": $0.name, "contents": $0.contents] },
                                  "problems": Packs.problems, "folder": Packs.folder.path]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    @objc func explorePacks() { catalogWindow.show() }

    /// Looks for newer versions of the installed packs (at launch and once a day).
    func checkCatalog() {
        PackCatalog.fetch { [weak self] r in
            guard let self, case .success(let entries) = r else { return }
            let n = entries.filter(PackCatalog.hasUpdate).count
            if n != self.catalogUpdates { self.catalogUpdates = n; self.buildMenu() }
            if n > 0 { self.tank.notice = (tr("%@ pacote(s) com versão nova: Tema → Explorar pacotes", "\(n)"), self.tank.time) }
        }
    }

    @objc func resumePack(_ i: NSMenuItem) {
        guard let id = i.representedObject as? String else { return }
        Packs.resume(id)
        reloadPacks()
    }

    func watchPacks() {
        packsSignature = Packs.signature()
        packsWatch = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if UserDefaults.standard.object(forKey: "watchPacks") as? Bool ?? true {
                let sig = Packs.signature()
                if sig != self.packsSignature { self.packsSignature = sig; Packs.resumeLinked(); self.reloadPacks() }
            }
        }
    }

    /// Reads agents/*.json again (the Agents section's button, POST /agents/reload): manifests rarely change, so
    /// there's no watching; the app also reads them when it opens.
    func reloadAgents() {
        AgentManifests.load(fish: tank.fish)
        let n = AgentManifests.problems.count
        tank.notice = (n == 0 ? tr("agentes recarregados") : tr("agentes recarregados, %@ problema(s): veja Preferências → Geral", "\(n)"), tank.time)
    }

    /// A .fishbotspack opened in the Finder (or dragged onto the app): installed and loaded.
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls where u.pathExtension.lowercased() == "fishbotspack" {
            do {
                let id = try Packs.install(u)
                reloadPacks()
                tank.notice = (tr("pacote instalado: %@", Packs.loaded.first { $0.id == id }?.name ?? id), tank.time)
            } catch {
                tank.notice = (tr("pacote não instalado: %@", error.localizedDescription), tank.time)
            }
        }
    }
    @objc func chooseTheme(_ i: NSMenuItem) {
        guard let id = i.representedObject as? String else { return }
        useTheme(id)
    }
    func useTheme(_ id: String) {
        Themes.current = Themes.named(id)
        applyTheme()
        tank.notice = (tr("tema: ") + Themes.current.displayName, tank.time)
        preferences.refresh()   // its Theme row shows the current one
    }

    @objc func openThemePicker() { themePicker.show() }

    /// The surprise mode: another theme by itself, every hour or every day (checked every minute).
    func surpriseTheme() {
        let d = UserDefaults.standard
        guard let mode = d.string(forKey: "surpriseTheme"), mode != "off" else { return }
        let every: Double = mode == "hour" ? 3600 : 86_400
        let at = d.double(forKey: "surpriseThemeAt")
        guard Date().timeIntervalSince1970 - at >= every else { return }
        d.set(Date().timeIntervalSince1970, forKey: "surpriseThemeAt")
        guard let next = Themes.all.filter({ $0.id != Themes.current.id }).randomElement() else { return }
        useTheme(next.id)
    }
    /// The scene's colors go to the shader; the seaweed count to the tank (the fish nibble it); the default visualizer.
    func applyTheme() {
        let t = Themes.current
        renderer.theme = t.uniforms
        tank.weeds.count = t.weedCount
        tank.rayStrength = t.uniforms.params.z
        visual.themeVisualizer = t.visualizer
        tank.fauna.select(t.fauna)
        tank.weeds.shapes = t.weedShapes
        tank.scenery.looks = t.looks
        tank.scenery.kinds = t.scenery
        // the theme's looks for presences and fish kinds (Preferences: "Vestir presenças e peixes com o tema")
        tank.scene.themeLooks = t.looks
        if appliedSchools != t.id { appliedSchools = t.id; tank.setSchools(t.schools ?? School.usual) }
        tank.scene.dressByTheme = FishKinds.dressByTheme
        dressedWith = (t.id, FishKinds.dressByTheme)
        for f in tank.fish where !f.decor { Providers.refresh(f) }      // (the music fish too: "looks": {"betta": …})
        Generator.preferredStyle = t.music
    }
    @objc func chooseVisual(_ i: NSMenuItem) {
        if let id = i.representedObject as? String { visual.choice = id }
    }
}
