import AppKit

/// From when the summary looks.
enum SummaryRange: Equatable {
    /// Since you left the Mac (the journal's last time away) until now.
    case away(Date)
    /// Since midnight.
    case today
    /// Half an hour each side of a moment (a pearl's).
    case around(Date)

    var since: Date {
        switch self {
        case .away(let d): return d
        case .today: return Calendar.current.startOfDay(for: Date())
        case .around(let d): return d.addingTimeInterval(-1800)
        }
    }
    var until: Date {
        if case .around(let d) = self { return min(Date(), d.addingTimeInterval(1800)) }
        return Date()
    }
}

/// What the summary panel says: worked out from the journal (what happened in the range) and the tank (how things are
/// right now). In the order a person sitting back down needs it: who waits for them and for what, what broke, what got
/// done (by project), what is still running and how far along.
struct Digest {
    /// One line about a session (or a plugin's thing).
    struct Line {
        /// A live session: the line opens its card. Nil: it's gone from the tank (or it's a plugin's).
        var fish: Fish?
        var color: NSColor
        /// Who: its name, and where (project · branch).
        var who: String
        var place: String?
        /// What: the question, the task, the error; then, quieter, its own words about it.
        var what: String
        var note: String?
        /// On the right: since when, or how long it took.
        var when: String?
        /// Its todo list, done of total (running sessions).
        var progress: (done: Int, total: Int)?
        /// A plugin's thing has a symbol instead of a fish, and maybe a link.
        var symbol: String?
        var link: String?
    }

    /// A project's finished tasks.
    struct Project {
        let name: String
        let color: NSColor
        let fish: Fish?
        var tasks: [Line]
        var took: Double
        var last: Date
    }

    var waiting: [Line] = []
    var broke: [Line] = []
    /// Who had an error in the range and has moved on since.
    var recovered: [String] = []
    var done: [Project] = []
    /// Pull requests merged, deploys and checks that went through (the plugins').
    var shipped: [Line] = []
    var running: [Line] = []
    /// Everything else the tank noticed (in words).
    var notices: [String] = []
    /// Work time and steps of the finished tasks.
    var worked: Double = 0
    var steps = 0
    /// The fish it talks about, the most pressing first (they come forward while the panel is open).
    var fishIds: [String] = []

    var tasksDone: Int { done.reduce(0) { $0 + $1.tasks.count } }
    var quiet: Bool { waiting.isEmpty && broke.isEmpty && done.isEmpty && shipped.isEmpty && running.isEmpty && recovered.isEmpty }

    static func color(_ c: SIMD3<Float>) -> NSColor { NSColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1) }

    /// The first line of a text, cut to `n` characters.
    static func firstLine(_ s: String?, _ n: Int = 140) -> String? {
        guard let line = s?.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty })
        else { return nil }
        return line.count > n ? String(line.prefix(n - 1)) + "…" : line
    }

    /// What the session was last asked to do (the latest prompt in its history).
    static func task(of f: Fish) -> String? {
        firstLine(f.history.last(where: { $0.name == Fish.toldMark })?.said, 120)
    }

    /// A plugin's thing, as a symbol: what kind of thing it is when its source says so, otherwise how it is.
    static func symbol(_ p: Presence) -> String {
        let s = (p.source + " " + p.kind.id).lowercased()
        if s.contains("github") || s.contains("gitlab") || s.contains("pr") && p.label.contains("#") { return "arrow.triangle.pull" }
        if s.contains("deploy") || s.contains("vercel") || s.contains("netlify") || s.contains("fly") { return "shippingbox.fill" }
        if s.contains("ci") || s.contains("check") || s.contains("build") { return "checklist" }
        switch p.state {
        case .error: return "xmark.octagon"
        case .alert: return "exclamationmark.triangle.fill"
        case .waiting: return "hand.raised.fill"
        default: return "circle.hexagongrid.fill"
        }
    }

    static func place(_ project: String, _ branch: String?) -> String {
        guard let b = branch, !b.isEmpty, !["main", "master", "HEAD"].contains(b) else { return project }
        return project + "  ⎇ " + b
    }

    static func make(_ range: SummaryRange, journal: Journal, tank: Tank, permissions: Permissions) -> Digest {
        var d = Digest()
        let list = journal.between(range.since, range.until)
        let live = tank.fish.filter { !$0.decor && !$0.leaving && !$0.sings }
        func fish(_ id: String?) -> Fish? { id.flatMap { id in live.first { $0.id == id } } }
        func name(_ f: Fish) -> String { f.nickname ?? f.label }
        /// Its project and branch, and who launched it (a school's leader).
        func at(_ f: Fish) -> String {
            let p = place(f.label, f.branch)
            guard let l = tank.leader(of: f) else { return p }
            return p + "   ↳ " + (l.nickname ?? firstLine(l.displayTitle, 40) ?? task(of: l).map { firstLine($0, 30)! } ?? l.label)
        }
        func ago(_ seconds: Double) -> String { seconds < 60 ? tr("agora") : Journal.duration(seconds) }
        let clock = DateFormatter(); clock.timeStyle = .short; clock.dateStyle = .none; clock.locale = L10n.locale

        // ✋ who waits for you, and for what: right now, whatever the range (the longest waiting first)
        for f in live.sorted(by: { $0.since < $1.since }) where f.offer == nil {
            let request = permissions.request(ofFish: f.id)
            guard f.state == .waiting || request != nil else { continue }
            var what = tr("espera a sua resposta"), note = task(of: f).map { "› " + $0 }
            if let p = request {
                if let q = p.question { what = q.text }
                else if let q = p.questions.first { what = q.text + (p.questions.count > 1 ? "  " + tr("(+%d)", p.questions.count - 1) : "") }
                else { what = tr("quer usar %@", p.tool); note = firstLine(p.summary, 160) }
            } else if let q = firstLine(f.asked, 160) {
                what = q
            }
            d.waiting.append(Line(fish: f, color: color(f.color), who: name(f), place: at(f), what: what, note: note,
                                  when: ago(tank.time - f.since)))
        }
        for p in tank.scene.presences where !p.leaving && p.state == .waiting {
            d.waiting.append(Line(fish: nil, color: color(p.baseColor), who: p.label, place: p.source, what: p.detail ?? tr("espera você"),
                                  when: ago(tank.time - p.since), symbol: symbol(p), link: p.link))
        }

        // ✗ what's broken now (sessions, then the plugins' things), and who had an error and moved on
        for f in live where f.state == .error {
            d.broke.append(Line(fish: f, color: color(f.color), who: name(f), place: at(f),
                                what: task(of: f) ?? f.displayTitle ?? tr("parou com erro"), note: firstLine(f.lastReply),
                                when: ago(tank.time - f.since)))
        }
        for p in tank.scene.presences where !p.leaving && (p.state == .error || p.state == .alert) {
            d.broke.append(Line(fish: nil, color: color(p.baseColor), who: p.label, place: p.source,
                                what: p.detail ?? (p.state == .error ? tr("com erro") : tr("em alerta")), when: ago(tank.time - p.since),
                                symbol: symbol(p), link: p.link))
        }
        var seenRecovered = Set<String>()
        for h in list where h.kind == .error && h.presence == nil {
            if let f = fish(h.fishId), f.state == .error { continue }
            let n = h.name ?? h.label
            if seenRecovered.insert(n).inserted { d.recovered.append(n) }
        }

        // ✓ what got done, by project (the most recent first); the plugins' merges, deploys and checks apart
        var byProject: [String: Project] = [:]
        for h in list where h.kind == .done && h.presence == nil {
            let f = fish(h.fishId)
            let c = h.color.map { color(SIMD3($0[0], $0[1], $0[2])) } ?? f.map { color($0.color) } ?? NSColor(white: 0.75, alpha: 1)
            var right = clock.string(from: h.when)
            if let t = h.took, t >= 60 { right = Journal.duration(t) + "  ·  " + right }
            let line = Line(fish: f, color: c, who: h.name ?? h.label, place: h.branch.map { "⎇ " + $0 },
                            what: firstLine(h.task, 120) ?? h.title ?? tr("tarefa"), note: h.said, when: right)
            var p = byProject[h.label] ?? Project(name: h.label, color: c, fish: f, tasks: [], took: 0, last: h.when)
            p.tasks.insert(line, at: 0)
            p.took += h.took ?? 0
            p.last = max(p.last, h.when)
            byProject[h.label] = p
            d.worked += h.took ?? 0
            d.steps += h.steps ?? 0
        }
        d.done = byProject.values.sorted { $0.last > $1.last }
        for h in list.reversed() where h.kind == .merge || (h.kind == .done && h.presence != nil) {
            d.shipped.append(Line(fish: fish(h.fishId), color: h.color.map { color(SIMD3($0[0], $0[1], $0[2])) } ?? .systemPurple,
                                  who: h.label, place: nil, what: h.kind == .merge ? tr("PR mergeado") : (h.said ?? tr("pronto")),
                                  when: clock.string(from: h.when), symbol: shippedSymbol(h), link: h.link))
        }

        func shippedSymbol(_ h: Happening) -> String {
            if h.kind == .merge || (h.said ?? "").lowercased().contains("merg") { return "arrow.triangle.merge" }
            if let id = h.presence, let p = tank.scene.presences.first(where: { $0.id == id }) { return symbol(p) }
            return "checkmark.seal.fill"
        }
        // ▸ what's still running, and how far along (the longest working first)
        for f in live where f.state == .busy && f.isAgent {
            let working = f.workingSince.map { tank.time - $0 } ?? (tank.time - f.since)
            var note: String?
            if let d = f.doing, !d.isEmpty { note = "▸ " + d } else if let t = f.tool { note = "▸ " + t }
            d.running.append(Line(fish: f, color: color(f.color), who: name(f), place: at(f),
                                  what: task(of: f) ?? f.displayTitle ?? tr("trabalhando"), note: note, when: ago(working),
                                  progress: f.todos.map { ($0.done, $0.total) }))
        }
        d.running.sort { ($0.fish?.workingSince ?? 0) < ($1.fish?.workingSince ?? 0) }

        var seenNotice = Set<String>()
        for h in list.reversed() where h.kind == .event && h.presence == nil && seenNotice.insert(h.label).inserted { d.notices.append(h.label) }

        for l in d.waiting + d.broke + d.running { if let id = l.fish?.id, !d.fishIds.contains(id) { d.fishIds.append(id) } }
        for p in d.done { if let id = p.fish?.id, !d.fishIds.contains(id) { d.fishIds.append(id) } }
        return d
    }
}

extension Journal {
    /// A session's happening with all the summary needs to tell it: its name, what it was asked, its own words, how
    /// long it took.
    func record(_ kind: Happening.Kind, of f: Fish, tank: Tank, permission: Permissions.Request?) {
        var h = Happening(when: Date(), kind: kind, label: f.label, fishId: f.id)
        h.name = f.nickname
        h.title = f.displayTitle
        h.branch = f.branch.flatMap { ["main", "master", "HEAD", ""].contains($0) ? nil : $0 }
        h.color = [f.color.x, f.color.y, f.color.z]
        let told = f.history.last(where: { $0.name == Fish.toldMark })
        h.task = Digest.firstLine(told?.said, 200)
        switch kind {
        case .done:
            if let t = told { h.took = Date().timeIntervalSince(t.when) }
            h.steps = f.toolSinceStart
        case .waiting:
            h.said = Digest.firstLine(permission.map { $0.question?.text ?? ($0.tool + ": " + $0.summary) } ?? f.asked, 200)
        case .error:
            h.said = Digest.firstLine(f.lastReply, 200)
        default: break
        }
        // its last reply: its first line is what it says it did. It may already be here (it came with the event), or
        // arrive a moment later (read from the conversation file); not the reply of its previous task, if no new one came.
        let earlier = items.last(where: { $0.fishId == f.id && $0.kind == .done })?.said
        if kind == .done, let said = Digest.firstLine(f.lastReply, 200), said != earlier { h.said = said }
        add(h)
        guard kind == .done else { return }
        let before = f.lastReply
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak f] in
            guard let self, let f, f.lastReply != before, let said = Digest.firstLine(f.lastReply, 200), said != earlier else { return }
            self.amendLast(of: f.id, .done) { $0.said = said }
        }
    }

    /// A plugin's thing changed state: worth telling when it's done, broken, or waits for you.
    func record(_ p: Presence) {
        let kind: Happening.Kind
        switch p.state {
        case .done: kind = .done
        case .error, .alert: kind = .error
        case .waiting: kind = .waiting
        default: return
        }
        var h = Happening(when: Date(), kind: kind, label: p.label, fishId: nil)
        h.presence = p.id
        h.said = p.detail
        h.link = p.link
        h.color = [p.baseColor.x, p.baseColor.y, p.baseColor.z]
        add(h)
    }
}
