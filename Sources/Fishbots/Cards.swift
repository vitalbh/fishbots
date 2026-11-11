import AppKit
import simd

/// The cards over the water: the one that opens when the mouse rests on a fish (or Tab picks it), the bubble of a
/// permission request, and what you do from them: reply, stop, allow or deny, go there. It owns what's open and
/// what the mouse and the keyboard are on; the app tells it where the mouse is and calls `control` every frame.
final class Cards: NSObject, NSPopoverDelegate {
    private let tank: Tank
    private let permissions: Permissions
    /// The water's view, where the bubbles point. Made with the window, a little after this.
    var view: TankView!
    /// Reads a fish's question or last reply aloud (the app's voice).
    var read: ((Fish) -> Void)?

    /// The fish under the mouse, and since when.
    private(set) var hoverId: String?
    private var hoverSince = Date()
    private var hoverCard: NSPopover?
    private var hoverCardId: String?
    private var cardSignature = ""
    private var cardCheckedAt = Date.distantPast
    private var pinnedCheckedAt = Date.distantPast
    /// The fish chosen with Tab (its card stays open until Esc or the mouse goes to another fish).
    private(set) var keyboardPick: String?
    private var requestBubble: NSPopover?
    private var sourceBubble: NSPopover?

    init(tank: Tank, permissions: Permissions) {
        self.tank = tank
        self.permissions = permissions
        super.init()
        // Esc closes a card that was dragged off its fish: the one under the mouse, or the one the keys are going to
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.keyCode == 53, !self.pinned.isEmpty else { return e }
            let mouse = NSEvent.mouseLocation
            let windows = self.pinned.values.compactMap { $0.pop.contentViewController?.view.window }
            guard let w = windows.first(where: { $0.frame.contains(mouse) }) ?? windows.first(where: { $0.isKeyWindow }),
                  let out = self.pinned.values.first(where: { $0.pop.contentViewController?.view.window === w }) else { return e }
            out.pop.close()
            return nil
        }
    }

    // MARK: - cards dragged off their fish

    /// Cards the person dragged away from their fish: they stay where they were put, each still following its
    /// session, until closed (their ✕, or the session ending).
    private var pinned: [String: (pop: NSPopover, signature: String)] = [:]

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { popover === hoverCard }

    func popoverDidDetach(_ popover: NSPopover) {
        guard popover === hoverCard, let id = hoverCardId, let f = tank.fish.first(where: { $0.id == id }) else { return }
        pinned[id]?.pop.close()
        pinned[id] = (popover, cardSignature)
        hoverCard = nil
        hoverCardId = nil
        if keyboardPick == id { keyboardPick = nil }
        popover.contentViewController = cardContent(f, pinned: true)
    }

    func popoverDidClose(_ notification: Notification) {
        guard let pop = notification.object as? NSPopover else { return }
        pinned = pinned.filter { $0.value.pop !== pop }
    }

    /// Once a second: a pinned card whose session changed is rebuilt (not while a reply is being written in it), and
    /// one whose fish left closes.
    private func refreshPinned() {
        for (id, card) in pinned {
            guard let f = tank.fish.first(where: { $0.id == id && !$0.leaving }) else { card.pop.close(); continue }
            if (card.pop.contentViewController as? FishCard)?.typing == true { continue }
            let now = signature(f)
            if now != card.signature {
                pinned[id] = (card.pop, now)
                card.pop.contentViewController = cardContent(f, pinned: true)
            }
        }
    }

    var isOpen: Bool { hoverCard != nil }
    /// The open card, if it's a fish's.
    var card: FishCard? { hoverCard?.contentViewController as? FishCard }

    /// The mouse is over this fish now (nil: over none).
    func hover(_ id: String?) {
        if id != hoverId { hoverSince = Date() }
        hoverId = id
    }

    /// Opens a fish's card as if the mouse had rested on it (it stays while nothing else takes the mouse's place).
    func open(_ f: Fish) {
        hoverId = f.id
        hoverSince = Date(timeIntervalSinceNow: -1)
        show(f)
    }

    /// The card was dismissed: it only comes back when the mouse goes over the fish again.
    func forgetHover() { hoverId = nil }

    // MARK: - what a session takes

    /// What the fish's session provider can do now. Nothing that types into the session while a permission request is open.
    func can(_ c: Capability, _ f: Fish) -> Bool {
        guard let p = Providers.of(f.source), p.capabilities(f).contains(c) else { return false }
        return c == .stop || permissions.request(ofFish: f.id) == nil
    }
    func canReply(_ f: Fish) -> Bool { can(.reply, f) }

    /// A session's line for another (`fishbots reply`) when that one is asking something with a menu: it's the
    /// answer. False: it isn't asking that way.
    func answer(_ f: Fish, _ text: String) -> Bool {
        guard let p = permissions.request(ofFish: f.id), p.question != nil else { return false }
        decide(p.id, "answer:" + text)
        return true
    }
    func canStop(_ f: Fish) -> Bool { can(.stop, f) }

    func sendReply(_ f: Fish, _ text: String) {
        guard let provider = Providers.of(f.source) else { return }
        provider.reply(f, text) { [weak self, weak f] error in
            guard let self, let f else { return }
            if let error { self.tank.notice = (tr("não enviei: ") + error, self.tank.time); return }
            f.glow = 1
            self.tank.ring(at: f.pos, color: [0.7, 0.9, 1], size: f.size * 0.5, grow: 110, life: 0.7)
            f.moment = (tr("↩︎ respondido"), self.tank.time + 4)
        }
    }


    // MARK: - hover card

    func control() {
        // the fish under the mouse (or with the card open) swims in circles in place
        tank.focused = hoverCardId ?? hoverId
        let now = Date()
        if !pinned.isEmpty, now.timeIntervalSince(pinnedCheckedAt) > 1 { pinnedCheckedAt = now; refreshPinned() }
        let mouseInCard: Bool = {
            guard let w = hoverCard?.contentViewController?.view.window else { return false }
            return w.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        }()
        // writing a reply: the card stays open until sending or clicking outside
        if (hoverCard?.contentViewController as? FishCard)?.typing == true { return }
        // chosen with Tab: stays open until Esc, or until the mouse rests on another fish
        if let pick = keyboardPick {
            if let id = hoverId, id != pick, now.timeIntervalSince(hoverSince) > 0.5 { keyboardPick = nil }
            else if hoverCardId == pick {
                if let pop = hoverCard, now.timeIntervalSince(cardCheckedAt) > 1, let f = tank.fish.first(where: { $0.id == pick }) {
                    cardCheckedAt = now
                    let a = signature(f)
                    if a != cardSignature { cardSignature = a; let c = cardContent(f); c.keyboardHint = true; pop.contentViewController = c }
                }
                return
            } else { keyboardPick = nil }
        }
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
        if let id = hoverId, now.timeIntervalSince(hoverSince) > 0.5, hoverCardId != id, requestBubble?.isShown != true,
           let f = tank.fish.first(where: { $0.id == id }), view.window?.isVisible == true {
            show(f)
        } else if hoverCard != nil, hoverId == nil, !mouseInCard {
            close()
        } else if let id = hoverId, hoverCardId != nil, hoverCardId != id, !mouseInCard {
            close()
        }
    }

    /// What, if it changes, makes the open card refresh.
    private func signature(_ f: Fish) -> String {
        // its school, and how each one is
        let school: [String] = tank.school(of: f).map { c in
            let asks = permissions.request(ofFish: c.id).map { "\($0.id)" } ?? ""
            return c.id + c.state.rawValue + (c.displayTitle ?? "") + asks + (c.doing ?? c.tool ?? "") + String((c.lastReply ?? "").prefix(40))
        }
        let family: String = school.joined(separator: ",") + "<" + (tank.leader(of: f)?.id ?? "")
        return [f.state.rawValue, f.tool ?? "", f.history.last?.name ?? "", f.history.last?.said ?? "", "\(f.history.count)",
         f.context.map { "\(Int($0 * 100))" } ?? "", f.model ?? "", f.doing ?? "", "\(f.lastReply?.hashValue ?? 0)", f.asked ?? "",
         f.displayTitle ?? "", f.nickname ?? "", f.sub ?? "", "\(permissions.request(ofFish: f.id)?.id ?? 0)",
         "\(f.finished.count)", f.compactingSince == nil ? "" : "c", family].joined(separator: "|")
    }

    func show(_ f: Fish, keyboard: Bool = false) {
        close()
        // its card is already out, pinned somewhere: that one comes to the front instead
        if let out = pinned[f.id] { out.pop.contentViewController?.view.window?.orderFront(nil); return }
        let pop = NSPopover()
        pop.delegate = self
        pop.behavior = .applicationDefined
        pop.animates = false
        pop.appearance = NSAppearance(named: .darkAqua)   // dark glass (see FishCard.glass)
        let content = cardContent(f)
        content.keyboardHint = keyboard
        pop.contentViewController = content
        cardSignature = signature(f)
        cardCheckedAt = Date()
        let r = NSRect(x: CGFloat(f.pos.x) - f.size.cg, y: CGFloat(f.pos.y) - f.size.cg * 0.6, width: f.size.cg * 2, height: f.size.cg * 1.2)
        pop.show(relativeTo: r, of: view, preferredEdge: .maxY)
        hoverCard = pop
        hoverCardId = f.id
    }

    /// `pinned`: for a card dragged off its fish (acting from it doesn't close it, and it has its own ✕).
    private func cardContent(_ f: Fish, pinned isPinned: Bool = false) -> FishCard {
        let request = permissions.request(ofFish: f.id)
        let resp: ((String) -> Void)? = canReply(f) ? { [weak self, weak f] text in
            guard let self, let f else { return }
            if !isPinned { self.close() }
            self.sendReply(f, text)
        } : nil
        let stopFn: (() -> Void)? = canStop(f) ? { [weak self, weak f] in
            guard let self, let f else { return }
            if !isPinned { self.close() }
            Providers.of(f.source)?.stop(f)
            self.tank.notice = (tr("Esc em %@", f.nickname ?? f.label), self.tank.time)
        } : nil
        let card = FishCard(fish: f, request: request, reply: resp, stop: stopFn) { [weak self] action in
            guard let self, let p = request else { return }
            if !isPinned { self.close() }
            self.decide(p.id, action)
        }
        card.go = { [weak f] in if let f { Whereabouts.go(f) } }
        if SessionControl.canEnd(f) {
            card.end = { [weak f] in if let f { (NSApp.delegate as? AppDelegate)?.endSession(f) } }
        }
        card.school = tank.school(of: f)
        card.leader = tank.leader(of: f)
        card.visit = { [weak self] other in self?.show(other) }
        card.asks = { [weak self] child in self?.permissions.request(ofFish: child.id) }
        card.answerFor = { [weak self] p, action in self?.decide(p.id, action) }
        card.rebuild = { [weak self, weak f] in
            guard let self, let f else { return }
            if isPinned, let out = self.pinned[f.id] {
                self.pinned[f.id] = (out.pop, self.signature(f))
                out.pop.contentViewController = self.cardContent(f, pinned: true)
            } else if let pop = self.hoverCard, self.hoverCardId == f.id {
                pop.contentViewController = self.cardContent(f)
                self.cardSignature = self.signature(f)
            }
        }
        if isPinned { card.unpin = { [weak self, weak f] in if let f { self?.pinned[f.id]?.pop.close() } } }
        return card
    }

    func close() {
        hoverCard?.close()
        hoverCard = nil
        hoverCardId = nil
    }

    // MARK: - permission request

    func showRequest(_ p: Permissions.Request, fish f: Fish) {
        requestBubble?.close()
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = RequestView(request: p, label: f.label) { [weak self, weak pop] action in
            guard let self else { return }
            pop?.close()
            self.decide(p.id, action)
        }
        let r = NSRect(x: CGFloat(f.pos.x) - 20, y: CGFloat(f.pos.y) - 20, width: 40, height: 40)
        pop.show(relativeTo: r, of: view, preferredEdge: .maxY)
        requestBubble = pop
    }

    // MARK: - a light on the side glass

    /// The card of a light on the side glass: what its source keeps there, pointing at the light.
    func showSource(of p: Presence) {
        sourceBubble?.close()
        let items = tank.scene.presences.filter { $0.source == p.source && $0.kind.motion == .glass && !$0.leaving }
        let card = SourceCard(source: p.source, items: items, picked: p.id) { [tank] in tank.scene.lamp($0) }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.appearance = NSAppearance(named: .darkAqua)
        card.open = { [weak pop] item in
            guard let l = item.link, let u = URL(string: l), ["http", "https"].contains(u.scheme ?? "") else { return }
            pop?.close()
            NSWorkspace.shared.open(u)
        }
        pop.contentViewController = card
        let r = NSRect(x: CGFloat(p.pos.x) - 10, y: CGFloat(p.pos.y) - 10, width: 20, height: 20)
        pop.show(relativeTo: r, of: view, preferredEdge: p.side > 0 ? .maxX : .minX)
        sourceBubble = pop
    }

    /// "allow", "deny" or "go" (no decision: takes you to the session to answer there).
    func decide(_ id: Int, _ action: String) {
        guard let p = permissions.request(id: id) else { return }
        let f = tank.fish(source: p.source, entity: p.session)
        switch action {
        case let a where a.hasPrefix("answers:"):
            // a form of questions, filled in on the card
            let picked = (try? JSONSerialization.jsonObject(with: Data(a.dropFirst("answers:".count).utf8))) as? [String: String] ?? [:]
            guard permissions.answer(id, all: picked) else { return }
            if let f {
                f.glow = 1
                tank.ring(at: f.pos, color: [0.5, 1, 0.6], size: f.size * 0.5, grow: 120, life: 0.7)
                tank.upsert(source: p.source, entity: p.session, state: .busy, label: nil)
            }
        case let a where a.hasPrefix("answer:"):
            // a question with a menu, answered here: the tool gets its answer and the terminal shows no menu
            guard permissions.answer(id, String(a.dropFirst("answer:".count))) else { return }
            if let f {
                f.glow = 1
                tank.ring(at: f.pos, color: [0.5, 1, 0.6], size: f.size * 0.5, grow: 120, life: 0.7)
                tank.upsert(source: p.source, entity: p.session, state: .busy, label: nil)
            }
        case "allow", "deny":
            permissions.reply(id, action)
            if let f {
                f.glow = 1
                tank.ring(at: f.pos, color: action == "allow" ? [0.5, 1, 0.6] : [1, 0.5, 0.45], size: f.size * 0.5, grow: 120, life: 0.7)
                tank.upsert(source: p.source, entity: p.session, state: .busy, label: nil)
            }
        case "allow-go":
            // questions the terminal's menu has to take: let it show them, and go there
            permissions.reply(id, "allow")
            if let f { Whereabouts.go(f) }
        default:
            if let f { Whereabouts.go(f) }
        }
    }

    // MARK: - keyboard: moving through who needs you


    /// The Tab order: agent sessions waiting for you first (a permission request or a question, the latest first), then the
    /// other agent sessions (the most recently active first), then anything else asking for attention (a broken PR, an alert).
    private var needingYou: [Fish] {
        let live = tank.fish.filter { !$0.decor && !$0.leaving }
        func waits(_ f: Fish) -> Bool { f.state == .waiting || permissions.request(ofFish: f.id) != nil }
        let agents = live.filter(\.isAgent)
        let waiting = agents.filter(waits).sorted { $0.since > $1.since }
        let active = agents.filter { !waits($0) }.sorted { $0.seen > $1.seen }
        let others = live.filter { !$0.isAgent && [.waiting, .error, .alert].contains($0.state) }.sorted { $0.since < $1.since }
        return waiting + active + others
    }

    private func pick(_ f: Fish) {
        keyboardPick = f.id
        hoverId = nil
        show(f, keyboard: true)
        // a session that takes replies: the field is ready to type (Enter sends)
        if canReply(f) { (hoverCard?.contentViewController as? FishCard)?.focusReply() }
        f.glow = max(f.glow, 0.6)
        tank.ring(at: f.pos, color: [1, 0.9, 0.5], size: f.size * 0.5, grow: 110, life: 0.6)
    }

    /// Tab / ⇧Tab, Return, Esc, ⌘R (hear), ⌘D (speak), ⌘↩ (go), and A/N on a permission request (no text field there).
    /// Returns false when the key isn't about the keyboard pick (then it does what it always did).
    func key(_ k: String) -> Bool {
        let list = needingYou
        let current = keyboardPick.flatMap { id in tank.fish.first { $0.id == id && !$0.leaving } }
        switch k {
        case "⇥", "⇤":
            guard !list.isEmpty else { keyboardPick = nil; close(); tank.notice = (tr("✓ ninguém esperando"), tank.time); return true }
            let i = current.flatMap { c in list.firstIndex { $0 === c } }
            let next = i.map { (k == "⇥" ? $0 + 1 : $0 - 1 + list.count) % list.count } ?? (k == "⇥" ? 0 : list.count - 1)
            pick(list[next])
            return true
        case "⎋":
            guard keyboardPick != nil || hoverCard != nil else { return false }
            keyboardPick = nil
            close()
            return true
        default: break
        }
        guard let f = current else { return false }
        switch k {
        case "↩", "⌘↩":
            close(); keyboardPick = nil
            if !Whereabouts.go(f) { tank.notice = (tr("%@: não sei onde fica", f.label), tank.time) }
        case "⌘r": read?(f)
        case "⌘d":
            guard canReply(f) else { tank.notice = (f.label + ": " + tr("não sei responder essa sessão"), tank.time); return true }
            (hoverCard?.contentViewController as? FishCard)?.toggleDictation()
        case "a", "n":
            guard let p = permissions.request(ofFish: f.id) else { return false }
            close(); keyboardPick = nil
            decide(p.id, k == "a" ? "allow" : "deny")
        default: return false
        }
        return true
    }
}

/// The app's side of the cards: the voice, and the right-click menu's actions on a fish.
extension AppDelegate {
    // MARK: - voice reading

    var readQuestions: Bool { UserDefaults.standard.bool(forKey: "readQuestions") }
    @objc func toggleReadQuestions() { UserDefaults.standard.set(!readQuestions, forKey: "readQuestions") }

    /// If on (and neither muted nor in focus), reads the question aloud: "aquariozinho pergunta: …". It's called once
    /// the fish has finished calling (motif and knocks on the glass), so the voice doesn't cover them.
    func readQuestion(_ f: Fish, after delay: Double) {
        guard readQuestions, !synth.muted.load(ordering: .relaxed), !Attention.focus else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.4, delay)) { [weak self, weak f] in
            guard let f, f.state == .waiting, let q = f.asked else { return }
            Speaker.shared.speak(tr("%@ pergunta: %@", f.nickname ?? f.displayTitle ?? f.label, q))
            _ = self
        }
    }

    // MARK: - menu actions on a fish

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

    @objc func menuReply() {
        guard let f = menuFish, let t = ask(tr("Responder %@", f.nickname ?? f.label), "", tr("Enviar")), !t.isEmpty else { return }
        cards.sendReply(f, t)
    }
    @objc func menuStop() { if let f = menuFish { Providers.of(f.source)?.stop(f) } }
    @objc func menuNickname() {
        guard let f = menuFish, let t = ask(tr("Nome do peixe"), f.nickname ?? "", tr("Dar nome")) else { return }
        f.nickname = t
    }
    /// Each provider renames its own way (Claude: types /rename; Codex: writes to its index).
    @objc func menuRenameChat() {
        guard let f = menuFish, let provider = Providers.of(f.source),
              let t = ask(tr("Renomear a conversa"), f.displayTitle ?? "", tr("Renomear")),
              !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        provider.renameChat(f, t.trimmingCharacters(in: .whitespaces)) { [weak self] error in
            guard let self, let error else { return }
            self.tank.notice = (tr("não renomeei: ") + error, self.tank.time)
        }
    }
    @objc func menuRenamePane() {
        guard let f = menuFish, let t = ask(tr("Renomear o painel no Rex"), "", tr("Renomear")), !t.isEmpty else { return }
        Whereabouts.renamePane(f, t)
    }
    @objc func menuRenameRex() {
        guard let f = menuFish, let t = ask(tr("Renomear a sessão no Rex"), f.sub?.components(separatedBy: " › ").first ?? "", tr("Renomear")),
              !t.isEmpty else { return }
        Whereabouts.renameRex(f, t)
    }

    @objc func menuAllow(_ i: NSMenuItem) { if let id = i.representedObject as? Int { cards.decide(id, "allow") } }
    @objc func menuDeny(_ i: NSMenuItem) { if let id = i.representedObject as? Int { cards.decide(id, "deny") } }
}
