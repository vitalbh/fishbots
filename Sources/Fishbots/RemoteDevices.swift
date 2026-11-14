import Foundation
import Security

/// The devices paired with this Mac (Remote.swift), each with a key of its own: revoking one takes its key out of
/// the listener, and that device fails the handshake from then on while the others go on.
///
/// The QR code in Preferences always carries a key no device holds yet (`pending`); the first request a device makes
/// with it pairs it under its own name, and a fresh pending key takes its place for the next one. TLS proves a device
/// holds one of the keys but doesn't say which, so a device names itself in a header (`X-Fishbots-Device`): enough to
/// show who's paired and to seal its notifications with its key. Every device that can connect is one the person
/// paired, so a device naming itself as another changes nothing that matters; revoking is what's enforced, by TLS.
final class RemoteDevices {
    struct Device: Codable, Equatable {
        /// Its identity in the TLS handshake (`fishbots` for the one paired before each device had its own key).
        let id: String
        var name: String
        let key: Data
        let added: Date
        var seen: Date?
        /// Carried by the QR code, not used yet.
        var pending: Bool
    }

    private(set) var all: [Device] = []
    private let file: URL
    /// The keys changed (one paired, revoked, forgotten): the listener opens again with the new set.
    var keysChanged: (() -> Void)?

    init(port: UInt16) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fishbots")
        file = folder.appendingPathComponent(port == 7778 ? "remote-devices.json" : "remote-devices-\(port).json")
        all = (try? JSONDecoder().decode([Device].self, from: Data(contentsOf: file))) ?? []
        // the single key of earlier versions: the device paired with it stays paired, under the old identity
        let legacy = folder.appendingPathComponent(port == 7778 ? "remote.key" : "remote-\(port).key")
        if let hex = try? String(contentsOf: legacy, encoding: .utf8), let k = Data(hex: hex.trimmingCharacters(in: .whitespacesAndNewlines)), k.count == 32 {
            if !all.contains(where: { $0.id == RemoteTLS.pskIdentity }) {
                all.append(Device(id: RemoteTLS.pskIdentity, name: tr("aparelho pareado antes"), key: k, added: Date(), seen: nil, pending: false))
            }
            try? FileManager.default.removeItem(at: legacy)
        }
        if !all.contains(where: \.pending) { all.append(Self.fresh()) }
        save()
    }

    var paired: [Device] { all.filter { !$0.pending } }
    /// The key the QR code carries now.
    var pending: Device { all.first(where: \.pending) ?? { let d = Self.fresh(); all.append(d); save(); return d }() }
    /// Every key the listener accepts: the paired ones and the pending one.
    var keys: [(id: String, key: Data)] { all.map { ($0.id, $0.key) } }

    func key(of id: String) -> Data? { all.first { $0.id == id }?.key }

    /// A request named this device: it's seen now, and if it came with the pending key it's paired (and the QR code
    /// gets a new one).
    func heard(from id: String, name: String?) {
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        let wasPending = all[i].pending
        if let n = name?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty { all[i].name = String(n.prefix(60)) }
        // (seen at most once a minute on disk)
        if wasPending || all[i].seen.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
            all[i].seen = Date()
            if wasPending {
                all[i].pending = false
                all.append(Self.fresh())
            }
            save()
        }
        if wasPending { keysChanged?() }
    }

    func revoke(_ id: String) {
        all.removeAll { $0.id == id }
        if !all.contains(where: \.pending) { all.append(Self.fresh()) }
        save()
        keysChanged?()
    }

    /// Every device out, and a new pending key.
    func forgetAll() {
        all = [Self.fresh()]
        save()
        keysChanged?()
    }

    private static func fresh() -> Device {
        Device(id: "d-" + random(6).map { String(format: "%02x", $0) }.joined(), name: "", key: random(32), added: Date(), seen: nil, pending: true)
    }

    private static func random(_ n: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: n)
        guard SecRandomCopyBytes(kSecRandomDefault, n, &bytes) == errSecSuccess else { fatalError("fishbots: no random bytes for a pairing key") }
        return Data(bytes)
    }

    private func save() {
        guard let d = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ControlTokens.writePrivately(d, to: file)
    }
}

extension Data {
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
