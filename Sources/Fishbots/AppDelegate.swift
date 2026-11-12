import AppKit
import MetalKit
import QuartzCore
import simd
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private(set) var window: NSWindow!
    private(set) var view: TankView!
    private(set) var labels: LabelsView!
    private(set) var renderer: Renderer!
    let tank = Tank()
    let synth = Synth()
    private(set) var music: Music!
    var server: Server?
    private var mac: MacSource?
    private(set) var demo: Demo!
    private var musicTimer: Timer?
    let labelLayers = Labels()
    private(set) var windowModes: WindowModes!
    /// "Silenciar por 1 hora": brings the sound back when it's up.
    var unmuteTimer: Timer?
    let focusFollow = FocusFollow()
    lazy var widgetPlaceMenu = WidgetPlaceMenu { [weak self] in self?.windowModes }
    /// What terminals say by themselves, through Rex and Herdr: what a session is doing, titles and places, and
    /// programs without hooks as fish (TerminalPrograms, RexFish, HerdrFish).
    lazy var terminalPrograms = TerminalPrograms(tank: tank)
    lazy var rexFish = RexFish(tank: tank, programs: terminalPrograms)
    lazy var herdrFish = HerdrFish(tank: tank, programs: terminalPrograms)
    private var hotkeys: [HotkeyAction: Hotkey] = [:]
    private var activity: NSObjectProtocol?
    private(set) var port: UInt16 = 7777
    let notifier = Notifier()
    let visual = Visual()
    /// The album art's tint (0…1) and its two colors, eased.
    private var artTint: Float = 0
    private var artA: SIMD3<Float> = [1, 1, 1]
    private var artB: SIMD3<Float> = [1, 1, 1]
    let permissions = Permissions()
    let journal = Journal()
    private var outsideButton: NSButton?
    private(set) var card: SummaryView?
    /// The fish's card, the request bubble and the keyboard's pick (Cards.swift).
    lazy var cards = Cards(tank: tank, permissions: permissions)
    /// The "Nova sessão…" card while it's open (NewSession.swift).
    var newSessionCard: NSPopover?
    /// Sessions commanding other sessions (/control, SessionControl.swift).
    lazy var sessionControl = SessionControl(tank: tank, port: { [unowned self] in self.port }) { [unowned self] c, f in self.cards.can(c, f) }
    private(set) var hoverBattery = false
    private(set) var hoverPearl: Pearl?
    /// The presence (docs/scene.md) under the mouse.
    private(set) var hoverPresence: String?
    private(set) var plugins: Plugins?
    private var nowPlaying: NowPlaying?
    let menuPlugins = NSMenu(title: "Plugins")
    var statusItem: NSStatusItem!
    let statusMenu = NSMenu()
    /// The fish a right-click menu is about, and the delegate that plays a motif as the mouse goes over it.
    var menuFish: Fish?
    let previewMotif = MotifMenuDelegate()

    /// The theme on the tank, the packs and their pictures (ThemeKeeper); the menus and windows are in ThemesAndPacks.swift.
    lazy var themeKeeper = ThemeKeeper(tank: tank, visual: visual)
    /// The pack catalog ("Explorar pacotes…").
    lazy var catalogWindow: PackCatalogWindow = {
        let w = PackCatalogWindow()
        w.onInstalled = { [unowned self] _ in self.themeKeeper.reloadPacks(); self.themeKeeper.checkCatalog() }
        return w
    }()
    /// Pauses a pack whose drawings make the aquarium heavy (see PackGuard).
    let packGuard = PackGuard()
    /// The themes window (E): pictures, where each comes from, what it brings; the surprise mode; the catalog.
    lazy var themePicker: ThemePickerWindow = {
        let w = ThemePickerWindow()
        w.onChoose = { [unowned self] id in self.themeKeeper.use(id) }
        w.onExplore = { [unowned self] in self.explorePacks() }
        return w
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Providers.registerBuiltIns()
        // a new interface language: menus and notification buttons are rebuilt (labels, cards and the footer follow by themselves)
        L10n.onChange = { [unowned self] in
            self.buildMenu()
            self.notifier.languageChanged()
            self.cards.close()
        }
        tank.profile = Providers.profile
        Packs.load()   // before the renderer compiles the shader (fish kinds) and the theme is applied
        AgentManifests.load()
        Renderer.packFishFailed = Packs.fishFailed
        Renderer.packSceneryFailed = Packs.sceneryFailed
        Renderer.packFaunaFailed = Packs.faunaFailed
        Renderer.packPresenceFailed = Packs.presenceFailed
        Renderer.packBackgroundFailed = Packs.backgroundFailed
        TankProtocol.stateExtras = { ["packs": Packs.loaded.map { ["id": $0.id, "name": $0.name, "contents": $0.contents] },
                                      "packProblems": Packs.problems, "agentProblems": AgentManifests.problems, "fishKinds": FishKinds.all.map(\.id),
                                      "packsSignature": String(self.themeKeeper.signature.hashValue),
                                      "notifications": self.notifier.permission, "onScreen": self.onScreen] }
        notifier.prepare()
        if let p = Env.value("PORT"), let n = UInt16(p) { port = n }
        buildMenu()
        themeKeeper.watchPacks()
        // the surprise theme, if it's on
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.themeKeeper.surprise() }
        // the catalog: a while after launch, then once a day (FISHBOTS_CATALOG=off skips it)
        if Env.value("CATALOG") != "off" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.themeKeeper.checkCatalog() }
            Timer.scheduledTimer(withTimeInterval: 86_400, repeats: true) { [weak self] _ in self?.themeKeeper.checkCatalog() }
        }

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
        labelLayers.attach(to: labels, scale: window.backingScaleFactor)
        windowModes = WindowModes(window: window, view: view, labels: labels, tank: tank)
        windowModes.cardOpen = { [unowned self] in self.cards.isOpen || self.newSessionCard?.isShown == true || self.card != nil }
        windowModes.onDrawingChanged = { [unowned self] in self.visibilityChanged() }
        windowModes.onGo = { [unowned self] id in
            if let f = self.tank.fish.first(where: { $0.id == id }) { Whereabouts.go(f); return }
            // a plugin's presence: its link, else the notch opens on it
            let p = self.tank.scene.presences.first { "presence:" + $0.id == id }
            if let l = p?.link, let u = URL(string: l) { NSWorkspace.shared.open(u) } else { self.windowModes.setNotchOpen(true, hold: 4) }
        }
        windowModes.answers = { [unowned self] f in self.notchAnswers(f) }
        windowModes.onAnswer = { [unowned self] id, action in self.cards.decide(id, action) }
        windowModes.cover = { [unowned self] in
            NowPlaying.playing ? self.tank.fish(source: NowPlaying.source, entity: NowPlaying.entity)?.art : nil
        }
        windowModes.onMenu = { [unowned self] e, v in self.notchMenu(e, v) }
        windowModes.song = { [unowned self] in
            guard NowPlaying.playing, let f = self.tank.fish(source: NowPlaying.source, entity: NowPlaying.entity) else { return nil }
            return (f.id, f.label)
        }
        windowModes.peek = { [unowned self] id in self.notchPeek(id) }
        windowModes.onNewSession = { [unowned self] in self.newSession() }
        windowModes.onDrop = { [unowned self] text, v, at in self.notchDrop(text, v, at) }
        windowModes.away = { [unowned self] in self.notchAway() }
        windowModes.onAway = { [unowned self] in self.windowModes.openLarge(); self.openAwaySummary() }
        windowModes.onClosed = { [unowned self] in self.card?.close?() }

        renderer.frame = { [unowned self] dt in self.frame(dt) }
        renderer.onGPUFrame = { [unowned self] ms, failed in self.packGuard.gpu(ms: ms, failed: failed) }
        packGuard.onCulprit = { [unowned self] id, reason in
            let name = Packs.loaded.first { $0.id == id }?.name ?? id
            Packs.pause(id, reason: reason)
            self.themeKeeper.reloadPacks()
            self.tank.notice = (tr("pacote pausado: %@ (%@)", name, Packs.reasonText(reason)), self.tank.time)
        }
        themeKeeper.renderer = renderer
        themeKeeper.onChange = { [unowned self] in self.buildMenu() }
        themeKeeper.onTheme = { [unowned self] in self.preferences.refresh() }   // its Theme row shows the current one
        themeKeeper.apply()
        cards.view = view
        cards.read = { [unowned self] f in self.read(f) }
        view.onKey = { [unowned self] k in self.key(k) }
        // while a card is open, its keys work even with its reply field focused: all of them when it was opened from
        // the keyboard (Tab), only Esc when the mouse opened it
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] e in
            guard self.cards.isOpen else { return e }
            if self.cards.keyboardPick == nil {
                // a card opened by the mouse: Esc closes it too, even while writing in its reply field (and it only
                // comes back when the mouse goes over the fish again)
                guard e.keyCode == 53 else { return e }
                self.cards.forgetHover()
                return self.cards.key("⎋") ? nil : e
            }
            let cmd = e.modifierFlags.contains(.command)
            let k: String?
            switch Int(e.keyCode) {
            case 48: k = e.modifierFlags.contains(.shift) ? "⇤" : "⇥"
            case 53: k = "⎋"
            case 36, 76: k = cmd ? "⌘↩" : nil                 // plain Enter: sends the reply (the field's own)
            default: k = cmd ? (e.charactersIgnoringModifiers?.lowercased()).map { "⌘" + $0 } : nil
            }
            guard let key = k, ["⇥", "⇤", "⎋", "⌘↩", "⌘r", "⌘d"].contains(key) else { return e }
            return self.cards.key(key) ? nil : e
        }
        view.onClick = { [unowned self] p in self.click(p) }
        view.dragMovesWindow = { [unowned self] in self.windowModes.draggable }
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
            self.cards.hover(f?.id)
            self.hoverBattery = self.tank.battery != nil && simd_distance(q, self.tank.batteryPos) < 26
            let presence = f == nil ? self.tank.scene.presence(at: q) : nil
            self.hoverPresence = presence?.id
            self.hoverPearl = f == nil && presence == nil ? self.tank.pearls.at(q) : nil
            return f != nil || presence != nil || self.tank.scenery.chestHit(self.tank, at: q) || self.tank.scenery.eggsHit(self.tank, at: q)
        }
        rexFish.start()
        herdrFish.check()
        focusFollow.changed = { [unowned self] in self.buildMenu() }
        focusFollow.start()
        // session, tab and title names change: refresh every so often
        Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [unowned self] _ in
            // Rex and Herdr tell by themselves; a stream that ended (or a Herdr that has just started) is opened here
            self.rexFish.events.check()
            self.herdrFish.check()
            // the others are asked: pane and tab names only matter on screen. A fish in a Rex pane or a Herdr
            // terminal is only asked while its place isn't known yet, or while nobody is listening there
            if self.onScreen {
                for f in self.tank.fish where !f.decor && !f.whereabouts.isEmpty {
                    let told = f.sub != nil && (f.whereabouts["rex_block"] != nil && self.rexFish.events.isFollowing(f.whereabouts["rex_session"] ?? "")
                                                || f.whereabouts["herdr"] != nil && self.herdrFish.listening)
                    if !told { Whereabouts.detail(f) }
                }
            }
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
        // your music paused while the aquarium's was yielding: the music fish offers it, like an agent asking (but
        // quietly: no notification, nothing read aloud), and the offer goes away when your music plays again
        music.onUserMusicPaused = { [unowned self] in
            if let f = self.tank.fish(source: NowPlaying.source, entity: NowPlaying.entity) {
                f.offer = tr("♪ toco a música do aquário? (clique)")
            } else {
                self.tank.notice = (tr("sua música pausou: ⌘A toca a do aquário"), self.tank.time)
            }
        }
        music.onUserMusicPlays = { [unowned self] in
            self.tank.fish(source: NowPlaying.source, entity: NowPlaying.entity)?.offer = nil
        }
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
        notifier.decide = { [unowned self] request, action in self.cards.decide(request, action) }
        notifier.go = { [unowned self] id in
            guard let f = self.tank.fish.first(where: { $0.id == id }) else { return }
            // its terminal; when it has none, in the notch: it opens on that session's card
            if !Whereabouts.go(f) && self.windowModes.mode == .notch {
                self.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.cards.pick(f) }
            }
        }

        demo = Demo(tank: tank)
        mac = MacSource(tank: tank)
        startServer()
        rememberSessions()
        plugins = Plugins(tank: tank)
        nowPlaying = NowPlaying(tank: tank)
        nowPlaying?.ears.visual = visual
        setupStatusItem()
        // ⌃⌥F from any app: the session that has been waiting the longest (or the aquarium, if nobody is)
        registerHotkey()
        if UserDefaults.standard.bool(forKey: "menuBarOnly") { NSApp.setActivationPolicy(.accessory) }

        // quit in the widget: it comes back in it (without taking the keyboard)
        if WindowModes.startsInWidget {
            windowModes.toggle()
        } else {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            NSApp.activate(ignoringOtherApps: true)
        }

        if Env.value("DEMO") == "1" { demo.turnOn() }
    }

    // closing the window doesn't quit: the aquarium keeps playing and monitoring from the menu bar
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show()
        return true
    }

    /// (Re)registers the global shortcuts from the settings; `paused` lets the preferences record a new one.
    private func registerHotkey(paused: Bool = false) {
        hotkeys = [:]
        guard !paused else { return }
        for a in HotkeyAction.allCases {
            let run: () -> Void
            switch a {
            case .go: run = { [unowned self] in self.goToLongestWaiting() }
            case .read: run = { [unowned self] in self.readLongestWaiting() }
            case .mic: run = { [unowned self] in self.replyByVoice() }
            }
            if let h = Hotkey(a.shortcut, id: a.id, action: run) { hotkeys[a] = h }
            else { FileHandle.standardError.write("fishbots: couldn't register \(a.shortcut.display) (another app has it?)\n".data(using: .utf8)!) }
        }
    }

    private var longestWaiting: Fish? {
        tank.fish.filter { !$0.decor && !$0.leaving && $0.state == .waiting }.min { $0.since < $1.since }
    }

    /// Reads aloud the question (or the last reply) of whoever has waited longest.
    @objc func readLongestWaiting() {
        guard let f = longestWaiting else { Speaker.shared.speak(tr("ninguém esperando")); return }
        read(f)
    }

    /// Reads a fish's question (or its last reply) aloud; again stops it.
    func read(_ f: Fish) {
        if Speaker.shared.speaking { Speaker.shared.stop(); return }
        let name = f.nickname ?? f.displayTitle ?? f.label
        if let q = f.asked { Speaker.shared.speak(tr("%@ pergunta: %@", name, q)) }
        else if let r = f.lastReply { Speaker.shared.speak(name + ". " + r) }
        else { Speaker.shared.speak(tr("%@ está esperando você", name)) }
    }

    /// Opens the card of whoever has waited longest with the microphone on: speak, then Enter sends.
    @objc func replyByVoice() {
        // already listening: the same shortcut turns the microphone off
        if Dictation.shared.listening, let card = cards.card { card.toggleDictation(); return }
        guard let f = longestWaiting else { show(); tank.notice = (tr("✓ ninguém esperando"), tank.time); return }
        show()
        guard cards.canReply(f) else { tank.notice = (f.label + ": " + tr("não sei responder essa sessão"), tank.time); return }
        cards.open(f)
        cards.card?.startDictation()
    }

    /// The session waiting for you the longest: its terminal comes forward (the global shortcut, ⌃⌥F by default).
    @objc func goToLongestWaiting() {
        let waiting = tank.fish.filter { !$0.decor && !$0.leaving && $0.state == .waiting }.sorted { $0.since < $1.since }
        if let f = waiting.first, Whereabouts.go(f) {
            f.glow = 1
            tank.ring(at: f.pos, color: [1, 0.9, 0.5], size: f.size * 0.5, grow: 140, life: 0.7)
        } else {
            show()
            tank.notice = (waiting.isEmpty ? tr("✓ ninguém esperando") : tr("%@: não sei onde fica", waiting[0].label), tank.time)
        }
    }

    @objc func show() {
        if windowModes.mode == .notch {
            windowModes.setNotchOpen(true, hold: 4)
            windowModes.takeKeyboard()
            return
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) { Attention.reload(); notifier.readPermission() }
    func applicationWillTerminate(_ notification: Notification) {
        // quitting in widget mode: back to the normal window first, so it isn't remembered as the window's size
        windowModes.quit()
        SessionMemory.save(tank)
        rexFish.events.stop()
        herdrFish.stop()
        plugins?.stop()
        permissions.releaseAll()
    }

    // MARK: - attention

    private let openedAt = Date()

    /// The window is on screen (not closed, minimized or fully covered, nor shut in the notch).
    private var onScreen = true
    private var backgroundTick: Timer?

    /// Off screen, drawing stops (60 frames a second for nobody is most of the app's weight). The tank keeps ticking
    /// once a second, so its timers still run (a lingering error, sleeping, the whale…); sound and notices don't
    /// depend on drawing. Back on screen, it draws again.
    private func visibilityChanged() {
        let visible = window.occlusionState.contains(.visible) && !windowModes.holdsDrawing
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
                f.context = s.context; f.model = s.model; f.lastReply = s.lastReply; f.link = s.link; f.transcriptPath = s.transcriptPath
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
        // about to call you: are you already looking at its session? (the call waits for the answer)
        if [.waiting, .error, .alert].contains(f.state) { InView.check(f) }
        if restoring { updateDock(); return }
        // whatever was already like this when the app opened isn't news
        if !f.decor && Date().timeIntervalSince(openedAt) > 20 {
            switch f.state {
            case .done:
                journal.record(.done, f.label, fish: f.id)
                // productive day (10 tasks): the whale swims by, once a day
                tank.fauna.maybeWhale(tank, tasksToday: tank.pearls.all.count)
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

    func updateDock() {
        let n = max(tank.fish.filter { !$0.decor && !$0.leaving && $0.state == .waiting }.count, permissions.pending.count)
        NSApp.dockTile.badgeLabel = n > 0 ? "\(n)" : nil
        statusItem?.button?.title = n > 0 ? " \(n)" : ""
    }

    // MARK: - server

    private func click(_ p: CGPoint) {
        cards.close()
        let q: SIMD2<Float> = [Float(p.x), Float(p.y)]
        if let f = tank.fish(at: q), let p = permissions.request(ofFish: f.id) {
            cards.showRequest(p, fish: f)
            return
        }
        if let f = tank.fish(at: q), f.offer != nil {
            // the music fish's offer: a click says yes
            f.offer = nil
            music.yielded = false
            tank.ring(at: f.pos, color: f.color, size: f.size * 0.6, grow: 160, life: 0.8)
            tank.notice = (tr("música do aquário"), tank.time)
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
            // a light on the side glass: the card of everything its source keeps there
            if p.kind.motion == .glass { cards.showSource(of: p) }
            else if let l = p.link, let u = URL(string: l) { NSWorkspace.shared.open(u) }
            else { tank.notice = (p.detail.map { "\(p.label): \($0)" } ?? p.label, tank.time) }
        } else if let pearl = tank.pearls.at(q) {
            // a pearl of the day: what was done around that time
            let at = Date(timeIntervalSince1970: pearl.hour)
            let hour = DateFormatter.localizedString(from: at, dateStyle: .none, timeStyle: .short)
            summary(since: at.addingTimeInterval(-1800), until: at.addingTimeInterval(1800), title: tr("Por volta das %@", hour))
        } else if tank.scenery.chestHit(tank, at: q) {
            // the treasure chest keeps the last hours; clicking it again closes them
            if let c = card { c.close?() } else { recentSummary() }
        } else if tank.scenery.eggsHit(tank, at: q) {
            // the clutch of eggs: a new session, which will hatch from it
            newSession()
        } else if !tank.scare(q) {
            tank.feed(at: q)        // away from everyone: food; near fish: they get startled
        }
    }

    // MARK: - while you were away

    private func showOutsideButton() {
        guard let p = journal.pending else { return }
        // in the notch, the strip tells it instead (WindowModes.away)
        if windowModes.mode == .notch { statusItem?.button?.title = " 🌙"; return }
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
        let c = SummaryView(title: title, since: since, until: until, list: list) { [weak self] id in
            guard let id, let f = self?.tank.fish.first(where: { $0.id == id }) else { return nil }
            return NSColor(red: CGFloat(f.color.x), green: CGFloat(f.color.y), blue: CGFloat(f.color.z), alpha: 1)
        }
        c.close = { [weak self] in self?.card?.removeFromSuperview(); self?.card = nil; self?.tank.highlighted = nil; self?.tank.scenery.chestOpen = false }
        c.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(c)
        NSLayoutConstraint.activate([
            c.centerXAnchor.constraint(equalTo: window.contentView!.centerXAnchor),
            c.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 40),
        ])
        card = c
        show()
        tank.scenery.chestOpen = true          // the treasure chest opens while the summary is open

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
        renderer.weeds = tank.weeds.uniforms()
        tank.shaderTime = renderer.shaderTime
        // look settings (Preferências → Aparência); FISHBOTS_BLOOM wins
        let d = UserDefaults.standard
        renderer.bloom = Env.value("BLOOM").flatMap(Float.init) ?? Float(d.object(forKey: "bloom") as? Double ?? 1.1)
        tank.motes.show = d.object(forKey: "marineSnow") as? Bool ?? true
        tank.dust.show = d.object(forKey: "goldenDust") as? Bool ?? true
        let hourColors = d.object(forKey: "hourColors") as? Bool ?? true
        // the quake also moves the background (the sprites move in Tank.sprites)
        var u = Uniforms(res: .zero, time: 0, turbidity: tank.turbidity, light: tank.light, alert: alert, pix: .zero,
                         gaze: tank.gaze + tank.scene.shakeOffset * 0.02, flash: tank.scene.flash, grade: hourColors ? (Themes.current.sky ?? Sky()).grade(hour: hourNow()) : [1, 1, 1, 0],
                         scene: [tank.gauges.highest("waves") ?? 0, tank.gauges.highest("rain") ?? 0,
                                 tank.gauges.highest("temperature") ?? 0.5, tank.gauges.highest("fog") ?? 0],
                         sky: (Themes.current.sky ?? Sky()).disc(hour: hourNow()),
                         flashColor: SIMD4(tank.scene.flashColor, 0))
        u.setLamps(tank.fauna.lamps(tank))
        visual.size = tank.size
        if visual.sway == nil {
            visual.sway = { [unowned self] x, s in self.tank.weeds.dance(self.tank, at: x, strength: s) }
            visual.weedTips = { [unowned self] in self.tank.weeds.tips(self.tank) }
            visual.flashScene = { [unowned self] s, c in self.tank.scene.flashNow(s, color: c) }
            visual.stream = { [unowned self] v in self.tank.musicStream(v) }
        }
        visual.light = tank.light / (1 - 0.22 * min(1, Float(errors) / 3))   // daylight, without the darkening from errors
        visual.hush = tank.crowd
        visual.update(dt: min(dt, 0.05))
        // dressing by the theme turned on or off in the Preferences
        if themeKeeper.dressedWith.on != FishKinds.dressByTheme { themeKeeper.apply() }
        // the widget: no visualizer, the water stays calm around who needs you
        let sprites = packGuard.filter((tank.compact ? [] : visual.sprites()) + tank.sprites())
        // the album art's colors, while music plays: the water's light and the aurora take them, slowly
        let artGoal: Float = AlbumArt.enabled && NowPlaying.playing && AlbumArt.colors != nil ? 1 : 0
        artTint += (artGoal - artTint) * min(1, dt * 0.4)
        if let c = AlbumArt.colors {
            artA += (c.0 - artA) * min(1, dt * 0.5)
            artB += (c.1 - artB) * min(1, dt * 0.5)
        }
        let baseU = Themes.current.uniforms
        func tint(_ b: SIMD4<Float>, _ c: SIMD3<Float>, _ k: Float) -> SIMD4<Float> { SIMD4(mix(SIMD3(b.x, b.y, b.z), c, t: k * artTint), b.w) }
        renderer.theme.rays = tint(baseU.rays, artA, 0.5)
        renderer.theme.caustics = tint(baseU.caustics, artB, 0.45)
        renderer.theme.surface = tint(baseU.surface, artA, 0.3)
        renderer.theme.shallow = tint(baseU.shallow, artB * 0.45, 0.2)
        visual.art = (artA, artB)
        visual.artMix = artTint
        // the theme's background from a pack: counted by the guard, and left out while it's being tested
        let theme = Themes.current
        if theme.uniforms.pack.x > 0.5, let bg = PackBackgrounds.all.first(where: { $0.id == theme.id }) {
            packGuard.notePresent(bg.pack)
            renderer.theme.pack = packGuard.hidden.contains(bg.pack) ? .zero : theme.uniforms.pack
        }
        return (u, sprites)
    }

    /// Recording a demo (/test/do?footer=off): no footer, whatever the mouse does.
    var demoQuiet = false
    /// The hour set by /test/do?hour= (recording a demo), over FISHBOTS_HOUR and the clock.
    var demoHour: Float?

    /// The hour now, with minutes (FISHBOTS_HOUR fixes it, to see dawn or dusk any time).
    private func hourNow() -> Float {
        if let h = demoHour { return h }
        if let h = Env.value("HOUR").flatMap(Float.init) { return h }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Float(c.hour ?? 12) + Float(c.minute ?? 0) / 60
    }

    /// Real daylight: brightens in the morning, darkens at night (without going black).
    private func daylight() -> Float {
        let h = hourNow()
        let day = smoothstep(5.5, 8, h) * (1 - smoothstep(18, 20.5, h))
        let range = (Themes.current.sky ?? Sky()).light                         // the theme's night and midday brightness
        return range.lowerBound + (range.upperBound - range.lowerBound) * day
    }

    // MARK: - keys and menu

    func key(_ k: String) {
        if cards.key(k) { return }
        if k == "⎋" && windowModes.escape() { return }
        switch k {
        case "d": toggleDemo()
        case "m": toggleMute()
        case "t": toggleFloat()
        case "e": openThemePicker()
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
        synth.engine.mainMixerNode.outputVolume = 0.9 * volume
        synth.music.outputVolume = ducked ? 1 / 3 : 1
    }

    private(set) lazy var preferences = PreferencesWindow(Prefs.Actions(
        openAtLogin: { SMAppService.mainApp.status == .enabled },
        toggleLogin: { [unowned self] in self.toggleLogin() },
        menuBarOnly: { UserDefaults.standard.bool(forKey: "menuBarOnly") },
        toggleMenuBarOnly: { [unowned self] in self.toggleMenuBarOnly() },
        floating: { [unowned self] in self.window.level == .floating },
        toggleFloat: { [unowned self] in self.toggleFloat() },
        soundOn: { [unowned self] in !self.synth.muted.load(ordering: .relaxed) },
        toggleMute: { [unowned self] in self.toggleMute() },
        setShortcut: { [unowned self] action, s in action.shortcut = s ?? action.standard; self.registerHotkey() },
        pauseShortcut: { [unowned self] paused in self.registerHotkey(paused: paused) },
        volume: { [unowned self] in Double(self.volume) },
        setVolume: { [unowned self] in self.volume = Float($0) },
        applyTheme: { [unowned self] in self.themeKeeper.apply() },
        openThemePicker: { [unowned self] in self.openThemePicker() },
        applyLanguage: { L10n.setting = $0 },
        reloadAgents: { [unowned self] in self.reloadAgents() },
        refreshFish: { [unowned self] in for f in self.tank.fish where !f.decor { Providers.refresh(f) } },
        chooseWidgetPlace: { [unowned self] in self.windowModes.choose($0) },
        widgetSizeChanged: { [unowned self] in self.windowModes.sizeChanged() },
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
    // MARK: - widget mode (WindowModes)

    @objc func toggleWidget() { windowModes.toggle() }

    @objc func toggleFloat() {
        window.level = window.level == .floating ? .normal : .floating
        window.collectionBehavior = window.level == .floating ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }
    @objc func feed() { key("f") }
    @objc func toggleFocus() { Attention.focus.toggle() }
    @objc func toggleAmbientMusic() {
        // yielding to your music (it played and paused): ⌘A brings the aquarium's back instead of turning it off
        if UserDefaults.standard.bool(forKey: "ambientMusic") && music.yielded && !NowPlaying.playing {
            music.yielded = false
            tank.fish(source: NowPlaying.source, entity: NowPlaying.entity)?.offer = nil
            tank.notice = (tr("música do aquário"), tank.time)
            return
        }
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "ambientMusic"), forKey: "ambientMusic")
        music.yielded = false
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

extension Float { var cg: CGFloat { CGFloat(self) } }

/// SF Pro Rounded: the labels and the footer (friendlier, and it reads well small).
func rounded(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    return f.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? f
}
