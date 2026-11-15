import CryptoKit
import Foundation

/// Notifications on the paired iPhone when the app there isn't open (docs/extensions.md, 13): a session asks
/// permission, stops and waits for you, or breaks. An output (EventSink) like the webhooks.
///
/// Two ways, neither with a server of ours in between: through the person's iCloud (CloudNotes.swift: a note the
/// phone is subscribed to, the default, no setup), or straight to Apple's push service (APNs, HTTP/2 with a token
/// signed by a developer account's .p8 key, set in Preferences: for whoever builds the phone app with their own
/// account). A phone with a push token gets them the second way; the others the first. What a notification says goes sealed (PushSeal) with a
/// key derived from the pairing: Apple carries it without reading it, and the phone's notification extension opens it.
/// Each session's newest notification replaces its older one (collapse id).
///
/// `FISHBOTS_PUSH_DUMP=<folder>`: writes each payload there instead of sending it, in the shape
/// `xcrun simctl push booted <file>` takes, to try them in the simulator without an account.
final class Push: EventSink {
    let id = "push"
    private let tank: Tank
    private let permissions: Permissions
    private let remote: Remote
    /// The app's bundle id on the phone (the topic APNs delivers to).
    static var topic: String { Env.value("IOS_BUNDLE") ?? "io.vitalbh.fishbots.ios" }

    struct Device: Codable, Equatable {
        let token: String
        /// "sandbox" for builds signed for development, "production" for TestFlight and the App Store.
        let env: String
        /// The paired device it belongs to (RemoteDevices): its notifications are sealed with that device's key.
        var device: String? = nil
    }

    private(set) var devices: [Device] = []
    let cloud = CloudNotes()
    private var jwt: (token: String, made: Date)?
    private var sent = 0

    init(tank: Tank, permissions: Permissions, remote: Remote) {
        self.tank = tank
        self.permissions = permissions
        self.remote = remote
        devices = (try? JSONDecoder().decode([Device].self, from: Data(contentsOf: Self.devicesFile))) ?? []
    }

    // MARK: - settings

    static var keyId: String { UserDefaults.standard.string(forKey: "pushKeyId") ?? "" }
    static var teamId: String { UserDefaults.standard.string(forKey: "pushTeamId") ?? "" }
    private static var folder: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fishbots") }
    static var keyFile: URL { folder.appendingPathComponent("push-key.p8") }
    private static var devicesFile: URL { folder.appendingPathComponent("push-devices.json") }
    static var dump: URL? { Env.value("PUSH_DUMP").map { URL(fileURLWithPath: $0, isDirectory: true) } }

    /// Notifications on at all (Preferences → General → Notifications on the iPhone).
    static var enabled: Bool { UserDefaults.standard.object(forKey: "pushEnabled") as? Bool ?? true }

    /// Straight to APNs: a key, its id and the team (or the dump folder, for trying).
    var configured: Bool { Self.dump != nil || (!Self.keyId.isEmpty && !Self.teamId.isEmpty && signingKey() != nil) }

    /// Some phone would get one now, either way.
    var reachable: Bool { (configured && (!devices.isEmpty || Self.dump != nil)) || (CloudNotes.available && !cloud.devices.isEmpty) }

    /// How many phones get notifications.
    var receiving: Int { Set((configured ? devices.map { $0.device ?? RemoteTLS.pskIdentity } : []) + (CloudNotes.available ? Array(cloud.devices) : [])).count }

    /// Keeps a copy of the .p8 the person chose, readable by them only.
    static func setKey(from url: URL) throws {
        let pem = try String(contentsOf: url, encoding: .utf8)
        _ = try P256.Signing.PrivateKey(pemRepresentation: pem)            // it is one
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ControlTokens.writePrivately(Data(pem.utf8), to: keyFile)
    }

    private func signingKey() -> P256.Signing.PrivateKey? {
        guard let pem = try? String(contentsOf: Self.keyFile, encoding: .utf8) else { return nil }
        return try? P256.Signing.PrivateKey(pemRepresentation: pem)
    }

    /// The phone's token (`POST /push/register` on the remote listener).
    func register(_ d: Device) {
        devices.removeAll { $0.token == d.token }
        devices.append(d)
        save()
    }

    func forgetDevices() {
        devices = []
        save()
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(devices) { try? ControlTokens.writePrivately(d, to: Self.devicesFile) }
    }

    // MARK: - what's worth a notification

    func send(_ e: TankEvent) {
        guard Remote.enabled, Self.enabled, reachable, !remote.watching,
              let f = tank.fish(source: e.source, entity: e.entity) else { return }
        let name = f.nickname ?? f.displayTitle ?? f.label
        var content: [String: Any] = ["t": name, "f": f.id, "s": e.source, "e": e.entity]
        let category: String
        if e.type == "permission", let p = permissions.request(ofFish: f.id) {
            content["p"] = p.id
            if let q = p.question {
                category = "question"
                content["b"] = "✋ " + q.text
                content["o"] = q.options.prefix(4).map(\.label)
            } else if !p.questions.isEmpty {
                category = "open"
                content["b"] = "✋ " + (p.questions.first?.text ?? "")
            } else {
                category = "permission"
                content["b"] = tr("quer usar %@", p.tool) + ": " + p.summary
            }
        } else if e.type == "state", e.state == State.waiting.rawValue, e.previous != State.waiting.rawValue,
                  permissions.request(ofFish: f.id) == nil {
            category = "waiting"
            let said = f.asked ?? f.lastReply?.split(whereSeparator: \.isNewline).last.map(String.init)
            content["b"] = said.map { String($0.prefix(240)) } ?? tr("terminou e espera você")
        } else if e.type == "state", e.state == State.error.rawValue, e.previous != State.error.rawValue {
            category = "error"
            content["b"] = "✗ " + (f.sub ?? tr("parou com erro"))
        } else {
            return
        }
        content["k"] = category
        deliver(content, category: category, collapse: f.id)
    }

    /// "Mandar um teste" in Preferences.
    func test() {
        deliver(["t": "Fishbots", "b": tr("As notificações do aquário chegam aqui."), "k": "test"], category: "test", collapse: "test")
    }

    // MARK: - APNs

    private func deliver(_ content: [String: Any], category: String, collapse: String) {
        // what Apple sees: that something came, of which kind; the extension replaces the text with the sealed one
        var aps: [String: Any] = ["alert": ["title": "Fishbots", "body": tr("Uma sessão precisa de você")],
                                  "mutable-content": 1, "category": category, "sound": "default",
                                  "thread-id": Self.tag(collapse)]
        if category == "permission" || category == "question" { aps["interruption-level"] = "time-sensitive" }
        /// The payload for one paired device: sealed with its own key (nil: it isn't paired anymore).
        func payload(for device: String) -> [String: Any]? {
            guard let k = remote.devices.key(of: device), let sealed = PushSeal.seal(content, key: PushSeal.key(pairing: k)) else { return nil }
            return ["aps": aps, "fb": sealed]
        }
        // through iCloud: the subscribed phones that don't get them straight from APNs
        let direct = configured ? Set(devices.map { $0.device ?? RemoteTLS.pskIdentity }) : []
        if CloudNotes.available {
            for d in cloud.devices where !direct.contains(d) {
                guard let k = remote.devices.key(of: d) else { cloud.forget(d); continue }
                if let sealed = PushSeal.seal(content, key: PushSeal.key(pairing: k)) { cloud.send(sealed: sealed, to: d) }
            }
        }
        guard configured else { return }
        if let dir = Self.dump {
            // one file per paired device (the simulator's included), named after it
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            sent += 1
            for d in remote.devices.paired {
                guard var p = payload(for: d.id) else { continue }
                p["Simulator Target Bundle"] = Self.topic
                try? JSONSerialization.data(withJSONObject: p, options: [.prettyPrinted]).write(to: dir.appendingPathComponent("push-\(sent)-\(d.id).apns"))
            }
            return
        }
        guard let auth = bearer() else { return }
        // tokens of devices no longer paired go
        let gone = devices.filter { remote.devices.key(of: $0.device ?? RemoteTLS.pskIdentity) == nil }
        if !gone.isEmpty { devices.removeAll { gone.contains($0) }; save() }
        for d in devices {
            guard let p = payload(for: d.device ?? RemoteTLS.pskIdentity), let body = try? JSONSerialization.data(withJSONObject: p) else { continue }
            let host = d.env == "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com"
            guard let url = URL(string: "https://\(host)/3/device/\(d.token)") else { continue }
            var req = URLRequest(url: url, timeoutInterval: 15)
            req.httpMethod = "POST"
            req.httpBody = body
            req.setValue("bearer " + auth, forHTTPHeaderField: "authorization")
            req.setValue(Self.topic, forHTTPHeaderField: "apns-topic")
            req.setValue("alert", forHTTPHeaderField: "apns-push-type")
            req.setValue("10", forHTTPHeaderField: "apns-priority")
            req.setValue(Self.tag(collapse), forHTTPHeaderField: "apns-collapse-id")
            URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
                let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
                guard status != 200 else { return }
                let reason = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }?["reason"] as? String ?? err?.localizedDescription ?? ""
                FileHandle.standardError.write("fishbots: push \(status) \(reason)\n".data(using: .utf8)!)
                // the app was removed, or the token belongs to the other environment: stop sending to it
                if status == 410 || reason == "BadDeviceToken" || reason == "Unregistered" {
                    DispatchQueue.main.async { self?.devices.removeAll { $0 == d }; self?.save() }
                }
            }.resume()
        }
    }

    /// A fish's id as Apple sees it: the same for the same session, telling nothing about it.
    private static func tag(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// The provider token: a JWT signed with the .p8 (ES256), good for an hour; made again after 40 minutes.
    private func bearer() -> String? {
        if let jwt, Date().timeIntervalSince(jwt.made) < 40 * 60 { return jwt.token }
        guard let key = signingKey() else { return nil }
        func b64(_ d: Data) -> String {
            d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        let header = b64(Data(#"{"alg":"ES256","kid":"\#(Self.keyId)"}"#.utf8))
        let claims = b64(Data(#"{"iss":"\#(Self.teamId)","iat":\#(Int(Date().timeIntervalSince1970))}"#.utf8))
        let input = header + "." + claims
        guard let sig = try? key.signature(for: Data(input.utf8)) else { return nil }
        let token = input + "." + b64(sig.rawRepresentation)
        jwt = (token, Date())
        return token
    }
}
