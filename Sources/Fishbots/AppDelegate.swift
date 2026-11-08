import AppKit
import MetalKit
import QuartzCore
import simd
import ServiceManagement

/// The aquarium's window: it can take keys even without a title bar (widget mode).
final class TankWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class TankView: MTKView {
    /// Widget mode: dragging the empty water moves the window (it has no title bar).
    var dragMovesWindow: (() -> Bool)?
    var onKey: ((String) -> Void)?
    var onClick: ((CGPoint) -> Void)?
    var hits: ((CGPoint) -> Bool)?
    var onRightClick: ((CGPoint, NSEvent) -> Void)?
    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(convert(event.locationInWindow, from: nil), event)
    }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        (hits?(p) == true ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
    override func keyDown(with event: NSEvent) {
        if let c = event.charactersIgnoringModifiers?.lowercased() { onKey?(c) } else { super.keyDown(with: event) }
    }
    // a click counts on release, so it can be told from a drag; a double click knocks on the glass
    var onDrag: ((_ from: CGPoint, _ to: CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onKnock: ((CGPoint) -> Void)?
    var onScroll: ((CGPoint, CGFloat) -> Void)?
    private var downAt: CGPoint?
    private var dragging = false

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        downAt = p
        dragging = false
        if event.clickCount == 2 { onKnock?(p) }
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let d = downAt else { return }
        if !dragging && hypot(p.x - d.x, p.y - d.y) > 6 {
            if dragMovesWindow?() == true && hits?(d) != true { window?.performDrag(with: event); downAt = nil; return }
            dragging = true
        }
        if dragging { onDrag?(d, p) }
    }
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if dragging { onDragEnd?() } else if event.clickCount < 2 { onClick?(p) }
        downAt = nil
        dragging = false
    }
    override func scrollWheel(with event: NSEvent) {
        onScroll?(convert(event.locationInWindow, from: nil), event.scrollingDeltaY)
    }
}

/// Text layer on top of Metal: fish names and the footer.
final class LabelsView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isFlipped: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private var window: NSWindow!
    private var view: TankView!
    private var labels: LabelsView!
    private var renderer: Renderer!
    private let tank = Tank()
    private let synth = Synth()
    private var music: Music!
    private var server: Server?
    private var mac: MacSource?
    private var demo: Demo!
    private var musicTimer: Timer?
    private var textLayers: [String: CATextLayer] = [:]
    private let footer = CATextLayer()
    private var footerOpacity: Float = 1
    private let banner = CATextLayer()
    private let batteryText = CATextLayer()
    private let calmText = CATextLayer()
    private var activity: NSObjectProtocol?
    private var port: UInt16 = 7777
    private let notifier = Notifier()
    private let visual = Visual()
    private let permissions = Permissions()
    private let journal = Journal()
    private var outsideButton: NSButton?
    private var card: SummaryView?
    private var popover: NSPopover?
    private var hoverId: String?
    private var hoverSince = Date()
    private var hoverCard: NSPopover?
    private var hoverCardId: String?
    private var cardSignature = ""
    private var cardCheckedAt = Date.distantPast
    private var hoverBattery = false
    private var hoverPearl: Tank.Pearl?
    /// Presences (docs/scene.md): their text layers and the one under the mouse.
    private var presenceLayers: [String: CATextLayer] = [:]
    private var hoverPresence: String?
    private let pearlText = CATextLayer()
    private var plugins: Plugins?
    private var nowPlaying: NowPlaying?
    private let menuPlugins = NSMenu(title: "Plugins")
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Providers.registerBuiltIns()
        // a new interface language: menus and notification buttons are rebuilt (labels, cards and the footer follow by themselves)
        L10n.onChange = { [unowned self] in
            self.buildMenu()
            self.notifier.languageChanged()
            self.closeCard()
        }
        tank.profile = Providers.profile
        Packs.load()   // before the renderer compiles the shader (fish kinds) and the theme is applied
        Renderer.packFishFailed = Packs.fishFailed
        TankProtocol.stateExtras = { ["packs": Packs.loaded.map { ["id": $0.id, "name": $0.name, "contents": $0.contents] },
                                      "packProblems": Packs.problems, "fishKinds": FishKinds.all.map(\.id),
                                      "notifications": self.notifier.permission, "onScreen": self.onScreen] }
        notifier.prepare()
        if let p = Env.value("PORT"), let n = UInt16(p) { port = n }
        buildMenu()

        window = TankWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Fishbots"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.minSize = NSSize(width: 480, height: 320)
        window.center()
        window.setFrameAutosaveName("Fishbots")
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            self?.visibilityChanged()
        }
        window.isReleasedWhenClosed = false

        view = TankView(frame: window.contentView!.bounds, device: MTLCreateSystemDefaultDevice())
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .bgra8Unorm
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let r = Renderer(view: view) else {
            let a = NSAlert(); a.messageText = tr("Não consegui iniciar o Metal."); a.runModal(); NSApp.terminate(nil); return
        }
        renderer = r
        view.delegate = renderer
        window.contentView!.addSubview(view)

        labels = LabelsView(frame: view.bounds)
        labels.autoresizingMask = [.width, .height]
        labels.wantsLayer = true
        window.contentView!.addSubview(labels)
        setupFooter()

        renderer.frame = { [unowned self] dt in self.frame(dt) }
        applyTheme()
        view.onKey = { [unowned self] k in self.key(k) }
        view.onClick = { [unowned self] p in self.click(p) }
        view.dragMovesWindow = { [unowned self] in self.tank.compact }
        // drag a fish to nudge it, or the water to make a current; double click knocks; scrolling sprinkles food
        view.onDrag = { [unowned self] from, to in
            self.tank.drag(from: [Float(from.x), Float(from.y)], to: [Float(to.x), Float(to.y)])
        }
        view.onDragEnd = { [unowned self] in self.tank.endDrag() }
        view.onKnock = { [unowned self] p in
            let q: SIMD2<Float> = [Float(p.x), Float(p.y)]
            guard self.tank.fish(at: q) == nil else { return }
            self.tank.knock(at: q)
            if !Attention.focus { self.music.sceneSound("glass", cue: .effect, x: q.x / max(1, self.tank.size.x)) }
        }
        view.onScroll = { [unowned self] p, dy in self.tank.sprinkle(at: [Float(p.x), Float(p.y)], amount: Float(abs(dy))) }
        view.onRightClick = { [unowned self] p, e in self.fishMenu(p, e) }
        view.hits = { [unowned self] p in
            let q: SIMD2<Float> = [Float(p.x), Float(p.y)]
            self.tank.moveCursor(q)
            let f = self.tank.fish(at: q)
            if f?.id != self.hoverId { self.hoverSince = Date() }
            self.hoverId = f?.id
            self.hoverBattery = self.tank.battery != nil && simd_distance(q, self.tank.batteryPos) < 26
            let presence = f == nil ? self.tank.scene.presence(at: q) : nil
            self.hoverPresence = presence?.id
            self.hoverPearl = f == nil && presence == nil ? self.tank.pearl(at: q) : nil
            return f != nil || presence != nil || self.tank.chest(at: q)
        }
        // session, tab and title names change: refresh every so often
        Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [unowned self] _ in
            // pane and tab names only matter on screen (each refresh asks Rex)
            if self.onScreen { for f in self.tank.fish where !f.decor && !f.whereabouts.isEmpty { Whereabouts.detail(f) } }
            // lingering error (over 12 min): becomes urgent once
            for f in self.tank.fish where !f.decor && !f.leaving && f.state == .error && !f.escalated
                && self.tank.time - f.since > 720 * Tank.scale && Attention.level(f.source, .error) >= .attention {
                f.escalated = true
                self.notifier.notify(f)
            }
        }

        synth.start()
        music = Music(synth: synth, tank: tank)
        music.visual = visual
        music.called = { [unowned self] f, delay in self.readQuestion(f, after: delay) }
        // the Mac's voice ducks the music while it speaks
        applyVolume()
        Speaker.shared.muffle = { [unowned self] on in self.applyVolume(ducked: on) }
        tank.onSplash = { [unowned self] x in self.visual.splash(x: x) }
        // scene sounds: silent in focus mode; alert and error follow the attention rules, like the fish
        tank.scene.onSound = { [unowned self] voice, cue, source, state, x in
            guard !Attention.focus else { return }
            if let state, state == .alert || state == .error, Attention.level(source, state) < .attention { return }
            self.music.sceneSound(voice, cue: cue, x: x)
        }
        // scene effects that live in the visualizer (docs/scene.md)
        tank.scene.onEffect = { [unowned self] name, p, color in
            switch name {
            case "fireworks":
                for i in 0..<3 {
                    let at = p + [Float.random(in: -150...150), Float.random(in: -40...50)]
                    let c = i == 1 ? mix(color, [1, 1, 1], t: 0.45) : color
                    self.tank.after(Double(i) * 0.45) { [unowned self] in self.visual.fire(at: at, n: 28, radius: 100, color: c) }
                }
            case "shooting-star":
                let a: SIMD2<Float> = [p.x - self.tank.size.x * 0.22, p.y + 14]
                self.visual.line(from: a, until: p, color: SIMD4(color, 1), life: 1.1, width: 1.6, vel: [self.tank.size.x * 0.18, -10])
                self.tank.after(0.25) { [unowned self] in self.tank.sparkle(at: p + [self.tank.size.x * 0.05, -3], color: color) }
            default: break
            }
        }
        tank.fauna.onWhale = { [unowned self] in self.music.whaleSong() }
        tank.onEvent = { [unowned self] p in
            self.visual.event(at: p)
            if let (txt, t) = self.tank.notice, self.tank.time - t < 0.5 { self.journal.record(.event, txt) }
        }
        musicTimer = Timer(timeInterval: 0.02, repeats: true) { [unowned self] _ in self.music.tick() }
        RunLoop.main.add(musicTimer!, forMode: .common)
        // no App Nap: the music can't lag when the window is hidden
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                                                         reason: "música do aquário")

        Attention.reload()
        tank.onState = { [unowned self] f, before in self.stateChanged(f, before) }
        tank.onParty = { [unowned self] f in
            if f.source != "fry" { self.journal.record(.merge, f.label, fish: f.id) }
            Outputs.emit(TankEvent(type: "party", fish: f))
        }
        journal.returned = { [unowned self] in self.showOutsideButton() }
        notifier.decide = { [unowned self] request, action in self.decide(request, action) }
        notifier.go = { [unowned self] id in
            if let f = self.tank.fish.first(where: { $0.id == id }) { Whereabouts.go(f) }
        }

        demo = Demo(tank: tank)
        mac = MacSource(tank: tank)
        startServer()
        rememberSessions()
        plugins = Plugins(tank: tank)
        nowPlaying = NowPlaying(tank: tank)
        setupStatusItem()
        if UserDefaults.standard.bool(forKey: "menuBarOnly") { NSApp.setActivationPolicy(.accessory) }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSApp.activate(ignoringOtherApps: true)

        if Env.value("DEMO") == "1" { demo.turnOn() }
    }

    // closing the window doesn't quit: the aquarium keeps playing and monitoring from the menu bar
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return true
    }

    @objc func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - menu bar

    private func setupStatusItem() {
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

    func applicationDidBecomeActive(_ notification: Notification) { Attention.reload(); notifier.readPermission() }
    func applicationWillTerminate(_ notification: Notification) {
        SessionMemory.save(tank)
        plugins?.stop()
        permissions.releaseAll()
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
            let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
            i.isEnabled = false
            if let err = e.error { i.toolTip = err }
            menu.addItem(i)
            if let err = e.error {
                let ei = NSMenuItem(title: "    " + String(err.prefix(70)), action: nil, keyEquivalent: "")
                ei.isEnabled = false
                menu.addItem(ei)
            }
        }
        menu.addItem(.separator())
        let open = NSMenuItem(title: tr("Abrir pasta de plugins"), action: #selector(openPlugins), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
    }

    @objc func openPlugins() { Plugins.openFolder() }

    // MARK: - attention

    private let openedAt = Date()

    /// The window is on screen (not closed, minimized or fully covered).
    private var onScreen = true
    private var backgroundTick: Timer?

    /// Off screen, drawing stops (60 frames a second for nobody is most of the app's weight). The tank keeps ticking
    /// once a second, so its timers still run (a lingering error, sleeping, the whale…); sound and notices don't
    /// depend on drawing. Back on screen, it draws again.
    private func visibilityChanged() {
        let visible = window.occlusionState.contains(.visible)
        guard visible != onScreen else { return }
        onScreen = visible
        view.isPaused = !visible
        backgroundTick?.invalidate()
        backgroundTick = nil
        if visible {
            for f in tank.fish where !f.decor && !f.whereabouts.isEmpty { Whereabouts.detail(f) }
        } else {
            backgroundTick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.tank.update(dt: 0.05)
            }
        }
    }

    /// Sessions coming back from before the restart: no notices, no outputs.
    private var restoring = false

    /// The sessions from before the app restarted that are still alive come back quietly; then they're saved now and then.
    private func rememberSessions() {
        SessionMemory.restore { [weak self] saved in
            guard let self else { return }
            self.restoring = true
            defer { self.restoring = false }
            for s in saved where self.tank.fish(source: s.source, entity: s.entity) == nil {
                var state = State(wire: s.state) ?? .idle
                if state == .busy && Date().timeIntervalSince(s.lastSeen) > 120 { state = .idle }   // probably finished meanwhile
                self.tank.upsert(source: s.source, entity: s.entity, state: state, label: s.label)
                guard let f = self.tank.fish(source: s.source, entity: s.entity) else { continue }
                f.title = s.title; f.logTitle = s.logTitle; f.fixedTitle = s.fixedTitle; f.branch = s.branch
                f.context = s.context; f.lastReply = s.lastReply; f.link = s.link; f.transcriptPath = s.transcriptPath
                if state == .waiting { f.asked = s.asked }
                Whereabouts.restore(f, s.whereabouts)
                if let t = s.transcriptPath { Transcript.read(t, to: f, now: self.tank.time) }
            }
        }
        // a minute is enough: quitting saves too (this is for when the app is killed)
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            if let self { SessionMemory.save(self.tank) }
        }
    }

    private func stateChanged(_ f: Fish, _ before: State?) {
        if restoring { updateDock(); return }
        // whatever was already like this when the app opened isn't news
        if !f.decor && Date().timeIntervalSince(openedAt) > 20 {
            switch f.state {
            case .done:
                journal.record(.done, f.label, fish: f.id)
                // productive day (10 tasks): the whale swims by, once a day
                tank.fauna.maybeWhale(tank, tasksToday: tank.pearls.count)
            case .error: journal.record(.error, f.label, fish: f.id)
            case .waiting:
                journal.record(.waiting, f.label, fish: f.id)   // (the question is read after the knocks: music.called)
            default: break
            }
            Outputs.emit(TankEvent(type: "state", fish: f, previous: before))
        }
        if let before, Attention.level(f.source, before) == .urgent { notifier.clear(f) }
        if f.source != "decor", Attention.level(f.source, f.state) == .urgent { notifier.notify(f) }
        updateDock()
    }

    private func updateDock() {
        let n = max(tank.fish.filter { !$0.decor && !$0.leaving && $0.state == .waiting }.count, permissions.pending.count)
        NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
        statusItem?.button?.title = n > 0 ? " \(n)" : ""
    }

    // MARK: - server

    private func startServer() {
        ClaudeCodeHook.sessionContinued = { [unowned self] source, session, event in self.permissions.sessionContinued(source: source, session: session, event: event) }
        permissions.changed = { [unowned self] in self.updateDock() }
        do {
            server = try Server(port: port) { [unowned self] method, path, headers, body in
                let route = path.split(separator: "?").first.map(String.init) ?? path
                let path = path
                switch (method, route) {
                case ("POST", "/event"), ("POST", "/events"), ("POST", "/evento"), ("POST", "/eventos"):
                    return TankProtocol.apply(body, at: self.tank)
                case ("POST", "/test/whale"):
                    self.tank.fauna.callWhale(self.tank)
                    return (200, Data(#"{"ok":true}"#.utf8))
                case ("POST", "/test/card"):
                    // to test the hover card without moving the mouse
                    let goal = path.components(separatedBy: "f=").dropFirst().first?.removingPercentEncoding
                    if let f = self.tank.fish.first(where: { $0.isAgent && !$0.leaving && (goal == nil || $0.id.hasSuffix(goal!)) }) {
                        self.hoverId = f.id                      // pretend the mouse is over it, so the card doesn't close
                        self.hoverSince = Date(timeIntervalSinceNow: -1)
                        self.showCard(f)
                    }
                    return (200, Data(#"{"ok":true}"#.utf8))
                case ("POST", "/test/preferences"):
                    // to check the preferences window without clicking: ?tab=0…3
                    let tab = path.components(separatedBy: "tab=").dropFirst().first.flatMap { Int($0.prefix(1)) }
                    self.preferences.show(tab: tab)
                    return (200, Data(#"{"ok":true}"#.utf8))
                case ("POST", "/test/widget"):
                    self.toggleWidget()
                    return (200, Data(#"{"ok":true}"#.utf8))
                case ("POST", "/summary"):
                    self.recentSummary()
                    return (200, Data(#"{"ok":true}"#.utf8))
                case ("GET", "/state"), ("GET", "/estado"):
                    return (200, TankProtocol.state(self.tank))
                case ("GET", "/"):
                    let routes = ["POST /event"] + Providers.allRoutes.map { "POST " + $0 } + ["GET /state"]
                    return (200, (try? JSONSerialization.data(withJSONObject: ["fishbots": "ok", "routes": routes])) ?? Data())
                case ("POST", _):
                    if let (p, isPermission) = Providers.route(route), !isPermission {
                        return p.handle(route: route, body: body, headers: headers, tank: self.tank)
                    }
                    return (404, Data(#"{"error":"unknown route"}"#.utf8))
                default:
                    return (404, Data(#"{"error":"unknown route"}"#.utf8))
                }
            }
            server?.deferred = { [unowned self] method, path, headers, body, reply in
                let route = path.split(separator: "?").first.map(String.init) ?? path
                guard method == "POST", let (provider, isPermission) = Providers.route(route), isPermission else { return false }
                let source = provider.id
                guard let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { reply(400, Data()); return true }
                // the fish arrives/updates like a normal PermissionRequest, and the request stays waiting
                var ev = m; ev["hook_event_name"] = "PermissionRequest"
                if let d = try? JSONSerialization.data(withJSONObject: ev) {
                    let mainRoute = provider.routes.first { route.hasPrefix($0 + "/") } ?? route
                    _ = provider.handle(route: mainRoute, body: d, headers: headers, tank: self.tank)
                }
                if let p = self.permissions.add(m, source: source, reply: reply), let f = self.tank.fish(source: source, entity: p.session) {
                    Outputs.emit(TankEvent(type: "permission", fish: f, detail: p.tool + ": " + p.summary))
                    if Attention.level(source, .waiting) == .urgent { self.notifier.notify(f, request: p.id, summary: p.tool + ": " + p.summary) }
                }
                return true
            }
        } catch {
            FileHandle.standardError.write("fishbots: couldn't open port \(port): \(error)\n".data(using: .utf8)!)
        }
    }

    private func click(_ p: CGPoint) {
        closeCard()
        let q: SIMD2<Float> = [Float(p.x), Float(p.y)]
        if let f = tank.fish(at: q), let p = permissions.request(ofFish: f.id) {
            showRequest(p, fish: f)
            return
        }
        if let f = tank.fish(at: q) {
            f.glow = 1
            tank.ring(at: f.pos, color: [1, 1, 1], size: f.size * 0.5, grow: 140, life: 0.6)
            if !Whereabouts.go(f) {
                tank.notice = (tr("%@: não sei onde fica", f.label), tank.time)
            }
        } else if let p = tank.scene.presence(at: q) {
            // a presence: opens its link, or shows its text
            tank.ring(at: q, color: [1, 1, 1], size: p.kind.size * 0.4, grow: 120, life: 0.6)
            if let l = p.link, let u = URL(string: l) { NSWorkspace.shared.open(u) }
            else { tank.notice = (p.detail.map { "\(p.label): \($0)" } ?? p.label, tank.time) }
        } else if tank.chest(at: q) {
            recentSummary()         // the treasure chest keeps the last hours
        } else if !tank.scare(q) {
            tank.feed(at: q)        // away from everyone: food; near fish: they get startled
        }
    }

    // MARK: - while you were away

    private func showOutsideButton() {
        guard let p = journal.pending else { return }
        outsideButton?.removeFromSuperview()
        let b = NSButton(title: tr("🌙 Enquanto você estava fora · %@", Journal.duration(p.until.timeIntervalSince(p.since))),
                         target: self, action: #selector(openAwaySummary))
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(b)
        NSLayoutConstraint.activate([
            b.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            b.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 34),
        ])
        outsideButton = b
        statusItem?.button?.title = " 🌙"
    }

    @objc func openAwaySummary() {
        guard let p = journal.pending else { return }
        journal.discardPending()
        outsideButton?.removeFromSuperview()
        outsideButton = nil
        updateDock()
        summary(since: p.since, until: p.until, title: tr("Enquanto você estava fora (%@)", Journal.duration(p.until.timeIntervalSince(p.since))))
    }

    @objc func recentSummary() {
        let until = Date(), since = until.addingTimeInterval(-7200)
        summary(since: since, until: until, title: tr("Nas últimas 2 horas"))
    }

    /// The visual summary: the card and the parade of fish that did something, with the period's pearls lighting up.
    private func summary(since: Date, until: Date, title: String) {
        let list = journal.between(since, until)
        card?.removeFromSuperview()
        let c = SummaryView(title: title, lines: journal.text(list))
        c.close = { [weak self] in self?.card?.removeFromSuperview(); self?.card = nil; self?.tank.highlighted = nil; self?.tank.chestOpen = false }
        c.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(c)
        NSLayoutConstraint.activate([
            c.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            c.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 40),
        ])
        card = c
        show()
        tank.chestOpen = true          // the treasure chest opens while the summary is open

        tank.highlightPearls(since: since, until: until)
        // parade: each fish that did something comes to the front, one at a time
        var ids: [String] = []
        for a in list { if let id = a.fishId, !ids.contains(id), tank.fish.contains(where: { $0.id == id && !$0.leaving }) { ids.append(id) } }
        for (i, id) in ids.prefix(8).enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(i) * 2.2) { [weak self] in
                guard let self, self.card != nil else { return }
                self.tank.highlighted = id
                if let f = self.tank.fish.first(where: { $0.id == id }) {
                    self.tank.ring(at: f.pos, color: f.color, size: f.size * 0.6, grow: 120, life: 0.9)
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6 + Double(min(ids.count, 8)) * 2.2) { [weak self] in
            self?.tank.highlighted = nil
        }
    }

    // MARK: - labels (minimal / full / none)

    private var labelMode: String { UserDefaults.standard.string(forKey: "labels") ?? "minimal" }

    @objc func cycleLabels() {
        let next = ["minimal": "full", "full": "none", "none": "minimal"][labelMode] ?? "minimal"
        UserDefaults.standard.set(next, forKey: "labels")
        tank.notice = (tr("rótulos: ") + tr(["minimal": "mínimo", "full": "completo", "none": "nenhum"][next]!), tank.time)
    }

    /// One short line (title or name) and, only when it matters, a second colored line:
    /// always if it needs you (request, question, error); for a few seconds when something happens.
    private func minimalLabel(_ f: Fish, _ l: CATextLayer) {
        if labelMode == "none" { l.opacity = 0; return }
        func short(_ t: String, _ n: Int) -> String { t.count > n ? String(t.prefix(n - 1)) + "…" : t }
        let near = hoverId == f.id
        let name = f.nickname.map { short($0, 22) } ?? (f.isAgent ? short(f.displayTitle ?? f.label, 22) : f.label)
        let s = NSMutableAttributedString(string: name, attributes: [
            .font: rounded(10.5, .medium), .foregroundColor: NSColor(white: 1, alpha: near ? 0.95 : 0.6)])
        let today = min(5, f.finished.filter { Calendar.current.isDateInToday($0.when) }.count)
        if today > 0 {
            s.append(NSAttributedString(string: " " + String(repeating: "●", count: today), attributes: [
                .font: rounded(6.5), .foregroundColor: NSColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 0.7), .baselineOffset: 1.5]))
        }
        if let e = f.lastError, Date().timeIntervalSince(e) < 3600, f.state != .error {
            s.append(NSAttributedString(string: " ●", attributes: [
                .font: rounded(6.5), .foregroundColor: NSColor(red: 1, green: 0.4, blue: 0.35, alpha: 0.85), .baselineOffset: 1.5]))
        }
        let yellow = NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
        var line2: (String, NSColor)?
        if let p = permissions.request(ofFish: f.id) { line2 = (tr("✋ quer usar %@", p.tool), yellow) }
        else if f.state == .waiting { line2 = (f.asked.map { "✋ " + short($0, 38) } ?? tr("✋ esperando você"), yellow) }
        else if f.state == .error { line2 = (tr("✗ erro"), NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1)) }
        else if f.state == .alert { line2 = (tr("⚠︎ alerta"), NSColor(red: 1, green: 0.75, blue: 0.3, alpha: 1)) }
        else if f.compactingSince != nil { line2 = (tr("🫧 compactando…"), NSColor(white: 1, alpha: 0.6)) }
        else if let m = f.moment, tank.time < m.until {
            line2 = (m.text, NSColor(white: 1, alpha: CGFloat(min(1, m.until - tank.time)) * 0.6))
        }
        if let (t, color) = line2 {
            s.append(NSAttributedString(string: "\n" + t, attributes: [.font: rounded(10), .foregroundColor: color]))
        }
        l.string = s
        let sz = s.size()
        l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
        l.position = CGPoint(x: CGFloat(f.pos.x), y: CGFloat(f.pos.y - f.size * 0.75) - l.bounds.height / 2)
        l.opacity = f.leaving ? 0.3 : 1
        l.zPosition = near ? 10 : 0
    }

    /// The text of each presence: its label always (except with labels off), and a second line with the detail while
    /// it needs you, for a few seconds after it changes, and on hover. See docs/scene.md.
    private func presenceLabels(_ scale: CGFloat) {
        var alive = Set<String>()
        func short(_ t: String, _ n: Int) -> String { t.count > n ? String(t.prefix(n - 1)) + "…" : t }
        for p in tank.scene.presences {
            alive.insert(p.id)
            let l = presenceLayers[p.id] ?? {
                let t = CATextLayer()
                t.contentsScale = scale
                t.alignmentMode = .center
                t.shadowOpacity = 0.75
                t.shadowRadius = 3
                t.shadowOffset = CGSize(width: 0, height: -0.5)
                t.shadowColor = NSColor(red: 0, green: 0.03, blue: 0.08, alpha: 1).cgColor
                labels.layer!.addSublayer(t)
                presenceLayers[p.id] = t
                return t
            }()
            let near = hoverPresence == p.id
            if labelMode == "none" && !near && !p.needsYou { l.opacity = 0; continue }
            if tank.compact && !p.needsYou { l.opacity = 0; continue }
            var name = short(p.label, 28)
            if p.kind.meter, p.detail == nil, let v = p.value { name += " · \(Int((v * 100).rounded()))%" }
            if near && p.link != nil { name += " ↗" }
            let s = NSMutableAttributedString(string: name, attributes: [
                .font: rounded(10.5, .medium), .foregroundColor: NSColor(white: 1, alpha: near ? 0.95 : 0.62)])
            let recent = tank.time - p.changedAt < 6
            var line2: (String, NSColor)?
            switch p.state {
            case .waiting: line2 = (p.detail.map { "✋ " + $0 } ?? p.state.label, NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1))
            case .alert: line2 = (p.detail.map { "⚠︎ " + $0 } ?? p.state.label, NSColor(red: 1, green: 0.75, blue: 0.3, alpha: 1))
            case .error: line2 = (p.detail.map { "✗ " + $0 } ?? p.state.label, NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1))
            default:
                let fade = near || labelMode == "full" ? 0.75 : CGFloat(max(0, min(1, 6 - (tank.time - p.changedAt)))) * 0.6
                if let d = p.detail, near || recent || labelMode == "full" { line2 = (d, NSColor(white: 1, alpha: fade)) }
                else if near, p.state != .ok { line2 = (p.state.label, NSColor(white: 1, alpha: 0.6)) }
            }
            if let (t, color) = line2 {
                s.append(NSAttributedString(string: "\n" + (near ? t : short(t, 44)), attributes: [.font: rounded(10), .foregroundColor: color]))
            }
            l.string = s
            let sz = s.size()
            l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
            let (at, above) = tank.scene.labelAnchor(p)
            l.position = CGPoint(x: CGFloat(at.x), y: CGFloat(at.y) + (above ? 1 : -1) * l.bounds.height / 2)
            l.opacity = p.alpha
            l.zPosition = near ? 10 : 1
        }
        for (id, l) in presenceLayers where !alive.contains(id) {
            l.removeFromSuperlayer()
            presenceLayers[id] = nil
        }
    }

    // MARK: - voice reading

    private var readQuestions: Bool { UserDefaults.standard.bool(forKey: "readQuestions") }
    @objc func toggleReadQuestions() { UserDefaults.standard.set(!readQuestions, forKey: "readQuestions") }

    /// If on (and neither muted nor in focus), reads the question aloud: "aquariozinho pergunta: …". It's called once
    /// the fish has finished calling (motif and knocks on the glass), so the voice doesn't cover them.
    private func readQuestion(_ f: Fish, after delay: Double) {
        guard readQuestions, !synth.muted.load(ordering: .relaxed), !Attention.focus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.4, delay)) { [weak self, weak f] in
            guard let f, f.state == .waiting, let q = f.asked else { return }
            Speaker.shared.speak(tr("%@ pergunta: %@", f.nickname ?? f.displayTitle ?? f.label, q))
            _ = self
        }
    }

    // MARK: - session actions

    /// What the fish's session provider can do now. Nothing that types into the session while a permission request is open.
    private func can(_ c: Capability, _ f: Fish) -> Bool {
        guard let p = Providers.of(f.source), p.capabilities(f).contains(c) else { return false }
        return c == .stop || permissions.request(ofFish: f.id) == nil
    }
    private func canReply(_ f: Fish) -> Bool { can(.reply, f) }
    private func canStop(_ f: Fish) -> Bool { can(.stop, f) }

    private func sendReply(_ f: Fish, _ text: String) {
        guard let provider = Providers.of(f.source) else { return }
        provider.reply(f, text) { [weak self, weak f] error in
            guard let self, let f else { return }
            if let error { self.tank.notice = (tr("não enviei: ") + error, self.tank.time); return }
            f.glow = 1
            self.tank.ring(at: f.pos, color: [0.7, 0.9, 1], size: f.size * 0.5, grow: 110, life: 0.7)
            f.moment = (tr("↩︎ respondido"), self.tank.time + 4)
        }
    }

    /// A simple text box (to reply, give a name, rename in Rex).
    private func ask(_ title: String, _ text: String = "", _ button: String = tr("Ok")) -> String? {
        let a = NSAlert()
        a.messageText = title
        a.addButton(withTitle: button)
        a.addButton(withTitle: tr("Cancelar"))
        let field = NSTextField(string: text)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        a.accessoryView = field
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }

    @objc private func menuReply() {
        guard let f = menuFish, let t = ask(tr("Responder %@", f.nickname ?? f.label), "", tr("Enviar")), !t.isEmpty else { return }
        sendReply(f, t)
    }
    @objc private func menuStop() { if let f = menuFish { Providers.of(f.source)?.stop(f) } }
    @objc private func menuNickname() {
        guard let f = menuFish, let t = ask(tr("Nome do peixe"), f.nickname ?? "", tr("Dar nome")) else { return }
        f.nickname = t
    }
    /// Each provider renames its own way (Claude: types /rename; Codex: writes to its index).
    @objc private func menuRenameChat() {
        guard let f = menuFish, let provider = Providers.of(f.source),
              let t = ask(tr("Renomear a conversa"), f.displayTitle ?? "", tr("Renomear")),
              !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        provider.renameChat(f, t.trimmingCharacters(in: .whitespaces)) { [weak self] error in
            guard let self, let error else { return }
            self.tank.notice = (tr("não renomeei: ") + error, self.tank.time)
        }
    }
    @objc private func menuRenamePane() {
        guard let f = menuFish, let t = ask(tr("Renomear o painel no Rex"), "", tr("Renomear")), !t.isEmpty else { return }
        Whereabouts.renamePane(f, t)
    }
    @objc private func menuRenameRex() {
        guard let f = menuFish, let t = ask(tr("Renomear a sessão no Rex"), f.sub?.components(separatedBy: " › ").first ?? "", tr("Renomear")),
              !t.isEmpty else { return }
        Whereabouts.renameRex(f, t)
    }

    // MARK: - hover card

    private func controlCard() {
        // the fish under the mouse (or with the card open) swims in circles in place
        tank.focused = hoverCardId ?? hoverId
        let now = Date()
        let mouseInCard: Bool = {
            guard let w = hoverCard?.contentViewController?.view.window else { return false }
            return w.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        }()
        // writing a reply: the card stays open until sending or clicking outside
        if (hoverCard?.contentViewController as? FishCard)?.typing == true { return }
        // card open: once a second, if something changed in the session, rebuild the content in the same bubble
        if let pop = hoverCard, let id = hoverCardId, now.timeIntervalSince(cardCheckedAt) > 1,
           let f = tank.fish.first(where: { $0.id == id }) {
            cardCheckedAt = now
            let a = signature(f)
            if a != cardSignature {
                cardSignature = a
                pop.contentViewController = cardContent(f)
            }
        }
        if let id = hoverId, now.timeIntervalSince(hoverSince) > 0.5, hoverCardId != id, popover?.isShown != true,
           let f = tank.fish.first(where: { $0.id == id }), window.isVisible {
            showCard(f)
        } else if hoverCard != nil, hoverId == nil, !mouseInCard {
            closeCard()
        } else if let id = hoverId, hoverCardId != nil, hoverCardId != id, !mouseInCard {
            closeCard()
        }
    }

    /// What, if it changes, makes the open card refresh.
    private func signature(_ f: Fish) -> String {
        [f.state.rawValue, f.tool ?? "", f.history.last?.name ?? "", "\(f.history.count)",
         f.context.map { "\(Int($0 * 100))" } ?? "", "\(f.lastReply?.hashValue ?? 0)", f.asked ?? "",
         f.displayTitle ?? "", f.nickname ?? "", f.sub ?? "", "\(permissions.request(ofFish: f.id)?.id ?? 0)",
         "\(f.finished.count)", f.compactingSince == nil ? "" : "c"].joined(separator: "|")
    }

    private func showCard(_ f: Fish) {
        closeCard()
        let pop = NSPopover()
        pop.behavior = .applicationDefined
        pop.animates = false
        pop.appearance = NSAppearance(named: .darkAqua)   // dark glass (see FishCard.glass)
        pop.contentViewController = cardContent(f)
        cardSignature = signature(f)
        cardCheckedAt = Date()
        let r = NSRect(x: CGFloat(f.pos.x) - f.size.cg, y: CGFloat(f.pos.y) - f.size.cg * 0.6, width: f.size.cg * 2, height: f.size.cg * 1.2)
        pop.show(relativeTo: r, of: view, preferredEdge: .maxY)
        hoverCard = pop
        hoverCardId = f.id
    }

    private func cardContent(_ f: Fish) -> FishCard {
        let request = permissions.request(ofFish: f.id)
        let resp: ((String) -> Void)? = canReply(f) ? { [weak self, weak f] text in
            guard let self, let f else { return }
            self.closeCard()
            self.sendReply(f, text)
        } : nil
        let stopFn: (() -> Void)? = canStop(f) ? { [weak self, weak f] in
            guard let self, let f else { return }
            self.closeCard()
            Providers.of(f.source)?.stop(f)
            self.tank.notice = (tr("Esc em %@", f.nickname ?? f.label), self.tank.time)
        } : nil
        let card = FishCard(fish: f, request: request, reply: resp, stop: stopFn) { [weak self] action in
            guard let self, let p = request else { return }
            self.closeCard()
            self.decide(p.id, action)
        }
        card.go = { [weak f] in if let f { Whereabouts.go(f) } }
        card.rebuild = { [weak self, weak f] in
            guard let self, let f, let pop = self.hoverCard, self.hoverCardId == f.id else { return }
            pop.contentViewController = self.cardContent(f)
            self.cardSignature = self.signature(f)
        }
        return card
    }

    private func closeCard() {
        hoverCard?.close()
        hoverCard = nil
        hoverCardId = nil
    }

    // MARK: - permission request

    private func showRequest(_ p: Permissions.Request, fish f: Fish) {
        popover?.close()
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = RequestView(request: p, label: f.label) { [weak self, weak pop] action in
            guard let self else { return }
            pop?.close()
            self.decide(p.id, action)
        }
        let r = NSRect(x: CGFloat(f.pos.x) - 20, y: CGFloat(f.pos.y) - 20, width: 40, height: 40)
        pop.show(relativeTo: r, of: view, preferredEdge: .maxY)
        popover = pop
    }

    /// "allow", "deny" or "go" (no decision: takes you to the session to answer there).
    private func decide(_ id: Int, _ action: String) {
        guard let p = permissions.request(id: id) else { return }
        let f = tank.fish(source: p.source, entity: p.session)
        switch action {
        case "allow", "deny":
            permissions.reply(id, action)
            if let f {
                f.glow = 1
                tank.ring(at: f.pos, color: action == "allow" ? [0.5, 1, 0.6] : [1, 0.5, 0.45], size: f.size * 0.5, grow: 120, life: 0.7)
                tank.upsert(source: p.source, entity: p.session, state: .busy, label: nil)
            }
        default:
            if let f { Whereabouts.go(f) }
        }
    }

    @objc private func menuAllow(_ i: NSMenuItem) { if let id = i.representedObject as? Int { decide(id, "allow") } }
    @objc private func menuDeny(_ i: NSMenuItem) { if let id = i.representedObject as? Int { decide(id, "deny") } }

    // MARK: - fish menu (right click)

    private var menuFish: Fish?
    private let previewMotif = MotifMenuDelegate()

    private func fishMenu(_ p: CGPoint, _ e: NSEvent) {
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

        if canReply(f) { m.addItem(item("Responder…", #selector(menuReply))) }
        if canStop(f) { m.addItem(item("Parar (Esc)", #selector(menuStop))) }
        m.addItem(item(f.nickname == nil ? "Dar um nome…" : "Mudar o nome…", #selector(menuNickname)))
        if can(.renameChat, f) {
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

    // MARK: - frame

    private func frame(_ dt: Float) -> (Uniforms, [Sprite]) {
        tank.size = [Float(view.bounds.width), Float(view.bounds.height)]
        tank.update(dt: dt)
        synth.setTurbidity(tank.turbidity)
        // water health: with errors (which need attention), the water darkens a little
        let errors = tank.fish.filter { !$0.decor && !$0.leaving && $0.state == .error && Attention.level($0.source, .error) >= .attention }.count
        tank.light = daylight() * (1 - 0.22 * min(1, Float(errors) / 3))
        let hasError = tank.fish.contains { !$0.decor && $0.state == .error && !$0.leaving && Attention.level($0.source, .error) >= .attention }
        let alert: Float = hasError ? 0.25 + 0.1 * sinf(Float(tank.time) * 3) : 0
        updateLabels()
        renderer.weeds = tank.weedUniforms()
        tank.shaderTime = renderer.shaderTime
        // look settings (Preferências → Aparência); FISHBOTS_BLOOM wins
        let d = UserDefaults.standard
        renderer.bloom = Env.value("BLOOM").flatMap(Float.init) ?? Float(d.object(forKey: "bloom") as? Double ?? 1.1)
        tank.showMotes = d.object(forKey: "marineSnow") as? Bool ?? true
        let hourColors = d.object(forKey: "hourColors") as? Bool ?? true
        // the quake also moves the background (the sprites move in Tank.sprites)
        let u = Uniforms(res: .zero, time: 0, turbidity: tank.turbidity, light: tank.light, alert: alert, pix: .zero,
                         gaze: tank.gaze + tank.scene.shakeOffset * 0.02, flash: tank.scene.flash, grade: hourColors ? Tank.grade(hour: hourNow()) : [1, 1, 1, 0],
                         scene: [tank.sceneGauge("waves") ?? 0, tank.sceneGauge("rain") ?? 0,
                                 tank.sceneGauge("temperature") ?? 0.5, tank.sceneGauge("fog") ?? 0],
                         sky: Tank.sky(hour: hourNow()))
        visual.size = tank.size
        visual.light = tank.light / (1 - 0.22 * min(1, Float(errors) / 3))   // daylight, without the darkening from errors
        visual.update(dt: min(dt, 0.05))
        return (u, visual.sprites() + tank.sprites())
    }

    /// The hour now, with minutes (FISHBOTS_HOUR fixes it, to see dawn or dusk any time).
    private func hourNow() -> Float {
        if let h = Env.value("HOUR").flatMap(Float.init) { return h }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Float(c.hour ?? 12) + Float(c.minute ?? 0) / 60
    }

    /// Real daylight: brightens in the morning, darkens at night (without going black).
    private func daylight() -> Float {
        let h = hourNow()
        let day = smoothstep(5.5, 8, h) * (1 - smoothstep(18, 20.5, h))
        return 0.62 + 0.38 * day
    }

    private func setupFooter() {
        let scale = window.backingScaleFactor
        calmText.alignmentMode = .center
        for l in [footer, banner, batteryText, pearlText, calmText] {
            l.contentsScale = scale
            l.fontSize = 11
            l.font = rounded(11, .medium)
            l.foregroundColor = NSColor(white: 1, alpha: 0.55).cgColor
            labels.layer!.addSublayer(l)
        }
        footer.alignmentMode = .left
        banner.alignmentMode = .center
        banner.fontSize = 15
        banner.font = rounded(15, .semibold)
        banner.foregroundColor = NSColor(white: 1, alpha: 0.9).cgColor
        banner.shadowOpacity = 0.8
        banner.shadowRadius = 3
        banner.shadowOffset = .zero
    }

    private func updateLabels() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = window.backingScaleFactor
        var alive = Set<String>()
        for f in tank.fish where !f.decor {
            alive.insert(f.id)
            let l = textLayers[f.id] ?? {
                let t = CATextLayer()
                t.contentsScale = scale
                t.alignmentMode = .center
                t.shadowOpacity = 0.75
                t.shadowRadius = 3
                t.shadowOffset = CGSize(width: 0, height: -0.5)
                t.shadowColor = NSColor(red: 0, green: 0.03, blue: 0.08, alpha: 1).cgColor
                labels.layer!.addSublayer(t)
                textLayers[f.id] = t
                return t
            }()
            if tank.isHidden(f) { l.opacity = 0; continue }        // widget mode: only who needs you
            if labelMode != "full" {
                minimalLabel(f, l)
                continue
            }
            var state = f.state.label
            if f.state == .busy, let tool = f.tool { state += " · \(tool)" }
            if let c = f.context, c >= 0.05 { state += tr(" · %d%% contexto", Int((c * 100).rounded())) }
            if f.compactingSince != nil { state = tr("🫧 compactando…") }
            if let p = permissions.request(ofFish: f.id) { state = tr("✋ quer usar %@ · clique para responder", p.tool) }
            else if f.state == .waiting, let q = f.asked { state = tr("✋ te perguntou: ") + q }
            let s = NSMutableAttributedString(string: f.nickname ?? f.label, attributes: [
                .font: rounded(11, .semibold), .foregroundColor: NSColor(white: 1, alpha: 0.92)])
            // plugin fish stay compact (name and state); details show on hover.
            // Claude sessions and anything needing attention show everything.
            let full = f.isAgent || hoverId == f.id
                || Attention.level(f.source, f.state) >= .attention
            // dots: one pearl per task finished today (up to 5) and a red dot if there was an error in the last hour
            let today = min(5, f.finished.filter { Calendar.current.isDateInToday($0.when) }.count)
            if today > 0 {
                s.append(NSAttributedString(string: " " + String(repeating: "●", count: today), attributes: [
                    .font: rounded(7), .foregroundColor: NSColor(red: 0.95, green: 0.92, blue: 0.85, alpha: 0.85), .baselineOffset: 1.5]))
            }
            if let e = f.lastError, Date().timeIntervalSince(e) < 3600, f.state != .error {
                s.append(NSAttributedString(string: " ●", attributes: [
                    .font: rounded(7), .foregroundColor: NSColor(red: 1, green: 0.4, blue: 0.35, alpha: 0.9), .baselineOffset: 1.5]))
            }
            var detail = full ? (f.sub ?? "") : ""
            if let b = f.branch, b != "main", b != "master", b != "HEAD" { detail = "⎇ \(b)" + (detail.isEmpty ? "" : "  ·  " + detail) }
            if !detail.isEmpty {
                s.append(NSAttributedString(string: "  " + detail, attributes: [
                    .font: rounded(10), .foregroundColor: NSColor(white: 1, alpha: 0.5)]))
            }
            if full, let t = f.displayTitle {
                s.append(NSAttributedString(string: "\n" + t, attributes: [
                    .font: rounded(10, .medium), .foregroundColor: NSColor(white: 1, alpha: 0.78)]))
            }
            let color: NSColor = f.state == .waiting ? NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1)
                : f.state == .error ? NSColor(red: 1, green: 0.45, blue: 0.4, alpha: 1)
                : NSColor(white: 1, alpha: 0.55)
            s.append(NSAttributedString(string: "\n" + state, attributes: [.font: rounded(10), .foregroundColor: color]))
            l.string = s
            let sz = s.size()
            l.bounds = CGRect(x: 0, y: 0, width: ceil(sz.width) + 6, height: ceil(sz.height) + 2)
            l.position = CGPoint(x: CGFloat(f.pos.x), y: CGFloat(f.pos.y - f.size * 0.75) - l.bounds.height / 2)
            l.opacity = f.leaving ? 0.3 : 1
            l.zPosition = hoverId == f.id ? 10 : 0
        }
        for (id, l) in textLayers where !alive.contains(id) {
            l.removeFromSuperlayer()
            textLayers[id] = nil
        }
        presenceLabels(scale)

        var parts = [tr("clique no peixe: ir até ele"), tr("no vazio: alimentar"), "D demo\(demo.on ? " ✓" : "")", tr("M som") + (synth.muted.load(ordering: .relaxed) ? " ✗" : ""),
                      tr("T flutuar") + (window.level == .floating ? " ✓" : ""), tr("S foco") + (Attention.focus ? " ✓" : ""), tr("L rótulos"), "127.0.0.1:\(port)"]
        for (k, v) in tank.gauges.sorted(by: { $0.key < $1.key }) where k != "mac:battery" && k != "mac:charging" {
            parts.append("\(k.split(separator: ":").last ?? "") \(Int(v * 100))%")
        }
        if let n = music.pieceName { parts.insert("🎵 " + n, at: 0) }
        var vis: [String] = []
        if visual.auroraBackground || visual.auroraChosen { vis.append("✨ aurora (\(visual.auroraDescription))") }
        if let m = visual.mode, !m.isAurora { vis.append(m.title) }
        if !vis.isEmpty { parts.insert(vis.joined(separator: " + "), at: min(1, parts.count)) }
        footer.string = parts.joined(separator: "   ·   ")
        footer.frame = CGRect(x: 14, y: 6, width: labels.bounds.width - 28, height: 16)
        // the footer shows while you use the window (mouse moving over it) and fades out a few seconds later
        let wanted: Float = tank.cursor != nil && tank.time - tank.cursorAt < 4 ? 1 : 0
        footerOpacity += (wanted - footerOpacity) * (wanted > footerOpacity ? 0.25 : 0.04)
        footer.opacity = tank.compact ? 0 : footerOpacity
        // widget mode with nobody needing you: a quiet line in the middle
        let anyone = tank.fish.contains { !$0.decor && !$0.leaving && [.waiting, .error, .alert].contains($0.state) }
            || tank.scene.presences.contains { !$0.leaving && $0.needsYou }
        calmText.string = tr("✓ ninguém esperando")
        calmText.frame = CGRect(x: 0, y: labels.bounds.height / 2 - 9, width: labels.bounds.width, height: 18)
        calmText.opacity = tank.compact && !anyone ? 0.55 : 0

        if let b = tank.battery {
            batteryText.string = "\(Int((b * 100).rounded()))%" + (tank.pluggedIn ? " ⚡︎" : "")
            batteryText.fontSize = 10
            batteryText.alignmentMode = .center
            batteryText.foregroundColor = (b < 0.2 ? NSColor(red: 1, green: 0.5, blue: 0.45, alpha: 0.9) : NSColor(white: 1, alpha: 0.6)).cgColor
            let p = tank.batteryPos
            batteryText.frame = CGRect(x: CGFloat(p.x) - 30, y: CGFloat(p.y) + 12, width: 60, height: 14)
            // just a detail: the number shows on hover, or always if it's running out
            batteryText.opacity = hoverBattery || b < 0.2 ? 1 : 0
        } else {
            batteryText.opacity = 0
        }

        controlCard()

        if let p = hoverPearl {
            let hour = DateFormatter.localizedString(from: Date(timeIntervalSince1970: p.hour), dateStyle: .none, timeStyle: .short)
            pearlText.string = "\(p.project) · \(hour)\n\(p.title)"
            pearlText.fontSize = 10
            pearlText.alignmentMode = .center
            pearlText.foregroundColor = NSColor(white: 1, alpha: 0.85).cgColor
            let q = tank.pearlPos(p)
            pearlText.frame = CGRect(x: CGFloat(q.x) - 140, y: CGFloat(q.y) + 10, width: 280, height: 28)
            pearlText.opacity = 1
        } else {
            pearlText.opacity = 0
        }

        if let (txt, t) = tank.notice, tank.time - t < 4 {
            banner.string = (tank.noticeIcon.map { $0 + " " } ?? "") + txt
            banner.opacity = Float(min(1, 4 - (tank.time - t)))
        } else {
            banner.opacity = 0
        }
        banner.frame = CGRect(x: 0, y: labels.bounds.height - 56, width: labels.bounds.width, height: 22)
        CATransaction.commit()
    }

    // MARK: - keys and menu

    private func key(_ k: String) {
        switch k {
        case "d": toggleDemo()
        case "m": toggleMute()
        case "t": toggleFloat()
        case "w": toggleWidget()
        case "s": toggleFocus()
        case "r": recentSummary()
        case "l": cycleLabels()
        case "a": toggleAmbientMusic()
        case "f": tank.feed(at: [Float.random(in: tank.size.x * 0.2...tank.size.x * 0.8), tank.size.y - 30])
        default: break
        }
    }

    /// The volume chosen in the preferences (0…1), on top of the usual level (lower while the Mac's voice speaks).
    private var volume: Float {
        get { UserDefaults.standard.object(forKey: "volume") as? Float ?? 1 }
        set { UserDefaults.standard.set(newValue, forKey: "volume"); applyVolume() }
    }
    private func applyVolume(ducked: Bool = false) {
        synth.engine.mainMixerNode.outputVolume = (ducked ? 0.3 : 0.9) * volume
    }

    private lazy var preferences = PreferencesWindow(Prefs.Actions(
        openAtLogin: { SMAppService.mainApp.status == .enabled },
        toggleLogin: { [unowned self] in self.toggleLogin() },
        menuBarOnly: { UserDefaults.standard.bool(forKey: "menuBarOnly") },
        toggleMenuBarOnly: { [unowned self] in self.toggleMenuBarOnly() },
        floating: { [unowned self] in self.window.level == .floating },
        toggleFloat: { [unowned self] in self.toggleFloat() },
        soundOn: { [unowned self] in !self.synth.muted.load(ordering: .relaxed) },
        toggleMute: { [unowned self] in self.toggleMute() },
        volume: { [unowned self] in Double(self.volume) },
        setVolume: { [unowned self] in self.volume = Float($0) },
        applyTheme: { [unowned self] in self.applyTheme() },
        applyLanguage: { L10n.setting = $0 },
        plugins: { [unowned self] in
            let files = ((try? FileManager.default.contentsOfDirectory(atPath: Plugins.folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
            let fmt = RelativeDateTimeFormatter(); fmt.locale = L10n.locale
            return files.map { name in
                guard let s = self.plugins?.states[name] else { return (name, true, tr("ainda não rodou")) }
                let when = s.lastRun.map { tr("rodou %@", fmt.localizedString(for: $0, relativeTo: Date())) } ?? ""
                return (name, s.ok, s.ok ? when : (s.error ?? "falhou"))
            }
        }))

    @objc func showPreferences() { preferences.show() }

    @objc func toggleDemo() { demo.toggle() }
    @objc func toggleMute() { synth.muted.store(!synth.muted.load(ordering: .relaxed), ordering: .relaxed) }
    // MARK: - widget mode

    private var widgetFrom: NSRect?
    private var levelBeforeWidget: NSWindow.Level = .normal

    /// Widget mode: a small, frameless, rounded window in a corner, always on top and on every Space, showing only
    /// who needs you (the rest keeps swimming, hidden). W, the menu or the right-click menu switch it.
    @objc func toggleWidget() {
        guard let content = window.contentView else { return }
        content.wantsLayer = true
        if let from = widgetFrom {
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "widgetFrame")
            tank.compact = false
            widgetFrom = nil
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.level = levelBeforeWidget
            window.collectionBehavior = window.level == .floating ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
            window.isOpaque = true
            window.backgroundColor = .black
            content.layer?.cornerRadius = 0
            window.setFrame(from, display: true, animate: true)
        } else {
            widgetFrom = window.frame
            levelBeforeWidget = window.level
            tank.compact = true
            window.styleMask = [.borderless, .resizable]
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            content.layer?.cornerRadius = 16
            content.layer?.masksToBounds = true
            let vf = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            var frame = NSRect(x: vf.maxX - 436, y: vf.minY + 16, width: 420, height: 260)
            if let s = UserDefaults.standard.string(forKey: "widgetFrame") {
                let r = NSRectFromString(s)
                if r.width > 200 && vf.intersects(r) { frame = r }
            }
            window.setFrame(frame, display: true, animate: true)
            show()
        }
        window.invalidateShadow()
    }

    @objc func toggleFloat() {
        window.level = window.level == .floating ? .normal : .floating
        window.collectionBehavior = window.level == .floating ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }
    @objc func feed() { key("f") }
    @objc func toggleFocus() { Attention.focus.toggle() }
    @objc func toggleAmbientMusic() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "ambientMusic"), forKey: "ambientMusic")
    }
    @objc func toggleToolNotes() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "toolNotes"), forKey: "toolNotes")
    }
    @objc func toggleNotifyWaiting() {
        let urgent = Attention.level("*", .waiting) == .urgent
        Attention.setLevel("*:waiting", urgent ? .attention : .urgent)
    }
    @objc func toggleNotifyError() {
        let urgent = Attention.level("*", .error) == .urgent
        Attention.setLevel("*:error", urgent ? .attention : .urgent)
    }
    @objc func openConfig() { Attention.openConfig() }

    /// Visualizer submenu: automatic, random, off and each one.
    private func menuVisualizer() -> NSMenuItem {
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

    private func menuTheme() -> NSMenuItem {
        let item = NSMenuItem(title: tr("Tema"), action: nil, keyEquivalent: "")
        let m = NSMenu()
        for t in Themes.all {
            let it = NSMenuItem(title: t.displayName, action: #selector(chooseTheme(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = t.id
            m.addItem(it)
        }
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
        let open = NSMenuItem(title: tr("Abrir pasta de pacotes…"), action: #selector(openPacks), keyEquivalent: "")
        open.target = self
        m.addItem(open)
        item.submenu = m
        return item
    }
    @objc func openPacks() { NSWorkspace.shared.open(Packs.folder) }
    @objc func chooseTheme(_ i: NSMenuItem) {
        guard let id = i.representedObject as? String else { return }
        Themes.current = Themes.named(id)
        applyTheme()
        tank.notice = (tr("tema: ") + Themes.current.displayName, tank.time)
    }
    /// The scene's colors go to the shader; the seaweed count to the tank (the fish nibble it); the default visualizer.
    private func applyTheme() {
        let t = Themes.current
        renderer.theme = t.uniforms
        tank.weedCount = t.weedCount
        tank.rayStrength = t.uniforms.params.z
        visual.themeVisualizer = t.visualizer
        tank.fauna.select(t.fauna)
        tank.sceneryKinds = t.scenery
        Generator.preferredStyle = t.music
    }
    @objc func chooseVisual(_ i: NSMenuItem) {
        if let id = i.representedObject as? String { visual.choice = id }
    }

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
        default: break
        }
        return true
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        let prefsItem = NSMenuItem(title: tr("Preferências…"), action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Esconder Fishbots"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("Sair do Fishbots"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let aqItem = NSMenuItem()
        main.addItem(aqItem)
        let aq = NSMenu(title: tr("Aquário"))
        func add(_ t: String, _ s: Selector, _ k: String) {
            let i = NSMenuItem(title: tr(t), action: s, keyEquivalent: k)
            i.target = self
            aq.addItem(i)
        }
        add("Alimentar", #selector(feed), "f")
        add("Modo demo", #selector(toggleDemo), "d")
        add("Som ligado/desligado", #selector(toggleMute), "m")
        add("Flutuar sobre as janelas", #selector(toggleFloat), "t")
        add("Modo widget (janelinha no canto)", #selector(toggleWidget), "w")
        aq.addItem(.separator())
        add("Música ambiente (tocar o tempo todo)", #selector(toggleAmbientMusic), "a")
        add("Modo foco (só o que pede atenção)", #selector(toggleFocus), "s")
        add("Nota a cada ferramenta usada", #selector(toggleToolNotes), "")
        add("Ler as perguntas em voz alta", #selector(toggleReadQuestions), "")
        add("Notificar quando esperarem por você", #selector(toggleNotifyWaiting), "")
        add("Notificar erros", #selector(toggleNotifyError), "")
        add("Abrir configuração de atenção…", #selector(openConfig), "")
        add("Resumo das últimas 2 horas", #selector(recentSummary), "r")
        add("Rótulos: mínimo / completo / nenhum", #selector(cycleLabels), "l")
        aq.addItem(.separator())
        aq.addItem(menuVisualizer())
        aq.addItem(menuTheme())
        aqItem.submenu = aq

        let plItem = NSMenuItem()
        main.addItem(plItem)
        menuPlugins.delegate = self
        for i in NSApp.mainMenu?.items ?? [] where i.submenu === menuPlugins { i.submenu = nil }   // rebuilding (new language)
        plItem.submenu = menuPlugins

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let win = NSMenu(title: tr("Janela"))
        win.addItem(withTitle: tr("Fechar (continua na barra de menus)"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: tr("Minimizar"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "")
        win.addItem(withTitle: tr("Tela cheia"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "")
        winItem.submenu = win
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }
}

/// Plays the motif of the option under the mouse in the "Trocar motivo" submenu.
final class MotifMenuDelegate: NSObject, NSMenuDelegate {
    var play: ((Int) -> Void)?
    private var last = -1
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let item, item.tag > 0, item.tag - 1 != last else { return }
        last = item.tag - 1
        play?(last)
    }
    func menuDidClose(_ menu: NSMenu) { last = -1 }
}

private extension Float { var cg: CGFloat { CGFloat(self) } }

/// SF Pro Rounded: the labels and the footer (friendlier, and it reads well small).
func rounded(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    return f.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? f
}
