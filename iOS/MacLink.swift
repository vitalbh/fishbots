import Foundation
import Network
import Combine

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
    enum Status: Equatable {
        case unpaired, connecting, connected, failed(String)
    }

    @Published private(set) var pairing: Pairing?
    @Published private(set) var status: Status = .unpaired
    /// The fish as `/state` has them (for the card: title, what it's doing, what can be done with it).
    @Published private(set) var fish: [String: [String: Any]] = [:]
    @Published private(set) var permissions: [PermissionRequest] = []
    /// A short line for the person (a reply that didn't go, a decision that failed).
    @Published var notice: String?
    /// What happened while the app wasn't looking (`GET /journal`), when that was a while: shown once.
    @Published var away: [[String: Any]] = []
    /// When the app last looked at the aquarium (the stream open, in the front).
    private var lastSeen: Date? {
        get { UserDefaults.standard.object(forKey: "lastSeen") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastSeen") }
    }

    let mirror = TankMirror()
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
    private var retry: DispatchWorkItem?
    /// The endpoint that answered last: tried first next time.
    private var lastGood: NWEndpoint?

    init() {
        pairing = Pairing.load()
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
            self?.request("GET", "/packs/files") { status, data in done(status == 200 ? data : nil) }
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
        pairing = p
        lastGood = nil
        disconnect()
        mirror.clear()
        if active { connect() }
        return true
    }

    func forget() {
        Pairing.forget()
        disconnect()
        mirror.clear()
        pairing = nil
        fish = [:]
        permissions = []
        status = .unpaired
    }

    // MARK: - the stream

    /// The app came to the front: open the stream (and keep reopening it).
    func resume() {
        active = true
        if stream == nil { connect() }
    }

    /// The app went to the back: iOS would cut it anyway.
    func pause() {
        if status == .connected { lastSeen = Date() }
        active = false
        disconnect()
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
            self.lastSeen = Date()
        }
    }

    private func disconnect() {
        retry?.cancel()
        retry = nil
        stream?.cancel()
        stream = nil
    }

    private func connect() {
        guard let pairing, active else { return }
        status = .connecting
        open(pairing) { [weak self] c in
            guard let self else { return }
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
            c.send(content: Data("GET /stream HTTP/1.1\r\nHost: fishbots\r\nAccept: text/event-stream\r\n\r\n".utf8), completion: .contentProcessed { _ in })
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
        case "permissions":
            permissions = (obj["permissions"] as? [[String: Any]] ?? []).compactMap(PermissionRequest.init)
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
        guard let pairing else { done(0, nil); return }
        open(pairing) { c in
            guard let c else { done(0, nil); return }
            let payload = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) } ?? Data()
            var out = Data("\(method) \(path) HTTP/1.1\r\nHost: fishbots\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
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
            let c = NWConnection(to: e, using: RemoteTLS.parameters(key: pairing.key))
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
