import CryptoKit
import Foundation

/// A notification's content, sealed so only the paired phone reads it (Push.swift on the Mac seals, the iPhone's
/// notification extension opens). Apple's push service carries it without seeing what a session asked, its command
/// or its words: it sees only that something came for this phone.
///
/// The key is derived from the pairing key, so the extension never holds the key that talks to the Mac.
enum PushSeal {
    static func key(pairing: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: pairing), salt: Data("fishbots-push-v1".utf8),
                               info: Data("notification".utf8), outputByteCount: 32)
    }

    /// The object as JSON, sealed (ChaChaPoly, nonce and tag included), in base64.
    static func seal(_ obj: [String: Any], key: SymmetricKey) -> String? {
        guard let d = try? JSONSerialization.data(withJSONObject: obj), let box = try? ChaChaPoly.seal(d, using: key) else { return nil }
        return box.combined.base64EncodedString()
    }

    static func open(_ s: String, key: SymmetricKey) -> [String: Any]? {
        guard let d = Data(base64Encoded: s), let box = try? ChaChaPoly.SealedBox(combined: d),
              let plain = try? ChaChaPoly.open(box, using: key) else { return nil }
        return (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any]
    }
}
