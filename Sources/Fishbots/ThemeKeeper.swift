import AppKit
import simd

/// Keeps the tank dressed: applies the theme (water, seaweed, scenery, fauna, schools, music), reloads and watches
/// the packs, draws the themes' little pictures and knows how many packs have a newer version in the catalog.
/// The app builds the menus and the windows; this tells it when what they show has changed.
final class ThemeKeeper {
    private let tank: Tank
    private let visual: Visual
    /// Made with the window, a little after this.
    var renderer: Renderer!
    /// Something the menus show changed: the pictures, the packs, the catalog's count.
    var onChange: (() -> Void)?
    /// Another theme was chosen.
    var onTheme: (() -> Void)?

    /// The Tema menu's pictures, drawn in the background once per set of themes (and again after the packs change).
    private(set) var swatches: [String: CGImage] = [:]
    private var swatchesFor = ""
    /// How many installed packs have a newer version in the catalog.
    private(set) var catalogUpdates = 0
    /// The theme whose schools are swimming (they're made again only when the theme changes).
    private var appliedSchools = ""
    /// The theme and the dressing setting last applied (to notice when the setting changes).
    private(set) var dressedWith: (theme: String, on: Bool) = ("", true)
    /// The packs folder as last read: when a file changes (someone making a pack), it reloads by itself.
    private(set) var signature = ""
    private var watch: Timer?

    init(tank: Tank, visual: Visual) {
        self.tank = tank
        self.visual = visual
    }

    // MARK: - themes

    /// The scene's colors go to the shader; the seaweed count to the tank (the fish nibble it); the default visualizer.
    func apply() {
        let t = Themes.current
        renderer.theme = t.uniforms
        tank.weeds.count = t.weedCount
        tank.rayStrength = t.uniforms.params.z
        visual.themeVisualizer = t.visualizer
        tank.fauna.select(t.fauna)
        tank.weeds.shapes = t.weedShapes
        tank.scenery.pack = Packs.themePack[t.id]
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

    func use(_ id: String) {
        Themes.current = Themes.named(id)
        apply()
        tank.notice = (tr("tema: ") + Themes.current.displayName, tank.time)
        onTheme?()
    }

    /// The surprise mode: another theme by itself, every hour or every day (checked every minute).
    func surprise() {
        let d = UserDefaults.standard
        guard let mode = d.string(forKey: "surpriseTheme"), mode != "off" else { return }
        let every: Double = mode == "hour" ? 3600 : 86_400
        let at = d.double(forKey: "surpriseThemeAt")
        guard Date().timeIntervalSince1970 - at >= every else { return }
        d.set(Date().timeIntervalSince1970, forKey: "surpriseThemeAt")
        guard let next = Themes.all.filter({ $0.id != Themes.current.id }).randomElement() else { return }
        use(next.id)
    }

    /// Draws the pictures again if the themes or the packs changed since the last time.
    func drawSwatches() {
        let key = Themes.all.map(\.id).joined(separator: ",") + "|" + signature
        guard key != swatchesFor else { return }
        swatchesFor = key
        let job = PackPreview.swatchJob(Themes.all)
        DispatchQueue.global(qos: .utility).async {
            let images = PackPreview.themeSwatches(job)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.swatchesFor == key, !images.isEmpty else { return }
                self.swatches = images
                self.onChange?()
            }
        }
    }

    // MARK: - packs

    /// Reads the packs again, recompiles the shader and applies the theme, without restarting (a pack being made).
    /// The fish keep their kind by its id (the indices may move).
    func reloadPacks() {
        let kinds = tank.fish.map { ($0, $0.kindID) }
        Packs.reload()
        let ok = renderer.reload()
        for (f, id) in kinds { f.species = FishKinds.index(of: id) }
        tank.scene.refreshPackKinds()
        apply()
        onChange?()
        signature = Packs.signature()
        let n = Packs.problems.count
        tank.notice = (!ok ? tr("pacotes: o shader não compilou, ficou o anterior")
                       : n == 0 ? tr("pacotes recarregados") : tr("pacotes recarregados, %@ problema(s): veja o menu Tema", "\(n)"), tank.time)
    }

    /// The packs, what they bring and their problems, as JSON (GET /packs, and the answer of a reload).
    static func packsJSON() -> Data {
        let obj: [String: Any] = ["packs": Packs.loaded.map { ["id": $0.id, "name": $0.name, "contents": $0.contents] },
                                  "problems": Packs.problems, "folder": Packs.folder.path]
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// A paused pack (PackGuard) back on.
    func resume(_ id: String) {
        Packs.resume(id)
        reloadPacks()
    }

    /// .fishbotspack files opened in the Finder (or dragged onto the app): installed and loaded.
    func install(_ urls: [URL]) {
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

    /// Watches the packs folder (Preferências: on by default).
    func watchPacks() {
        signature = Packs.signature()
        watch = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if UserDefaults.standard.object(forKey: "watchPacks") as? Bool ?? true {
                let sig = Packs.signature()
                if sig != self.signature { self.signature = sig; Packs.resumeLinked(); self.reloadPacks() }
            }
        }
    }

    /// Looks for newer versions of the installed packs (at launch and once a day).
    func checkCatalog() {
        PackCatalog.fetch { [weak self] r in
            guard let self, case .success(let entries) = r else { return }
            let n = entries.filter(PackCatalog.hasUpdate).count
            if n != self.catalogUpdates { self.catalogUpdates = n; self.onChange?() }
            if n > 0 { self.tank.notice = (tr("%@ pacote(s) com versão nova: Tema → Explorar pacotes", "\(n)"), self.tank.time) }
        }
    }
}
