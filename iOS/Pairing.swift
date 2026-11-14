import Foundation
import Network
import Security

/// The Mac this phone is paired with: what the QR code in its Preferences carried (Remote.swift, `pairingURL`).
/// Kept in the Keychain, on this device only (not in backups, not synced): whoever has the key can answer the Mac's
/// permission requests.
struct Pairing: Codable, Equatable {
    var name: String
    var port: UInt16
    /// The Mac's addresses when the code was made (home network, Tailscale's 100.x).
    var hosts: [String]
    /// Its tailnet name (MagicDNS): stays the same when addresses change.
    var tailscale: String
    var key: Data
    /// This device's identity on that Mac (its key is its own); "fishbots" for a pairing from before devices had one.
    var id: String = RemoteTLS.pskIdentity

    /// `fishbots://pair?v=1&name=…&port=…&hosts=…&ts=…&key=…`
    init?(url: URL) {
        guard url.scheme == "fishbots", url.host == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        func value(_ n: String) -> String { items.first { $0.name == n }?.value ?? "" }
        var b64 = value("key").replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let key = Data(base64Encoded: b64), key.count == 32, let port = UInt16(value("port")) else { return nil }
        self.key = key
        self.port = port
        name = value("name")
        hosts = value("hosts").split(separator: ",").map(String.init)
        tailscale = value("ts")
        if !value("id").isEmpty { id = value("id") }
        guard !name.isEmpty || !hosts.isEmpty else { return nil }
    }

    /// Where to look for the Mac, in order: Bonjour (the same network), the tailnet name, then each address.
    var endpoints: [NWEndpoint] {
        var out: [NWEndpoint] = []
        if !name.isEmpty { out.append(.service(name: name, type: RemoteTLS.serviceType, domain: "local.", interface: nil)) }
        if !tailscale.isEmpty { out.append(.hostPort(host: .init(tailscale), port: .init(rawValue: port)!)) }
        for h in hosts { out.append(.hostPort(host: .init(h), port: .init(rawValue: port)!)) }
        return out
    }

    private enum CodingKeys: String, CodingKey { case name, port, hosts, tailscale, key, id }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        port = try c.decode(UInt16.self, forKey: .port)
        hosts = try c.decode([String].self, forKey: .hosts)
        tailscale = try c.decode(String.self, forKey: .tailscale)
        key = try c.decode(Data.self, forKey: .key)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? RemoteTLS.pskIdentity
    }

    // MARK: - the Keychain

    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "fishbots.pairing",
                                               kSecAttrAccount as String: "mac"]

    static func load() -> Pairing? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return try? JSONDecoder().decode(Pairing.self, from: d)
    }

    func save() {
        guard let d = try? JSONEncoder().encode(self) else { return }
        SecItemDelete(Self.query as CFDictionary)
        var q = Self.query
        q[kSecValueData as String] = d
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(q as CFDictionary, nil)
        if status != errSecSuccess { NSLog("fishbots: couldn't keep the pairing in the Keychain (%d)", status) }
    }

    static func forget() { SecItemDelete(query as CFDictionary) }
}
