import Foundation
import Network
import CryptoKit
import Security

/// The aquarium seen from another device, like the iPhone app (docs/extensions.md, 13). The sessions keep running
/// on this Mac; the device watches the tank, answers permission requests and replies to sessions, and the reply is
/// typed into the session's terminal here, the same way the card does it. Nothing is started on the device.
///
/// Off unless Preferences turns it on. Then a second listener opens on every interface (port + 1: 7778), announced
/// over Bonjour as `_fishbots._tcp`, speaking HTTP inside TLS with a pre-shared key: a device holding the pairing
/// key (the QR code in Preferences) gets in, anyone else fails the handshake. No certificates, nothing in the clear.
/// The key is kept across launches so a paired phone stays paired; "Forget devices" makes a new one.
///
/// Only a few routes answer there (`routes`); everything else is the local server's business.
final class Remote: EventSink {
    let id = "remote"
    static let serviceType = "_fishbots._tcp"
    static let pskIdentity = "fishbots"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "remoteAccess") }
    static let routes = ["GET /state", "GET /stream", "GET /permissions", "POST /permissions/<id>", "POST /reply",
                         "POST /stop", "GET /packs", "GET /packs/files", "GET /journal"]

    let port: UInt16
    private let tank: Tank
    private let permissions: Permissions
    /// The local server's answer, for the routes that are the same here (/state, /packs, /journal).
    var local: ((_ method: String, _ path: String, _ headers: [String: String], _ body: Data) -> (Int, Data))?
    /// What the card does: send a reply into the session, decide a permission request, interrupt the agent.
    var reply: ((Fish, String) -> Void)?
    var decide: ((Int, String) -> Void)?
    var can: ((Capability, Fish) -> Bool)?

    private var server: Server?
    private var streams: [Server.Stream] = []
    private var timer: Timer?
    private var sentState = Data()
    private var sentPermissions = Data()
    private var lastPing = Date()
    private var observer: NSObjectProtocol?

    init(tank: Tank, permissions: Permissions, port: UInt16) {
        self.tank = tank
        self.permissions = permissions
        self.port = port
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
            let params = Self.parameters(key: key())
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
            listener.service = NWListener.Service(name: Host.current().localizedName, type: Self.serviceType)
            let s = try Server(listener: listener, local: false) { [weak self] method, path, headers, body in
                self?.respond(method, path, headers, body) ?? (404, Data())
            }
            s.admit = { Self.admits($0) }
            s.stream = { [weak self] method, path in
                guard let self, method == "GET", path.split(separator: "?").first == "/stream" else { return nil }
                return { self.add($0) }
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

    /// A new pairing key: every paired device has to scan the code again.
    func forgetDevices() {
        try? FileManager.default.removeItem(at: Self.keyFile(port: port))
        if server != nil { close(); open() }
    }

    // MARK: - the transport

    /// TLS 1.2 with a pre-shared key (the same on both sides: the iPhone app builds its connection with this). The key
    /// proves who's who; ECDHE makes a fresh key for each connection, so a key that leaks one day doesn't open
    /// traffic someone recorded before (forward secrecy).
    static func parameters(key: Data) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let psk = Data(HMAC<SHA256>.authenticationCode(for: Data("fishbots-psk-v1".utf8), using: SymmetricKey(data: key)))
        let sec = tls.securityProtocolOptions
        sec_protocol_options_add_pre_shared_key(sec, psk.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
                                                Data(pskIdentity.utf8).withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData)
        sec_protocol_options_append_tls_ciphersuite(sec, tls_ciphersuite_t(rawValue: suite)!)
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10
        let p = NWParameters(tls: tls, tcp: tcp)
        p.includePeerToPeer = true
        return p
    }

    /// The suite `parameters` asks for. Listing it doesn't stop a server from taking a client's plain-PSK offer,
    /// so `admits` checks what was agreed.
    static let suite = UInt16(TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256)

    /// A connection stays if it agreed on the suite with forward secrecy and comes from a private network (the home
    /// network, Tailscale, link-local): an address on the internet is refused even with the key, so a forwarded port
    /// or a global IPv6 address doesn't put the aquarium on the internet.
    static func admits(_ c: NWConnection) -> Bool {
        guard let m = c.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata,
              sec_protocol_metadata_get_negotiated_tls_ciphersuite(m.securityProtocolMetadata).rawValue == suite else { return false }
        guard case .hostPort(let host, _) = c.endpoint else { return false }
        return isPrivate(host)
    }

    static func isPrivate(_ host: NWEndpoint.Host) -> Bool {
        switch host {
        case .ipv4(let a):
            return isPrivate(v4: [UInt8](a.rawValue))
        case .ipv6(let a):
            let b = [UInt8](a.rawValue)
            guard b.count == 16 else { return false }
            if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff { return isPrivate(v4: Array(b[12...])) }   // ::ffff:a.b.c.d
            if b[0..<15].allSatisfy({ $0 == 0 }), b[15] == 1 { return true }          // ::1
            if b[0] == 0xfe, b[1] & 0xc0 == 0x80 { return true }                      // fe80::/10, link-local
            return b[0] & 0xfe == 0xfc                                                // fc00::/7, unique local (Tailscale's fd7a:…)
        default:
            return false
        }
    }

    private static func isPrivate(v4 b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        return b[0] == 127 || b[0] == 10 || (b[0] == 172 && b[1] & 0xf0 == 16) || (b[0] == 192 && b[1] == 168)
            || (b[0] == 169 && b[1] == 254) || (b[0] == 100 && b[1] & 0xc0 == 64)    // 100.64.0.0/10: Tailscale
    }

    static func keyFile(port: UInt16) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fishbots/" + (port == 7778 ? "remote.key" : "remote-\(port).key"))
    }

    /// The pairing key, made the first time (32 random bytes, 0600 next to fish.json).
    func key() -> Data {
        let url = Self.keyFile(port: port)
        if let hex = try? String(contentsOf: url, encoding: .utf8), let d = Data(hex: hex.trimmingCharacters(in: .whitespacesAndNewlines)), d.count == 32 {
            return d
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { fatalError("fishbots: no random bytes for the pairing key") }
        let d = Data(bytes)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ControlTokens.writePrivately(Data((d.map { String(format: "%02x", $0) }.joined() + "\n").utf8), to: url)
        } catch {
            FileHandle.standardError.write("fishbots: couldn't write \(url.path): \(error)\n".data(using: .utf8)!)
        }
        return d
    }

    /// What the QR code carries: where to find this Mac (Bonjour name, and its addresses for when Bonjour can't
    /// reach, like over Tailscale) and the key.
    var pairingURL: String {
        var c = URLComponents()
        c.scheme = "fishbots"
        c.host = "pair"
        c.queryItems = [URLQueryItem(name: "v", value: "1"),
                        URLQueryItem(name: "name", value: Host.current().localizedName ?? "Mac"),
                        URLQueryItem(name: "port", value: String(port)),
                        URLQueryItem(name: "hosts", value: Self.addresses().joined(separator: ",")),
                        URLQueryItem(name: "ts", value: tailscaleName ?? ""),
                        URLQueryItem(name: "key", value: key().base64EncodedString()
                            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                            .replacingOccurrences(of: "=", with: ""))]
        return c.string ?? ""
    }

    var pairingJSON: Data {
        Self.json(["enabled": Self.enabled, "listening": server != nil, "port": Int(port), "service": Self.serviceType,
                   "url": Self.enabled ? pairingURL : "", "devices": streams.count,
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
    private func add(_ s: Server.Stream) {
        streams.append(s)
        s.closed = { [weak self, weak s] in self?.streams.removeAll { $0 === s } }
        // everyone catches up first (the new one with them); if nothing changed, the new one still needs it all
        let before = (sentState, sentPermissions)
        push()
        if sentState == before.0 { s.send("state", sentState) }
        if sentPermissions == before.1 { s.send("permissions", sentPermissions) }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.push() }
        }
    }

    /// Sends what changed since the last look (the state and the pending requests), to everyone listening.
    private func push() {
        streams.removeAll { !$0.isOpen }
        guard !streams.isEmpty else { timer?.invalidate(); timer = nil; sentState = Data(); sentPermissions = Data(); return }
        let state = compact(local?("GET", "/state", [:], Data()).1 ?? Data())
        if state != sentState { sentState = state; for s in streams { s.send("state", state) } }
        let perms = permissionsJSON()
        if perms != sentPermissions { sentPermissions = perms; for s in streams { s.send("permissions", perms) } }
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

private extension Data {
    init?(hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var out = Data(capacity: hex.count / 2)
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            guard let b = UInt8(hex[i..<j], radix: 16) else { return nil }
            out.append(b)
            i = j
        }
        self = out
    }
}
