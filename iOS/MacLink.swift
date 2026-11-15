import Foundation
import Network
import Combine
import UIKit

/// A permission request waiting on the Mac (`GET /permissions`, Remote.swift).
struct PermissionRequest: Identifiable, Equatable {
    struct Question: Equatable {
        let text: String
        let multi: Bool
        let options: [(label: String, about: String)]
        static func == (a: Question, b: Question) -> Bool { a.text == b.text && a.options.map(\.label) == b.options.map(\.label) }

        init(_ d: [String: Any]) {
            text = d["text"] as? String ?? ""
            multi = d["multi"] as? Bool ?? false
            options = (d["options"] as? [[String: Any]] ?? []).map { ($0["label"] as? String ?? "", $0["about"] as? String ?? "") }
        }
    }

    let id: Int
    let source: String
    let entity: String
    let label: String
    let tool: String
    let summary: String
    /// A question with a menu, answered with one of its options (or free text).
    let question: Question?
    /// Several questions: a form.
    let questions: [Question]

    init?(_ d: [String: Any]) {
        guard let id = d["id"] as? Int else { return nil }
        self.id = id
        source = d["source"] as? String ?? ""
        entity = d["entity"] as? String ?? ""
        label = d["label"] as? String ?? ""
        tool = d["tool"] as? String ?? ""
        summary = d["summary"] as? String ?? ""
        question = (d["question"] as? [String: Any]).map(Question.init)
        questions = (d["questions"] as? [[String: Any]] ?? []).map(Question.init)
    }
}

/// The link to the paired Mac: one stream that stays open (`GET /stream`: the tank's state, the pending requests,
/// each event) and short requests for what the person does (answer, reply, stop). Every connection is TLS with the
/// pairing key (RemoteTLS); the sessions stay on the Mac, nothing runs here.
final class MacLink: ObservableObject {
    /// One for the app: the screen and the notifications' buttons (which may run with the app closed) share it.
    static let shared = MacLink()

    enum Status: Equatable {
        case unpaired, connecting, connected, failed(String)
    }

    @Published private(set) var pairing: Pairing?
    @Published private(set) var status: Status = .unpaired
    /// The fish as `/state` has them (for the card: title, what it's doing, what can be done with it).
    @Published private(set) var fish: [String: [String: Any]] = [:]
    @Published private(set) var permissions: [PermissionRequest] = []
    /// The presences as `/state` has them (for their card: label, state, detail, link, value).
    @Published private(set) var presences: [[String: Any]] = []
    /// The resident assistant's conversation (`GET /assistant`, then the stream): turns, thinking, what it asks.
    @Published private(set) var assistant: [String: Any] = [:]
    /// A short line for the person (a reply that didn't go, a decision that failed).
    @Published var notice: String?
    /// What happened while the app wasn't looking (`GET /journal`), when that was a while: shown once.
    @Published var away: [[String: Any]] = []
    /// What the summary card says it is: while you were away, or the last hours (the chest).
    @Published var awayTitle = ""
    /// A fish whose card should open (a notification was tapped).
    @Published var openFish: String?
    /// This phone's push token, sent to the Mac each time the stream opens (it can change).
    private var pushToken: String?
    /// When the app last looked at the aquarium (the stream open, in the front).
    private var lastSeen: Date? {
        get { UserDefaults.standard.object(forKey: "lastSeen") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastSeen") }
    }

    let mirror = TankMirror()
    /// The aquarium's sound here (iOS/Sound.swift): on while the app is in front.
    private(set) lazy var sound = AquariumSound(mirror: mirror)
    /// The theme this phone shows: "" follows the Mac's.
    @Published var theme = UserDefaults.standard.string(forKey: "theme") ?? "" {
        didSet {
            UserDefaults.standard.set(theme, forKey: "theme")
            mirror.themeOverride = theme.isEmpty ? nil : theme
        }
    }
    /// Something happened on the Mac (a `TankEvent`: state, permission, party).
    var onEvent: (([String: Any]) -> Void)?

    private var stream: NWConnection?
    private var buffer = Data()
    private var headersDone = false
    private var active = false
    /// A stream is being opened (the race in `open` takes a moment): don't start a second one.
    private var connecting = false
    private var retry: DispatchWorkItem?
    /// The endpoint that answered last: tried first next time.
    private var lastGood: NWEndpoint?
    /// The demo's Mac, while it's on: the stream and the requests go to it.
    private(set) var demo: DemoMac?

    init() {
        // in front: the stream open; behind: closed (iOS would freeze it anyway, and the Mac sends notifications
        // only while nobody is watching)
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in self?.pause() }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in self?.resume() }
        pairing = Pairing.load()
        // paired before notifications existed: the extension's key comes from the pairing already kept
        if let p = pairing, PushKey.load() == nil {
            let st = PushKey.keep(pairing: p.key)
            MacLink.log("push key kept: \(st) group: \(PushKey.group ?? "-")")
        }
        status = pairing == nil ? .unpaired : .connecting
        mirror.log = { MacLink.log($0) }
        ShaderSheet.failed = { m in DispatchQueue.main.async { MacLink.log(m) } }
        // a pack drawing that doesn't compile here is left out (the rest still draws): say which
        Renderer.packFishFailed = { k, e in MacLink.log("pack fish \(k.id) failed: \(e)") }
        Renderer.packSceneryFailed = { k, e in MacLink.log("pack scenery \(k.id) failed: \(e)") }
        Renderer.packFaunaFailed = { k, e in MacLink.log("pack creature \(k.id) failed: \(e)") }
        Renderer.packPresenceFailed = { k, e in MacLink.log("pack presence \(k.id) failed: \(e)") }
        Renderer.packBackgroundFailed = { k, e in MacLink.log("pack background \(k.id) failed: \(e)") }
        mirror.themeOverride = theme.isEmpty ? nil : theme
        mirror.packsFolder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("packs", isDirectory: true)
        mirror.fetchPacks = { [weak self] done in
            self?.request("GET", "/packs/files?sounds=1") { status, data in done(status == 200 ? data : nil) }
        }
    }

    /// The app's own log (Library/Caches/fishbots.log): what the mirror did with the packs, drawings that didn't
    /// compile here. Kept short.
    static func log(_ line: String) {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("fishbots.log")
        let text = "\(Date()) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url), (try? h.seekToEnd()) ?? 0 < 200_000 { h.write(Data(text.utf8)); try? h.close() }
        else { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }

    // MARK: - pairing

    /// A `fishbots://pair` link (the QR code, or the Camera app opening it). False: it isn't one.
    @discardableResult
    func pair(_ url: URL) -> Bool {
        guard let p = Pairing(url: url) else { return false }
        p.save()
        PushKey.keep(pairing: p.key)
        pairing = p
        Notifications.ask()
        lastGood = nil
        disconnect()
        mirror.clear()
        if active { connect() }
        return true
    }

    /// Demo mode (DemoMac.swift): a make-believe Mac answers instead of the network, until `forget`. Nothing is kept.
    func startDemo() {
        disconnect()
        mirror.clear()
        demo = DemoMac { [weak self] event, obj in self?.handle(event, obj) }
        pairing = DemoMac.pairing
        connecting = false                                 // a real Mac still being looked for is let go (see connect)
        if active { connect() }
    }

    func forget() {
        if demo != nil { leaveDemo(); return }
        Pairing.forget()
        PushKey.forget()
        disconnect()
        mirror.clear()
        pairing = nil
        fish = [:]
        permissions = []
        status = .unpaired
    }

    private func leaveDemo() {
        disconnect()
        demo = nil
        mirror.clear()
        pairing = Pairing.load()
        fish = [:]
        permissions = []
        presences = []
        assistant = [:]
        away = []
        status = pairing == nil ? .unpaired : .connecting
        if active, pairing != nil { connect() }
    }

    // MARK: - the stream

    /// The app came to the front: open the stream (and keep reopening it).
    func resume() {
        active = true
        sound.start()
        if stream == nil { connect() }
    }

    /// The app went to the back: iOS would cut it anyway.
    func pause() {
        if status == .connected { lastSeen = Date() }
        active = false
        sound.stop()
        disconnect()
    }

    func registerPush(_ token: String) {
        pushToken = token
        sendPushToken()
    }

    /// Development builds get their notifications from Apple's sandbox; TestFlight and the App Store from production.
    private func sendPushToken() {
        // through iCloud: once this phone is subscribed, the Mac writes its notes there (no token needed)
        if let id = pairing?.id, demo == nil {
            Cloud.subscribe(device: id) { [weak self] in
                self?.request("POST", "/push/register", ["cloud": true]) { status, _ in
                    if status != 200 { MacLink.log("cloud: the Mac didn't take it (\(status))") }
                }
            }
        }
        guard let pushToken, pairing != nil else { return }
        let env = Bundle.main.object(forInfoDictionaryKey: "FishbotsAPNs") as? String ?? "sandbox"
        request("POST", "/push/register", ["token": pushToken, "env": env]) { status, _ in
            if status != 200 { MacLink.log("push: the Mac didn't take the token (\(status))") }
        }
    }

    /// The journal since the app last looked, if that was more than 10 minutes ago (only what's worth telling:
    /// finished, broke, waited, merged).
    private func catchUp() {
        guard let since = lastSeen, Date().timeIntervalSince(since) > 600 else { lastSeen = Date(); return }
        let hours = min(72, Date().timeIntervalSince(since) / 3600 + 0.1)
        request("GET", "/journal?hours=" + String(format: "%.2f", hours)) { [weak self] status, data in
            guard let self, status == 200, let d = data.flatMap({ (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }) else { return }
            let iso = ISO8601DateFormatter()
            self.away = (d["journal"] as? [[String: Any]] ?? []).filter {
                guard let w = ($0["when"] as? String).flatMap(iso.date(from:)), w > since else { return false }
                return ["done", "error", "waiting", "merge"].contains($0["kind"] as? String ?? "")
            }
            self.awayTitle = tr("🌙 Enquanto você estava fora…")
            self.lastSeen = Date()
        }
    }

    /// The chest: what happened in the last hours, on the same card.
    func recent(hours: Double) {
        request("GET", "/journal?hours=\(hours)") { [weak self] status, data in
            guard let self, status == 200, let d = data.flatMap({ (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }) else { return }
            let items = (d["journal"] as? [[String: Any]] ?? []).filter { ["done", "error", "waiting", "merge"].contains($0["kind"] as? String ?? "") }
            if items.isEmpty { self.notice = tr("Nada nas últimas horas."); return }
            self.awayTitle = String(format: tr("🧰 Últimas %d horas"), Int(hours))
            self.away = items
        }
    }

    private func disconnect() {
        retry?.cancel()
        retry = nil
        demo?.stop()
        stream?.cancel()
        stream = nil
    }

    private func connect() {
        guard let pairing, active, !connecting, stream == nil else { return }
        if let demo { status = .connected; catchUp(); demo.start(); return }
        connecting = true
        status = .connecting
        open(pairing) { [weak self] c in
            guard let self else { return }
            guard self.demo == nil else { c?.cancel(); return }
            self.connecting = false
            guard let c else { self.lost(tr("não achei o Mac")); return }
            guard self.active, self.pairing == pairing else { c.cancel(); return }
            self.stream = c
            self.buffer = Data()
            self.headersDone = false
            c.stateUpdateHandler = { [weak self, weak c] s in
                switch s {
                case .failed, .cancelled: if let c, self?.stream === c { self?.lost(tr("a conexão caiu")) }
                default: break
                }
            }
            c.send(content: Data("GET /stream HTTP/1.1\r\nHost: fishbots\r\nAccept: text/event-stream\r\n\(Self.whoAmI(pairing))\r\n".utf8), completion: .contentProcessed { _ in })
            self.read(c)
        }
    }

    private func read(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, err in
            guard let self, self.stream === c else { return }
            if let data { self.take(data) }
            if done || err != nil { c.cancel(); self.lost(tr("a conexão caiu")) } else { self.read(c) }
        }
    }

    private func lost(_ why: String) {
        stream?.cancel()
        stream = nil
        guard active, pairing != nil else { return }
        status = .failed(why)
        let w = DispatchWorkItem { [weak self] in self?.connect() }
        retry = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: w)
    }

    /// Server-Sent Events: after the headers, blocks of `event:` and `data:` lines separated by a blank line.
    private func take(_ data: Data) {
        buffer.append(data)
        if !headersDone {
            guard let r = buffer.range(of: Data("\r\n\r\n".utf8)) else { return }
            let head = String(decoding: buffer[..<r.lowerBound], as: UTF8.self)
            guard head.hasPrefix("HTTP/1.1 200") else { lost(tr("o Mac recusou")); return }
            buffer.removeSubrange(..<r.upperBound)
            headersDone = true
            status = .connected
            catchUp()
            sendPushToken()
        }
        let sep = Data("\n\n".utf8)
        while let r = buffer.range(of: sep) {
            let block = String(decoding: buffer[..<r.lowerBound], as: UTF8.self)
            buffer.removeSubrange(..<r.upperBound)
            var event = "message", lines: [String] = []
            for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("event: ") { event = String(line.dropFirst(7)) }
                else if line.hasPrefix("data: ") { lines.append(String(line.dropFirst(6))) }
            }
            guard !lines.isEmpty, let obj = try? JSONSerialization.jsonObject(with: Data(lines.joined(separator: "\n").utf8)) as? [String: Any] else { continue }
            handle(event, obj)
        }
    }

    private func handle(_ event: String, _ obj: [String: Any]) {
        switch event {
        case "state":
            mirror.apply(obj)
            var f: [String: [String: Any]] = [:]
            for d in obj["fish"] as? [[String: Any]] ?? [] {
                if let s = d["source"] as? String, let e = d["entity"] as? String { f["\(s):\(e)"] = d }
            }
            fish = f
            presences = obj["presences"] as? [[String: Any]] ?? []
        case "permissions":
            permissions = (obj["permissions"] as? [[String: Any]] ?? []).compactMap(PermissionRequest.init)
        case "assistant":
            assistant = obj
        case "event":
            onEvent?(obj)
        default:
            break
        }
    }

    // MARK: - requests

    /// Allow or deny; `answer`: a question's option (or free text); `answers`: a form.
    func decide(_ p: PermissionRequest, decision: String? = nil, answer: String? = nil, answers: [String: String]? = nil) {
        var body: [String: Any] = [:]
        if let decision { body["decision"] = decision }
        if let answer { body["answer"] = answer }
        if let answers { body["answers"] = answers }
        permissions.removeAll { $0.id == p.id }          // the stream confirms it in a moment
        request("POST", "/permissions/\(p.id)", body) { [weak self] status, data in
            if status != 200 { self?.notice = Self.error(data) ?? tr("não consegui responder") }
        }
    }

    func reply(source: String, entity: String, text: String, done: @escaping (String?) -> Void) {
        request("POST", "/reply", ["source": source, "entity": entity, "text": text]) { status, data in
            done(status == 200 ? nil : Self.error(data) ?? tr("não enviei"))
        }
    }

    /// The session's last reply (markdown when the Mac has it), for reading on its card.
    func said(source: String, entity: String, done: @escaping (_ text: String?, _ markdown: Bool) -> Void) {
        var c = URLComponents()
        c.path = "/said"
        c.queryItems = [URLQueryItem(name: "source", value: source), URLQueryItem(name: "entity", value: entity)]
        request("GET", c.string ?? "/said") { status, data in
            let d = status == 200 ? data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } : nil
            done(d?["text"] as? String, d?["markdown"] as? Bool ?? false)
        }
    }

    /// Talks to the resident assistant: "ask" {text}, "decide" {allow, always}, "stop", "new", "seen".
    func assistant(_ what: String, _ body: [String: Any] = [:]) {
        request("POST", "/assistant/" + what, body) { [weak self] status, data in
            if status != 200 { self?.notice = Self.error(data) ?? tr("o assistente não respondeu") }
        }
    }

    /// What can be opened on the Mac (agents, recent folders), for the new session sheet.
    func spawnOptions(done: @escaping ([String: Any]?) -> Void) {
        request("GET", "/spawn/options") { status, data in
            done(status == 200 ? data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } : nil)
        }
    }

    /// Opens a session on the Mac (in a terminal there, like the eggs do); `done` gets what went wrong, or nil once
    /// its fish is born.
    func spawn(agent: String, cwd: String, task: String, done: @escaping (String?) -> Void) {
        request("POST", "/spawn", ["agent": agent, "cwd": cwd, "task": task]) { status, data in
            done(status == 200 ? nil : Self.error(data) ?? tr("não consegui abrir a sessão"))
        }
    }

    /// The Mac takes this phone's theme too; then the phone goes back to following it.
    func useThemeOnMac() {
        let id = theme
        guard !id.isEmpty else { return }
        request("POST", "/theme", ["id": id]) { [weak self] status, data in
            if status == 200 { self?.theme = "" } else { self?.notice = Self.error(data) ?? tr("o Mac não trocou de tema") }
        }
    }

    func stop(source: String, entity: String) {
        request("POST", "/stop", ["source": source, "entity": entity]) { [weak self] status, data in
            if status != 200 { self?.notice = Self.error(data) ?? tr("não consegui parar") }
        }
    }

    private static func error(_ data: Data?) -> String? {
        data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }?["error"] as? String
    }

    /// One request on a connection of its own (the Mac closes it after answering). `done` runs on the main queue;
    /// status 0: no answer.
    func request(_ method: String, _ path: String, _ body: [String: Any]? = nil, done: @escaping (Int, Data?) -> Void) {
        if let demo { demo.request(method, path, body, done: done); return }
        guard let pairing else { done(0, nil); return }
        open(pairing) { c in
            guard let c else { done(0, nil); return }
            let payload = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
            var out = Data("\(method) \(path) HTTP/1.1\r\nHost: fishbots\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\(Self.whoAmI(pairing))\r\n".utf8)
            out.append(payload)
            c.send(content: out, completion: .contentProcessed { _ in })
            var acc = Data()
            func read() {
                c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, finished, err in
                    if let data { acc.append(data) }
                    if finished || err != nil {
                        c.cancel()
                        guard let r = acc.range(of: Data("\r\n\r\n".utf8)) else { done(0, nil); return }
                        let first = String(decoding: acc[..<r.lowerBound], as: UTF8.self).split(separator: " ")
                        done(first.count > 1 ? Int(first[1]) ?? 0 : 0, Data(acc[r.upperBound...]))
                    } else { read() }
                }
            }
            read()
        }
    }

    /// The headers that say which paired device this is, and its name for the Mac's list (RemoteDevices).
    private static func whoAmI(_ p: Pairing) -> String {
        let name = UIDevice.current.name.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        return "X-Fishbots-Device: \(p.id)\r\nX-Fishbots-Name: \(name)\r\n"
    }

    // MARK: - finding the Mac

    /// A ready connection to the Mac. Every way to it is tried at once (Bonjour, the tailnet name, each address) and
    /// the first that's ready wins; the one that worked last starts a moment ahead, so at home it's still Bonjour.
    private func open(_ pairing: Pairing, done: @escaping (NWConnection?) -> Void) {
        var tries = pairing.endpoints
        if let lastGood { tries.removeAll { $0 == lastGood }; tries.insert(lastGood, at: 0) }
        var pending = tries.count
        var won = false
        var all: [NWConnection] = []
        func finish(_ c: NWConnection?, _ e: NWEndpoint?) {
            guard !won else { return }
            if let c, let e {
                won = true
                lastGood = e
                for o in all where o !== c { o.stateUpdateHandler = nil; o.cancel() }
                c.stateUpdateHandler = nil
                done(c)
            } else {
                pending -= 1
                if pending == 0 { won = true; done(nil) }
            }
        }
        for (i, e) in tries.enumerated() {
            let c = NWConnection(to: e, using: RemoteTLS.parameters(key: pairing.key, identity: pairing.id))
            all.append(c)
            var settled = false
            func settle(_ ok: Bool) {
                guard !settled else { return }
                settled = true
                if !ok { c.stateUpdateHandler = nil; c.cancel() }
                finish(ok ? c : nil, ok ? e : nil)
            }
            c.stateUpdateHandler = { s in
                switch s {
                case .ready: settle(true)
                case .failed, .waiting: settle(false)
                default: break
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (i == 0 || lastGood == nil ? 0 : 0.3)) {
                if !won { c.start(queue: .main) } else { settle(false) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { settle(false) }
        }
        if tries.isEmpty { done(nil) }
    }
}
