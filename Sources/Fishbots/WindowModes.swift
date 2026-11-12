import AppKit

/// The aquarium's window has three shapes, all the same window (the tank's coordinates are the view's points, so it
/// can't be drawn twice at two sizes):
/// - normal: the titled window;
/// - corner: the widget, a small frameless window in a corner, always on top and on every Space;
/// - notch: the widget at the top of a monitor, around its notch (or a notch drawn there). Closed, it's a black strip
///   around the notch (NotchStrip.swift; nothing is drawn by Metal); with the mouse over it or a click, it opens into a
///   small tank hanging from the notch.
/// Both widgets show only who needs you (Tank.compact). W, the menu or the right-click menu switch them, and the app
/// comes back in the widget it quit in (`widgetOn`).
final class WindowModes {
    enum Mode { case normal, corner, notch }
    private(set) var mode: Mode = .normal

    private let window: NSWindow
    private let view: NSView
    private let labels: NSView
    private let tank: Tank
    /// A card is open over the tank: the notch stays open.
    var cardOpen: () -> Bool = { false }
    /// Told when drawing should stop or start again (the notch closed or opened).
    var onDrawingChanged: () -> Void = {}
    /// The name on the notch was clicked: go to that session's terminal.
    var onGo: (String) -> Void = { _ in }
    /// A fish's pending permission request, and the answers that fit on the notch (none: too long for it).
    var answers: (Fish) -> (Int, [NotchEars.Action])? = { _ in nil }
    /// An answer clicked on the notch (Cards.decide).
    var onAnswer: (Int, String) -> Void = { _, _ in }
    /// The album's cover, while music plays.
    var cover: () -> CGImage? = { nil }
    /// The music fish, while a song plays: its id and "♪ title — artist".
    var song: () -> (id: String, name: String)? = { nil }
    /// Right click on the notch.
    var onMenu: (NSEvent, NSView) -> Void = { _, _ in }
    /// What to show under a name on hover: what it asked (the question, the command it wants to run…) and its
    /// latest steps, drawn (StepTrail).
    struct Peek {
        var text: String?
        var steps: [StepTrail.Step] = []
        var busy = false
        var tint: NSColor = .white
    }
    var peek: (String) -> Peek? = { _ in nil }
    /// A session takes a reply (the 🎙 shows), and the 🎙 was clicked: its card opens listening.
    var canVoice: (Fish) -> Bool = { _ in false }
    var onVoice: (String) -> Void = { _ in }
    /// The "+" on the strip: a new session.
    var onNewSession: () -> Void = {}
    /// Files or text dropped on the strip: to which session (a menu at that point of the view).
    var onDrop: (String, NSView, NSPoint) -> Void = { _, _, _ in }
    /// Back after a while away: what happened meanwhile, in a line (nil: nothing to tell).
    var away: () -> String? = { nil }
    /// That line was clicked: the full summary.
    var onAway: () -> Void = {}
    /// The notch closed (what was open inside it closes too).
    var onClosed: () -> Void = {}

    private var normalFrame: NSRect?
    private var levelBefore: NSWindow.Level = .normal

    init(window: NSWindow, view: NSView, labels: NSView, tank: Tank) {
        self.window = window
        self.view = view
        self.labels = labels
        self.tank = tank
        NotificationCenter.default.addObserver(forName: Self.animationsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.ears?.animated = Self.animated
        }
        // a monitor plugged in or out, or the resolution changed: the notch finds its place again
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.mode == .notch else { return }
            self.reenter()
        }
    }

    var isWidget: Bool { mode != .normal }
    /// Dragging the water moves the window: only the corner widget (the notch stays on the notch).
    var draggable: Bool { mode == .corner }
    /// The tank can't be seen: the notch is closed.
    var holdsDrawing: Bool { mode == .notch && !notchOpen }

    /// W: in and out of the widget, where `widgetPlace` says.
    func toggle() {
        if isWidget { leave() } else { enterWidget() }
        UserDefaults.standard.set(isWidget, forKey: "widgetOn")
    }

    /// The app was quit in the widget: it starts in it again.
    static var startsInWidget: Bool { UserDefaults.standard.bool(forKey: "widgetOn") }

    /// Quitting: back to the normal window (so it isn't remembered as the window's size), keeping `widgetOn`.
    func quit() {
        if isWidget { leave() }
    }

    // MARK: - where the widget goes

    /// `widgetPlace`: "corner", or "screen:<display number>" for the top of that monitor (its notch, or a notch drawn
    /// in the middle of its menu bar). Unset: the Mac's notch if there is one, else the corner.
    static var place: String {
        get { UserDefaults.standard.string(forKey: "widgetPlace") ?? (notchScreen().map { "screen:\(number($0))" } ?? "corner") }
        set { UserDefaults.standard.set(newValue, forKey: "widgetPlace") }
    }

    static func number(_ s: NSScreen) -> Int {
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    /// The monitor the widget goes to the top of (nil: the corner). A monitor that was unplugged: the notch's, else
    /// the main one.
    private static func placeScreen() -> NSScreen? {
        let p = place
        guard p.hasPrefix("screen:") else { return nil }
        let n = Int(p.dropFirst(7)) ?? 0
        return NSScreen.screens.first { number($0) == n } ?? notchScreen() ?? NSScreen.main
    }

    /// `widgetClick`: the notch opens with a click instead of with the mouse over it.
    static var opensOnClick: Bool {
        get { UserDefaults.standard.bool(forKey: "widgetClick") }
        set { UserDefaults.standard.set(newValue, forKey: "widgetClick") }
    }

    /// `widgetAnimations`: the notch's fish swim, bubble and a light runs along it. Unset: on, unless the Mac is set
    /// to reduce motion.
    static var animated: Bool {
        get {
            let d = UserDefaults.standard
            return d.object(forKey: "widgetAnimations") != nil ? d.bool(forKey: "widgetAnimations") : !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        set { UserDefaults.standard.set(newValue, forKey: "widgetAnimations"); NotificationCenter.default.post(name: animationsChanged, object: nil) }
    }
    static let animationsChanged = Notification.Name("fishbotsWidgetAnimations")

    /// `widgetSize`: how big the notch's tank is when open.
    static let sizes: [(id: String, name: String, size: NSSize)] = [
        ("small", "Pequeno", NSSize(width: 420, height: 190)),
        ("medium", "Médio", NSSize(width: 540, height: 250)),
        ("large", "Grande", NSSize(width: 720, height: 340)),
    ]
    static var size: String {
        get { UserDefaults.standard.string(forKey: "widgetSize") ?? "medium" }
        set { UserDefaults.standard.set(newValue, forKey: "widgetSize") }
    }
    private static var openSize: NSSize { sizes.first { $0.id == size }?.size ?? sizes[1].size }
    /// Opened for something bigger than the tank (the summary): this size until it closes.
    private var sizeOverride: NSSize?

    /// Opens big (the largest size) until it closes, for a card that needs the room.
    func openLarge() {
        guard mode == .notch else { return }
        sizeOverride = Self.sizes.last?.size
        if notchOpen { layoutNotch(open: true, animate: true) } else { setNotchOpen(true, hold: 4) }
    }

    /// The size changed in the Preferences: an open notch takes it now.
    func sizeChanged() {
        if mode == .notch && notchOpen { layoutNotch(open: true, animate: true) }
    }

    // MARK: - keyboard

    /// The app that was in front before the notch took the keyboard: it gets it back when the notch closes.
    private var frontBefore: NSRunningApplication?

    /// The open notch takes the keyboard (Tab through who needs you, Enter to their terminal, Esc closes).
    func takeKeyboard() {
        guard mode == .notch else { return }
        if !NSApp.isActive, let f = NSWorkspace.shared.frontmostApplication, f != NSRunningApplication.current { frontBefore = f }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
    }

    /// Esc with nothing else to close: an open notch closes. False when it isn't one.
    func escape() -> Bool {
        guard mode == .notch, notchOpen else { return false }
        setNotchOpen(false)
        return true
    }

    /// The notch closed while it had the keyboard: back to the app that was in front.
    private func giveKeyboardBack() {
        guard let f = frontBefore else { return }
        frontBefore = nil
        if NSApp.isActive { f.activate() }
    }

    /// Chosen from the menu: the widget moves there now if it's showing.
    func choose(_ p: String) {
        Self.place = p
        if isWidget { reenter() }
    }

    private func enterWidget() {
        if let s = Self.placeScreen() { enterNotch(s) } else { enterCorner() }
    }

    /// From one widget to another (another monitor, the corner), without passing through the normal window.
    private func reenter() {
        if mode == .notch { leaveNotch() }
        if mode == .corner { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "widgetFrame") }
        enterWidget()
    }

    // MARK: - normal

    private func leave() {
        guard let from = normalFrame, let content = window.contentView else { return }
        if mode == .corner { UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "widgetFrame") }
        if mode == .notch { leaveNotch() }
        mode = .normal
        tank.compact = false
        normalFrame = nil
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.level = levelBefore
        window.collectionBehavior = window.level == .floating ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
        window.isOpaque = true
        window.backgroundColor = .black
        content.layer?.cornerRadius = 0
        content.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        window.setFrame(from, display: true, animate: true)
        window.setFrameAutosaveName("Fishbots")        // remember the normal window's size again
        window.invalidateShadow()
        onDrawingChanged()
    }

    /// The window leaves its normal shape: what's kept to come back to it.
    private func leaveNormal() {
        guard mode == .normal else { return }
        normalFrame = window.frame
        window.setFrameAutosaveName("")                // the widget's size isn't the window's size
        levelBefore = window.level
        tank.compact = true
        window.contentView?.wantsLayer = true
    }

    // MARK: - corner

    private func enterCorner() {
        guard let content = window.contentView else { return }
        leaveNormal()
        mode = .corner
        window.styleMask = [.borderless, .resizable]
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        content.layer?.cornerRadius = 16
        content.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        content.layer?.masksToBounds = true
        let vf = (window.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = NSRect(x: vf.maxX - 436, y: vf.minY + 16, width: 420, height: 260)
        if let s = UserDefaults.standard.string(forKey: "widgetFrame") {
            let r = NSRectFromString(s)
            if r.width > 200 && vf.intersects(r) { frame = r }
        }
        window.setFrame(frame, display: true, animate: true)
        window.orderFrontRegardless()
        window.invalidateShadow()
    }

    // MARK: - notch

    /// How the notch sits on its screen (screen coordinates).
    private struct Notch {
        let screen: NSScreen
        /// The notch itself: the camera housing, as tall as the menu bar.
        let rect: NSRect
        /// Closed: the notch with its ears (they grow with what they show).
        func closed(left: CGFloat, right: CGFloat) -> NSRect {
            NSRect(x: rect.minX - left, y: rect.minY, width: left + rect.width + right, height: rect.height)
        }
        /// Open: the tank hangs below the notch, wide enough for the ears.
        func opened(_ size: NSSize, ears: CGFloat) -> NSRect {
            let w = max(size.width, rect.width + 2 * ears)
            return NSRect(x: rect.midX - w / 2, y: rect.maxY - rect.height - size.height, width: w, height: rect.height + size.height)
        }
    }

    private var notch: Notch?
    private(set) var notchOpen = false
    private var ears: NotchEars?
    private var closedFrame: NSRect {
        let c = ears?.content ?? .init()
        return notch?.closed(left: NotchEars.leftWidth(c, plus: ears?.hovering ?? false),
                             right: NotchEars.rightWidth(c, compact: ears?.compact ?? false)) ?? .zero
    }
    private var openFrame: NSRect {
        let c = ears?.content ?? .init()
        return notch?.opened(sizeOverride ?? Self.openSize,
                             ears: max(NotchEars.leftWidth(c, plus: true), NotchEars.rightWidth(c, compact: false))) ?? .zero
    }
    /// The Mac's own notch (not one drawn on another monitor): there the strip keeps narrow, off the menu bar's icons.
    private var realNotch: Bool { (notch?.screen.safeAreaInsets.top ?? 0) > 0 }
    private var watch: Timer?
    /// Since when the mouse has been in (closed) or out (open): opening and closing wait a little, so passing by
    /// doesn't flicker it.
    private var mouseSince: Date?

    /// The Mac's screen, the one with a notch.
    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    /// The notch, or on a monitor without one, a notch drawn in the middle of its menu bar.
    private static func notchRect(_ s: NSScreen) -> NSRect {
        let f = s.frame
        guard s.safeAreaInsets.top > 0 else {
            let bar = f.maxY - s.visibleFrame.maxY
            let h = bar >= 20 ? bar : 24            // a menu bar that hides itself: its usual height
            return NSRect(x: f.midX - 90, y: f.maxY - h, width: 180, height: h)
        }
        let h = s.safeAreaInsets.top
        let left = s.auxiliaryTopLeftArea?.width ?? f.width / 2 - 100
        let right = s.auxiliaryTopRightArea?.width ?? f.width / 2 - 100
        let w = max(120, f.width - left - right)
        return NSRect(x: f.minX + left, y: f.maxY - h, width: w, height: h)
    }

    private func enterNotch(_ screen: NSScreen) {
        guard let content = window.contentView else { return }
        leaveNormal()
        mode = .notch
        let n = Notch(screen: screen, rect: Self.notchRect(screen))
        notch = n
        window.styleMask = [.borderless]
        window.level = .statusBar                    // over the menu bar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        content.layer?.backgroundColor = NSColor.black.cgColor
        content.layer?.masksToBounds = true
        // only the bottom corners are round: the top merges with the notch and the screen's edge
        content.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        // the tank sits below the notch's strip (the strip is black, like the notch)
        view.autoresizingMask = []
        labels.autoresizingMask = []
        let e = NotchEars(frame: content.bounds)
        e.autoresizingMask = [.width, .height]
        e.notchWidth = n.rect.width
        e.stripHeight = n.rect.height
        e.animated = Self.animated
        e.onClick = { [weak self] hit in self?.clicked(hit) }
        e.onMenu = { [weak self, weak e] ev in if let self, let e { self.onMenu(ev, e) } }
        e.onDrop = { [weak self, weak e] text, at in if let self, let e { self.onDrop(text, e, at) } }
        needIds = nil
        lastStates = [:]
        finished = nil
        hiddenForFullScreen = false
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        content.addSubview(e)
        ears = e
        notchOpen = false
        layoutNotch(open: false, animate: false)
        window.orderFrontRegardless()
        watch = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.watchMouse() }
        onDrawingChanged()
    }

    private func leaveNotch() {
        watch?.invalidate()
        watch = nil
        ears?.removeFromSuperview()
        ears = nil
        band?.removeFromSuperview()
        band = nil
        bandKey = nil
        notch = nil
        notchOpen = false
        mouseSince = nil
        frontBefore = nil
        hiddenForFullScreen = false
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.contentView?.layer?.backgroundColor = nil
        view.isHidden = false
        labels.isHidden = false
        if let b = window.contentView?.bounds { view.frame = b; labels.frame = b }
        view.autoresizingMask = [.width, .height]
        labels.autoresizingMask = [.width, .height]
    }

    private func layoutNotch(open: Bool, animate: Bool) {
        guard let n = notch, let content = window.contentView else { return }
        let frame = open ? openFrame : closedFrame
        ears?.notchX = n.rect.minX - frame.minX
        content.layer?.cornerRadius = open ? 18 : 10
        window.hasShadow = open
        if open {
            let tankRect = NSRect(x: 0, y: 0, width: frame.width, height: frame.height - n.rect.height)
            view.frame = tankRect
            labels.frame = tankRect
        }
        bandKey = nil
        updateBand(open: open, frame: frame)
        view.isHidden = !open
        labels.isHidden = !open
        ears?.open = open
        ears?.compact = !open && realNotch && !mouseOver
        ears?.hovering = open || mouseOver
        if animate {
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 0.2
                c.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
        window.invalidateShadow()
    }

    /// Opened from elsewhere (a notification, "who needs you"): it stays open a few seconds even without the mouse.
    private var heldOpenUntil = Date.distantPast

    func setNotchOpen(_ open: Bool, hold: TimeInterval = 0) {
        guard mode == .notch else { return }
        if open && hold > 0 { heldOpenUntil = Date().addingTimeInterval(hold) }
        if !open { heldOpenUntil = .distantPast }
        guard open != notchOpen else { return }
        notchOpen = open
        mouseSince = nil
        if !open { sizeOverride = nil; hidePeek() }
        layoutNotch(open: open, animate: true)
        if !open { giveKeyboardBack(); onClosed() }
        onDrawingChanged()
    }

    // MARK: - full screen

    /// The drawn notch hides while an app is full screen on its monitor (the Mac's own notch stays: that band is
    /// black there anyway).
    private var hiddenForFullScreen = false
    private var fullScreenCheckedAt = Date.distantPast

    private func checkFullScreen() {
        guard let n = notch, !realNotch, Date().timeIntervalSince(fullScreenCheckedAt) > 1 else { return }
        fullScreenCheckedAt = Date()
        let hide = Self.fullScreenApp(on: n.screen)
        guard hide != hiddenForFullScreen else { return }
        hiddenForFullScreen = hide
        if hide && notchOpen { setNotchOpen(false) }
        if hide { hidePeek() }
        window.alphaValue = hide ? 0 : 1
        window.ignoresMouseEvents = hide
    }

    /// Some other app's window covers the whole monitor (full screen).
    private static func fullScreenApp(on screen: NSScreen) -> Bool {
        guard let primary = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let f = screen.frame
        let want = CGRect(x: f.minX, y: primary - f.maxY, width: f.width, height: f.height)    // CG's top-left origin
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        return list.contains { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowOwnerPID as String] as? Int) != me,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return false }
            let r = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            return r.integral == want.integral
        }
    }

    private func watchMouse() {
        guard notch != nil else { return }
        checkFullScreen()
        if hiddenForFullScreen { return }
        let m = NSEvent.mouseLocation
        // the Mac's notch, closed: the right side widens (name, answers) only while the mouse is over it
        let over = !notchOpen && closedFrame.insetBy(dx: -2, dy: -2).contains(m)
        if over != mouseOver {
            mouseOver = over
            ears?.compact = !notchOpen && realNotch && !over
            ears?.hovering = notchOpen || over
            if !notchOpen { layoutNotch(open: false, animate: true) }
        }
        refreshEars()
        updatePeek(m)
        // opening with a click: the mouse alone doesn't open it (it still closes when the mouse goes away)
        if !notchOpen && Self.opensOnClick { mouseSince = nil; return }
        let inside = notchOpen ? openFrame.insetBy(dx: -8, dy: -8).contains(m) || cardOpen() || Date() < heldOpenUntil
                                   || (window.isKeyWindow && NSApp.isActive)       // it has the keyboard: Esc or a click elsewhere closes it
                               : closedFrame.insetBy(dx: -2, dy: -2).contains(m)
        // closed: open once the mouse rests on it a moment; open: close once it has been away a while
        let wantsChange = notchOpen ? !inside : inside
        guard wantsChange else { mouseSince = nil; return }
        let since = mouseSince ?? Date()
        mouseSince = since
        if Date().timeIntervalSince(since) > (notchOpen ? 0.6 : 0.12) { setNotchOpen(!notchOpen) }
    }

    /// A click on the strip: on the name, to that session's terminal; elsewhere, opens it (or closes it, when it
    /// opens with a click).
    private func clicked(_ hit: NotchEars.Hit) {
        switch hit {
        case .action(let id, let a): onAnswer(id, a); return
        case .plus: onNewSession(); return
        case .mic: if let id = ears?.content.whoId { onVoice(id) }; return
        case .name:
            if let id = ears?.content.whoId { onGo(id); return }
            if ears?.content.away != nil { onAway(); return }
            if let id = ears?.content.songId { onGo(id); return }
            if let id = ears?.content.workingId { onGo(id); return }
        case .strip: break
        }
        if !notchOpen { setNotchOpen(true); takeKeyboard() } else if Self.opensOnClick { setNotchOpen(false) }
    }

    /// The mouse is over the closed strip.
    private var mouseOver = false
    /// The last pulse: several needing you at once pulse once.
    private var pulsedAt = Date.distantPast

    /// Who needed you at the last look (nil: not looked yet, so the first look doesn't pulse).
    private var needIds: Set<String>?
    /// Each session's state at the last look, to see who just finished.
    private var lastStates: [String: State] = [:]
    private var finished: (name: String, until: Date)?

    /// The ears follow the sessions.
    private func refreshEars() {
        guard let ears, mode == .notch else { return }
        let live = tank.fish.filter { !$0.decor && !$0.leaving && $0.source != NowPlaying.source }
        // who needs you, sessions and the plugins' presences alike: errors and alerts first, then the longest waiting
        struct Need { let id: String; let name: String; let state: State; let since: Double; let fish: Fish? }
        let needs = (live.filter { [.waiting, .error, .alert].contains($0.state) }
                        .map { Need(id: $0.id, name: $0.displayTitle ?? $0.label, state: $0.state, since: $0.since, fish: $0) }
                     + tank.scene.needingYou().map { Need(id: "presence:" + $0.id, name: $0.label, state: $0.state, since: $0.since, fish: nil) })
            .sorted { ($0.state != .waiting ? 0 : 1, $0.since) < ($1.state != .waiting ? 0 : 1, $1.since) }
        let busy = live.filter { $0.state == .busy }
        var c = NotchEars.Content(working: busy.count)
        c.colors = busy.prefix(3).map { NSColor(red: CGFloat($0.color.x), green: CGFloat($0.color.y), blue: CGFloat($0.color.z), alpha: 1) }
        if busy.isEmpty {
            c.art = cover()
            if c.art != nil, let s = song() { c.song = s.name; c.songId = s.id }
        }
        // who has been working longest, among those whose steps can be shown when there are
        let withSteps = busy.filter { !$0.history.isEmpty }
        if let longest = (withSteps.isEmpty ? busy : withSteps).min(by: { $0.since < $1.since }) { c.workingName = longest.displayTitle ?? longest.label; c.workingId = longest.id }
        if let n = needs.first {
            c.who = n.name
            c.whoId = n.id
            c.urgent = n.state != .waiting
            c.more = needs.count - 1
            c.waited = Int((tank.time - n.since) / Tank.scale / 60)
            if n.state == .waiting, let f = n.fish, let (req, actions) = answers(f) { c.request = req; c.actions = actions }
            if n.state == .waiting, let f = n.fish, c.request == nil, canVoice(f) { c.voice = true }
        }
        // who went from working to done: "✓ name" for a few seconds
        for f in live where lastStates[f.id] == .busy && f.state == .done {
            finished = (f.displayTitle ?? f.label, Date().addingTimeInterval(5))
        }
        lastStates = Dictionary(live.map { ($0.id, $0.state) }, uniquingKeysWith: { a, _ in a })
        if let d = finished, Date() < d.until { c.finished = d.name } else { finished = nil }
        c.away = away()

        let before = ears.content
        ears.update(c)
        if notchOpen { updateBand(open: true, frame: window.frame) }
        let grew = NotchEars.leftWidth(c, plus: ears.hovering) != NotchEars.leftWidth(before, plus: ears.hovering)
            || NotchEars.rightWidth(c, compact: ears.compact) != NotchEars.rightWidth(before, compact: ears.compact)
        if grew && (!notchOpen || openFrame.width != window.frame.width) { layoutNotch(open: notchOpen, animate: true) }
        // someone new needs you: the strip pulses
        let ids = Set(needs.map(\.id))
        if let was = needIds, !ids.subtracting(was).isEmpty, Date().timeIntervalSince(pulsedAt) > 2.5 {
            pulsedAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ears.pulse(urgent: c.urgent) }   // after the strip grew
        }
        needIds = ids
    }

    // MARK: - the band

    /// Open, a thin band under the strip: whose steps (who needs you, else who has been working longest), drawn live.
    private var band: NSView?
    private var bandKey: (id: String, steps: Int, busy: Bool, width: CGFloat)?

    private func updateBand(open: Bool, frame: NSRect) {
        guard let n = notch, let content = window.contentView else { return }
        let c = ears?.content ?? .init()
        let id = c.whoId.flatMap { $0.hasPrefix("presence:") ? nil : $0 } ?? c.workingId
        guard open, let id, let what = peek(id), !what.steps.isEmpty else {
            band?.removeFromSuperview(); band = nil; bandKey = nil
            return
        }
        if let k = bandKey, k.id == id, k.steps == what.steps.count, k.busy == what.busy, k.width == frame.width { return }
        bandKey = (id, what.steps.count, what.busy, frame.width)
        band?.removeFromSuperview()
        let h: CGFloat = 26
        let b = NSView(frame: NSRect(x: 0, y: frame.height - n.rect.height - h, width: frame.width, height: h))
        b.wantsLayer = true
        b.layer?.backgroundColor = NSColor(white: 0, alpha: 0.38).cgColor
        b.autoresizingMask = [.width, .minYMargin]           // stays under the strip while the notch opens
        let name = (c.whoId == id ? c.who : c.workingName) ?? ""
        let label = NSTextField(labelWithString: name)
        label.font = .systemFont(ofSize: 10.5, weight: .medium)
        label.textColor = NSColor(white: 1, alpha: 0.6)
        label.lineBreakMode = .byTruncatingTail
        let nameW = min(130, ceil(label.fittingSize.width))
        label.frame = NSRect(x: 12, y: (h - 14) / 2, width: nameW, height: 14)
        b.addSubview(label)
        let trailW = frame.width - nameW - 34
        let trail = StepTrail(steps: what.steps, busy: what.busy, tint: what.tint, width: trailW, mini: true, animated: Self.animated)
        trail.translatesAutoresizingMaskIntoConstraints = true
        trail.frame = NSRect(x: nameW + 22, y: (h - StepTrail.miniHeight) / 2, width: trailW, height: StepTrail.miniHeight)
        b.addSubview(trail)
        // over the tank and its labels, under the strip
        if let ears { content.addSubview(b, positioned: .below, relativeTo: ears) } else { content.addSubview(b) }
        band = b
    }

    // MARK: - peek

    private var peekPanel: NSPanel?
    private var peekSince: Date?
    /// What the peek shows now: whose, and how many steps (a new step redraws it).
    private var peekShown: (id: String, steps: Int, busy: Bool)?

    /// The mouse rests on a name (who needs you, or who's working): what it asked and its steps show under the strip.
    private func updatePeek(_ m: NSPoint) {
        guard let ears, let r = ears.nameOnScreen, r.insetBy(dx: -4, dy: -6).contains(m),
              let id = ears.content.whoId ?? (ears.compact ? nil : ears.content.workingId),
              let what = peek(id), what.text?.isEmpty == false || !what.steps.isEmpty else { hidePeek(); return }
        if let s = peekShown, s.id == id, s.steps == what.steps.count, s.busy == what.busy { return }
        let since = peekSince ?? Date()
        peekSince = since
        guard peekShown?.id == id || Date().timeIntervalSince(since) > 0.3, let n = notch else { return }
        showPeek(what, at: r.minX - 10, below: n.rect.minY - 6, on: n.screen)
        peekShown = (id, what.steps.count, what.busy)
    }

    private func showPeek(_ what: Peek, at x: CGFloat, below top: CGFloat, on screen: NSScreen) {
        let panel = peekPanel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            peekPanel = p
            return p
        }()
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(white: 0.06, alpha: 0.96).cgColor
        box.layer?.cornerRadius = 10
        let inner: CGFloat = 360
        var y: CGFloat = 10, height: CGFloat = 10
        var label: NSTextField?
        if let text = what.text, !text.isEmpty {
            let l = NSTextField(wrappingLabelWithString: text.count > 400 ? String(text.prefix(399)) + "…" : text)
            l.font = .systemFont(ofSize: 12)
            l.textColor = NSColor(white: 1, alpha: 0.9)
            l.preferredMaxLayoutWidth = inner
            label = l
            height += l.fittingSize.height
        }
        let trail = what.steps.isEmpty ? nil
            : StepTrail(steps: what.steps, busy: what.busy, tint: what.tint, width: inner, animated: Self.animated)
        if trail != nil { height += StepTrail.height + (label != nil ? 8 : 0) }
        height += 10
        let width = trail != nil ? inner + 24 : min(inner, label?.fittingSize.width ?? inner) + 24
        // top to bottom: the text, then the trail
        if let trail {
            trail.translatesAutoresizingMaskIntoConstraints = true
            trail.frame = NSRect(x: 12, y: y, width: inner, height: StepTrail.height)
            box.addSubview(trail)
            y += StepTrail.height + 8
        }
        if let l = label {
            let h = l.fittingSize.height
            l.frame = NSRect(x: 12, y: y, width: width - 24, height: h)
            box.addSubview(l)
        }
        panel.contentView = box
        let vf = screen.frame
        let left = max(vf.minX + 8, min(x, vf.maxX - width - 8))
        panel.setFrame(NSRect(x: left, y: top - height, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    private func hidePeek() {
        peekSince = nil
        guard peekShown != nil else { return }
        peekShown = nil
        peekPanel?.orderOut(nil)
    }
}

/// Window → Where the widget goes: the top of each monitor, or the corner.
final class WidgetPlaceMenu: NSObject, NSMenuDelegate {
    let modes: () -> WindowModes?
    init(_ modes: @escaping () -> WindowModes?) { self.modes = modes }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = WindowModes.place
        for s in NSScreen.screens {
            let id = "screen:\(WindowModes.number(s))"
            let title = s.safeAreaInsets.top > 0 ? tr("No notch de %@", s.localizedName) : tr("No topo de %@", s.localizedName)
            add(menu, title, id, current)
        }
        menu.addItem(.separator())
        add(menu, tr("Janelinha no canto"), "corner", current)
    }

    private func add(_ menu: NSMenu, _ title: String, _ id: String, _ current: String) {
        let i = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: "")
        i.target = self
        i.representedObject = id
        i.state = current == id ? .on : .off
        menu.addItem(i)
    }

    @objc private func pick(_ i: NSMenuItem) {
        guard let p = i.representedObject as? String else { return }
        modes()?.choose(p)
    }
}
