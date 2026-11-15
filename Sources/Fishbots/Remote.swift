import Foundation
import Network
import CryptoKit
import Security

/// The aquarium seen from another device, like the iPhone app (docs/extensions.md, 13). The sessions keep running
/// on this Mac; the device watches the tank, answers permission requests and replies to sessions, and the reply is
/// typed into the session's terminal here, the same way the card does it. Nothing is started on the device.
///
/// Off unless Preferences turns it on. Then a second listener opens on every interface (port + 1: 7778), announced
/// over Bonjour as `_fishbots._tcp`, speaking HTTP inside TLS with pre-shared keys: each paired device has a key of
/// its own (RemoteDevices.swift; the QR code in Preferences carries the next one), anyone else fails the handshake.
/// No certificates, nothing in the clear. Keys are kept across launches; revoking a device takes its key out.
///
/// Only a few routes answer there (`routes`); everything else is the local server's business.
final class Remote: EventSink {
    let id = "remote"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "remoteAccess") }
    static let routes = ["GET /state", "GET /stream", "GET /permissions", "POST /permissions/<id>", "GET /said", "POST /reply",
                         "POST /stop", "POST /theme", "POST /push/register", "GET /spawn/options", "POST /spawn",
                         "GET /assistant", "POST /assistant/ask", "POST /assistant/decide", "POST /assistant/stop",
                         "POST /assistant/new", "POST /assistant/seen", "GET /packs", "GET /packs/files", "GET /journal"]

    let port: UInt16
    private let tank: Tank
    private let permissions: Permissions
    /// The local server's answer, for the routes that are the same here (/state, /packs, /journal).
    var local: ((_ method: String, _ path: String, _ headers: [String: String], _ body: Data) -> (Int, Data))?
    /// What the card does: send a reply into the session, decide a permission request, interrupt the agent.
    var reply: ((Fish, String) -> Void)?
    var decide: ((Int, String) -> Void)?
    var can: ((Capability, Fish) -> Bool)?
    /// Changes the Mac's theme, as its menu does.
    var useTheme: ((String) -> Void)?
    /// The resident assistant: the device reads the conversation (and gets it on the stream as it changes) and talks
    /// to it, as its card on the Mac does.
    weak var assistant: Assistant?

    /// Starting a session from the device (it runs here, in a terminal, like one from the eggs): what can be opened
    /// and where, and the opening itself (`done` gets what went wrong, or nil once its fish is born).
    var spawnOptions: (() -> [String: Any])?
    var spawn: ((_ agent: String, _ cwd: String, _ task: String, _ done: @escaping (String?) -> Void) -> Void)?

    /// Keeps a phone's push token (Push.swift).
    var registerPush: ((Push.Device) -> Void)?
    var registerCloud: ((String) -> Void)?

    /// A device has the stream open (the app in front): it sees everything already, no notifications.
    var watching: Bool { streams.contains { $0.isOpen } }

    /// The paired devices and their keys.
    let devices: RemoteDevices
    private var server: Server?
    /// Listeners replaced when the keys changed, kept a moment for the requests they were still answering.
    private var retired: [Server] = []
    private var streams: [Server.Stream] = []
    /// Which device opened each stream (to close them when it's revoked).
    private var streamDevice: [ObjectIdentifier: String] = [:]
    private var timer: Timer?
    private var sentState = Data()
    private var sentPermissions = Data()
    private var sentAssistant = Data()
    private var lastPing = Date()
    private var observer: NSObjectProtocol?

    init(tank: Tank, permissions: Permissions, port: UInt16) {
        self.tank = tank
        self.permissions = permissions
        self.port = port
        devices = RemoteDevices(port: port)
        devices.keysChanged = { [weak self] in self?.reopen() }
    }

    /// Follows the Preferences switch from now on.
    func start() {
        sync()
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sync()
        }
    }

    private func sync() {
        if Self.enabled, server == nil { open() }
        if !Self.enabled, server != nil { close() }
    }

    private func open() {
        do {
            let params = RemoteTLS.parameters(keys: devices.keys)
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener.service = NWListener.Service(name: Host.current().localizedName, type: RemoteTLS.serviceType)
            let s = try Server(listener: listener, local: false) { [weak self] method, path, headers, body in
                self?.respond(method, path, headers, body) ?? (404, Data())
            }
            s.admit = { RemoteTLS.admits($0) }
            s.stream = { [weak self] method, path, headers in
                guard let self, method == "GET", path.split(separator: "?").first == "/stream" else { return nil }
                let device = self.heard(headers)
                return { self.add($0, device: device) }
            }
            // a new session answers once its fish is born, or with what went wrong: later
            s.deferred.append { [weak self] method, path, _, body, reply in
                guard let self, method == "POST", path.split(separator: "?").first == "/spawn" else { return false }
                let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
                guard let agent = m["agent"] as? String, let cwd = m["cwd"] as? String, let spawn = self.spawn else {
                    reply(400, Self.error(#"send {"agent", "cwd", "task"}"#)); return true
                }
                spawn(agent, cwd, (m["task"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) { failure in
                    reply(failure == nil ? 200 : 409, failure.map { Self.error($0) } ?? Data(#"{"ok":true}"#.utf8))
                }
                return true
            }
            server = s
            Task { await refreshTailscale() }
        } catch {
            FileHandle.standardError.write("fishbots: couldn't open the remote port \(port): \(error)\n".data(using: .utf8)!)
        }
    }

    private func close() {
        for s in streams { s.end() }
        streams = []
        server?.stop()
        server = nil
        timer?.invalidate()
        timer = nil
    }

    /// Every device out: each has to scan the code again.
    func forgetDevices() { devices.forgetAll() }

    /// One device out (its key leaves the listener; its streams close).
    func revoke(_ id: String) { devices.revoke(id) }

    /// The keys changed: a listener with the new set takes the port. The old one stays a moment for the answers it
    /// still owes; streams of devices no longer paired close.
    private func reopen() {
        guard let old = server else { return }
        old.stop()
        retired.append(old)
        server = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, Self.enabled, self.server == nil else { return }
            self.open()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in self?.retired.removeAll { $0 === old } }
        for s in streams where devices.key(of: streamDevice[ObjectIdentifier(s)] ?? "") == nil { s.end() }
    }

    /// The device a request comes from (its header), marked as seen; nil: it didn't say.
    @discardableResult
    private func heard(_ headers: [String: String]) -> String? {
        guard let id = headers["x-fishbots-device"], devices.key(of: id) != nil else { return nil }
        devices.heard(from: id, name: headers["x-fishbots-name"])
        return id
    }

    /// What the QR code carries: where to find this Mac (Bonjour name, and its addresses for when Bonjour can't
    /// reach, like over Tailscale), and the next device's identity and key.
    var pairingURL: String {
        var c = URLComponents()
        c.scheme = "fishbots"
        c.host = "pair"
        c.queryItems = [URLQueryItem(name: "v", value: "1"),
                        URLQueryItem(name: "name", value: Host.current().localizedName ?? "Mac"),
                        URLQueryItem(name: "port", value: String(port)),
                        URLQueryItem(name: "hosts", value: Self.addresses().joined(separator: ",")),
                        URLQueryItem(name: "ts", value: tailscaleName ?? ""),
                        URLQueryItem(name: "id", value: devices.pending.id),
                        URLQueryItem(name: "key", value: devices.pending.key.base64EncodedString()
                            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                            .replacingOccurrences(of: "=", with: ""))]
        return c.string ?? ""
    }

    var pairingJSON: Data {
        Self.json(["enabled": Self.enabled, "listening": server != nil, "port": Int(port), "service": RemoteTLS.serviceType,
                   "url": Self.enabled ? pairingURL : "", "watching": streams.count,
                   "devices": devices.paired.map { ["id": $0.id, "name": $0.name, "seen": $0.seen.map { ISO8601DateFormatter().string(from: $0) } ?? ""] },
                   "tailscale": Self.tailscaleAddress() ?? "", "tailscaleName": tailscaleName ?? ""])
    }

    /// This Mac's name on the tailnet (MagicDNS, e.g. "mac.tail1234.ts.net"), found from its Tailscale address.
    /// It goes in the QR code: it stays the same when addresses change, and works from outside the house.
    private(set) var tailscaleName: String?

    /// The Mac's address in Tailscale's range (100.64.0.0/10), when the Tailscale app is running here. Tailscale
    /// built into another app (its own node inside that process) makes no address on the Mac and can't reach us.
    static func tailscaleAddress() -> String? {
        addresses().first { a in
            let p = a.split(separator: ".").compactMap { UInt8($0) }
            return p.count == 4 && p[0] == 100 && p[1] & 0xc0 == 64
        }
    }

    /// Looks the name up again (a reverse lookup that Tailscale's DNS answers), off the main thread.
    @discardableResult
    func refreshTailscale() async -> String? {
        guard let ip = Self.tailscaleAddress() else { tailscaleName = nil; return nil }
        let name = await Task.detached { () -> String? in
            var sa = sockaddr_in()
            sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            sa.sin_family = sa_family_t(AF_INET)
            guard inet_pton(AF_INET, ip, &sa.sin_addr) == 1 else { return nil }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let r = withUnsafePointer(to: &sa) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                }
            }
            guard r == 0 else { return nil }
            let n = String(cString: host).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return n.hasSuffix(".ts.net") ? n : nil
        }.value
        tailscaleName = name
        return name
    }

    /// The Mac's IPv4 addresses, other than loopback.
    static func addresses() -> [String] {
        var out: [String] = []
        var ifs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifs) == 0, let first = ifs else { return [] }
        defer { freeifaddrs(ifs) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let i = p.pointee
            guard let a = i.ifa_addr, a.pointee.sa_family == UInt8(AF_INET), (i.ifa_flags & UInt32(IFF_UP)) != 0,
                  (i.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let s = String(cString: host)
                if !s.hasPrefix("169.254."), !out.contains(s) { out.append(s) }
            }
        }
        return out
    }

    // MARK: - routes

    private func respond(_ method: String, _ path: String, _ headers: [String: String], _ body: Data) -> (Int, Data) {
        let route = path.split(separator: "?").first.map(String.init) ?? path
        let device = heard(headers)
        switch (method, route) {
        case ("GET", "/"):
            return (200, Self.json(["fishbots": "ok", "remote": true, "name": Host.current().localizedName ?? "Mac", "routes": Self.routes]))
        case ("GET", "/state"), ("GET", "/packs"), ("GET", "/packs/files"), ("GET", "/journal"):
            return local?(method, path, [:], Data()) ?? (500, Data())
        case ("GET", "/permissions"):
            return (200, permissionsJSON())
        case ("POST", let r) where r.hasPrefix("/permissions/"):
            guard let id = Int(r.dropFirst("/permissions/".count)), permissions.request(id: id) != nil else {
                return (404, Self.error("no such request (already answered?)"))
            }
            let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            if let d = m["decision"] as? String, ["allow", "deny"].contains(d) { decide?(id, d) }
            else if let a = m["answer"] as? String { decide?(id, "answer:" + a) }
            else if let a = m["answers"] as? [String: String], let d = try? JSONSerialization.data(withJSONObject: a) {
                decide?(id, "answers:" + String(decoding: d, as: UTF8.self))
            } else { return (400, Self.error(#"send {"decision": "allow"|"deny"}, {"answer": "…"} or {"answers": {"question": "answer"}}"#)) }
            // still there: the decision didn't fit the request (an answer to one that isn't a question)
            if permissions.request(id: id) != nil { return (400, Self.error("that request doesn't take this answer")) }
            push()
            return (200, Data(#"{"ok":true}"#.utf8))
        case ("GET", "/assistant"):
            return (200, assistantJSON())
        case ("POST", let r) where r.hasPrefix("/assistant/"):
            guard let a = assistant else { return (404, Self.error("no assistant")) }
            let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            switch r {
            case "/assistant/ask":
                guard let t = (m["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return (400, Self.error(#"send {"text"}"#)) }
                guard Assistant.on, a.brain != nil else { return (409, Self.error("the assistant is off (Preferences → Assistant)")) }
                a.ask(t)
            case "/assistant/decide": a.decide(allow: m["allow"] as? Bool == true, always: m["always"] as? String)
            case "/assistant/stop": a.stop()
            case "/assistant/new": a.newConversation()
            case "/assistant/seen": a.seen()
            default: return (404, Self.error("unknown route"))
            }
            push()
            return (200, Data(#"{"ok":true}"#.utf8))
        case ("GET", "/spawn/options"):
            return (200, Self.json(spawnOptions?() ?? [:]))
        case ("POST", "/push/register"):
            // the phone's APNs token: {"token": "<hex>", "env": "sandbox"|"production"}
            let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            // or {"cloud": true}: this phone is subscribed to its notes in iCloud (CloudNotes.swift)
            if m["cloud"] as? Bool == true {
                registerCloud?(device ?? RemoteTLS.pskIdentity)
                return (200, Data(#"{"ok":true}"#.utf8))
            }
            guard let t = m["token"] as? String, t.count >= 32, t.allSatisfy(\.isHexDigit) else { return (400, Self.error("send {\"token\": \"…\", \"env\": \"sandbox\"}")) }
            registerPush?(Push.Device(token: t.lowercased(), env: m["env"] as? String == "production" ? "production" : "sandbox", device: device))
            return (200, Data(#"{"ok":true}"#.utf8))
        case ("POST", "/theme"):
            // the device chose a theme for the Mac too: {"id": "…"}, one the Mac has (built in or from a pack)
            let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            guard let id = m["id"] as? String, Themes.all.contains(where: { $0.id == id }) else { return (404, Self.error("no such theme")) }
            useTheme?(id)
            push()
            return (200, Data(#"{"ok":true}"#.utf8))
        case ("GET", "/said"):
            // the session's last reply, to read on the device: ?source=…&entity=… (not in /state: it can be long)
            let q = URLComponents(string: path)?.queryItems ?? []
            guard let source = q.first(where: { $0.name == "source" })?.value, let entity = q.first(where: { $0.name == "entity" })?.value,
                  let f = tank.fish(source: source, entity: entity) else { return (404, Self.error("no such fish: send ?source=…&entity=…")) }
            var d: [String: Any] = [:]
            if let t = f.lastReplyMarkdown ?? f.lastReply { d["text"] = String(t.suffix(20_000)); d["markdown"] = f.lastReplyMarkdown != nil }
            if let a = f.asked { d["asked"] = a }
            return (200, Self.json(d))
        case ("POST", "/reply"), ("POST", "/stop"):
            let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            guard let source = m["source"] as? String, let entity = m["entity"] as? String,
                  let f = tank.fish(source: source, entity: entity) else { return (404, Self.error("no such fish: send source and entity, as /state has them")) }
            if route == "/stop" {
                guard can?(.stop, f) == true, let p = Providers.of(f.source) else { return (409, Self.error("this session can't be interrupted from the aquarium")) }
                p.stop(f)
                return (200, Data(#"{"ok":true}"#.utf8))
            }
            guard let text = (m["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                return (400, Self.error(#"send {"source", "entity", "text"}"#))
            }
            // a question with a menu waiting on this fish takes the reply as its answer, like on the card
            if let p = permissions.request(ofFish: f.id), p.question != nil {
                decide?(p.id, "answer:" + text)
                push()
                return (200, Data(#"{"ok":true,"answered":"question"}"#.utf8))
            }
            guard can?(.reply, f) == true else { return (409, Self.error("this session can't take a reply from the aquarium")) }
            reply?(f, text)
            return (200, Data(#"{"ok":true}"#.utf8))
        default:
            return (404, Self.error("unknown route"))
        }
    }

    /// The assistant's conversation (its last turns), and what it's asking to use, if anything.
    private func assistantJSON() -> Data {
        guard let a = assistant else { return Self.json(["on": false]) }
        var d: [String: Any] = ["on": Assistant.on, "ready": a.hasBrain == true && a.brain != nil, "thinking": a.thinking,
                                "model": a.answeringModel ?? "", "brain": a.brain?.name ?? ""]
        d["turns"] = a.turns.suffix(20).map { t -> [String: Any] in
            ["q": t.question, "a": String(t.answer.suffix(20_000)), "doing": t.doing ?? "", "failed": t.failed, "mentions": t.mentions]
        }
        if let r = a.request {
            d["request"] = ["tool": Assistant.toolName(r.tool), "summary": r.summary,
                            "always": Assistant.ruleKeys(r).map { ["key": $0, "label": Assistant.ruleName($0)] }]
        }
        return Self.json(d)
    }

    private func permissionsJSON() -> Data {
        let iso = ISO8601DateFormatter()
        func question(_ q: Permissions.Question) -> [String: Any] {
            ["text": q.text, "multi": q.multi, "options": q.options.map { ["label": $0.label, "about": $0.about] }]
        }
        let list: [[String: Any]] = permissions.pending.map { p in
            var d: [String: Any] = ["id": p.id, "source": p.source, "entity": p.session, "tool": p.tool, "summary": p.summary,
                                    "since": iso.string(from: p.since), "label": tank.fish(source: p.source, entity: p.session)?.label ?? ""]
            if let q = p.question { d["question"] = question(q) }
            if p.question == nil, !p.questions.isEmpty { d["questions"] = p.questions.map(question) }
            return d
        }
        return Self.json(["permissions": list])
    }

    // MARK: - the stream

    /// A device listening: it gets the whole state right away, then each change.
    private func add(_ s: Server.Stream, device: String?) {
        streams.append(s)
        streamDevice[ObjectIdentifier(s)] = device ?? RemoteTLS.pskIdentity
        s.closed = { [weak self, weak s] in
            guard let self, let s else { return }
            self.streams.removeAll { $0 === s }
            self.streamDevice[ObjectIdentifier(s)] = nil
        }
        // everyone catches up first (the new one with them); if nothing changed, the new one still needs it all
        let before = (sentState, sentPermissions, sentAssistant)
        push()
        if sentState == before.0 { s.send("state", sentState) }
        if sentPermissions == before.1 { s.send("permissions", sentPermissions) }
        if sentAssistant == before.2 { s.send("assistant", sentAssistant) }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.push() }
        }
    }

    /// Sends what changed since the last look (the state and the pending requests), to everyone listening.
    private func push() {
        streams.removeAll { !$0.isOpen }
        guard !streams.isEmpty else { timer?.invalidate(); timer = nil; sentState = Data(); sentPermissions = Data(); sentAssistant = Data(); return }
        let state = compact(local?("GET", "/state", [:], Data()).1 ?? Data())
        if state != sentState { sentState = state; for s in streams { s.send("state", state) } }
        let perms = permissionsJSON()
        if perms != sentPermissions { sentPermissions = perms; for s in streams { s.send("permissions", perms) } }
        let said = assistantJSON()
        if said != sentAssistant { sentAssistant = said; for s in streams { s.send("assistant", said) } }
        if Date().timeIntervalSince(lastPing) > 15 { lastPing = Date(); for s in streams { s.ping() } }
    }

    /// What happens in the tank, as it happens (EventSink): state changes, done, permission requests.
    func send(_ e: TankEvent) {
        guard !streams.isEmpty else { return }
        let d = Self.json(e.json)
        for s in streams { s.send("event", d) }
    }

    /// One line of JSON, keys sorted (so equal states compare equal, and an SSE `data:` takes it whole).
    private func compact(_ d: Data) -> Data {
        guard let o = try? JSONSerialization.jsonObject(with: d) else { return d }
        return (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? d
    }

    private static func json(_ o: Any) -> Data { (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data() }
    private static func error(_ text: String) -> Data { json(["error": text]) }
}
