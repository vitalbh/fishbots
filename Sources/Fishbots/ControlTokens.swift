import Foundation
import Security

/// Who may use the control routes (/control/*, SessionControl.swift): a bearer token, new on every launch.
///
/// - The person's own: written to control.token in the app's Application Support folder (0600), next to fish.json.
///   `fishbots` reads it from any terminal, and the resident assistant gets it from the app. Full reach.
/// - One per session the aquarium launches, in its pane's environment (FISHBOTS_TOKEN): it says which fish is
///   asking, so the app doesn't take a session's word for who it is, and it reaches only the children it launched.
///
/// Nothing is kept across launches: after a restart the sessions' tokens are dead, and `fishbots` falls back to the
/// file (a restored session commands with the person's token, as a session the aquarium didn't launch does).
enum ControlTokens {
    /// A session's token: the pane it was launched in, and its fish once it's born there.
    final class Grant {
        let token: String
        let source: String
        /// The pane's whereabouts (rex_block, herdr, tmux, background), once the launcher opened it.
        var place: [String: String] = [:]
        /// Its fish's id, once it's born.
        var fish: String?
        /// The session that launched it, when it was launched with a token of its own: the only one, with the
        /// person, that can reply to it, stop it and close it.
        let parent: Grant?

        init(token: String, source: String, parent: Grant?) {
            self.token = token
            self.source = source
            self.parent = parent
        }
    }

    /// The person's token for this run.
    private(set) static var person = ""
    private static var grants: [Grant] = []

    /// Where the person's token is written. A test instance on another port writes its own, so it doesn't
    /// overwrite the token of the aquarium on 7777 when they share a home folder.
    static func file(port: UInt16) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fishbots/" + (port == 7777 ? "control.token" : "control-\(port).token"))
    }

    /// Makes this run's token and writes it, readable by the user only. Called once, as the server opens.
    static func start(port: UInt16) {
        person = make()
        let url = file(port: port)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try writePrivately(Data((person + "\n").utf8), to: url)
        } catch {
            FileHandle.standardError.write("fishbots: couldn't write \(url.path): \(error)\n".data(using: .utf8)!)
        }
    }

    /// A new session's token, before its pane opens (it goes in the pane's environment).
    static func issue(source: String, parent: Grant?) -> Grant {
        let g = Grant(token: make(), source: source, parent: parent)
        grants.append(g)
        return g
    }

    /// The pane didn't open: its token goes.
    static func revoke(_ g: Grant) {
        grants.removeAll { $0 === g }
    }

    /// The sessions launched by the one holding this token.
    static func children(of g: Grant) -> [Grant] {
        grants.filter { $0.parent === g }
    }

    enum Bearer {
        case person
        case session(Grant)
    }

    /// Whose token this request carries, if it's one of this run's.
    static func bearer(_ headers: [String: String]) -> Bearer? {
        guard let auth = headers["authorization"], auth.count > 7, auth.prefix(7).lowercased() == "bearer " else { return nil }
        let t = auth.dropFirst(7).trimmingCharacters(in: .whitespaces)
        if !person.isEmpty, same(t, person) { return .person }
        if let g = grants.first(where: { same(t, $0.token) }) { return .session(g) }
        return nil
    }

    /// 32 random bytes, as hex.
    private static func make() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            fatalError("fishbots: no random bytes for the control token")
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Compares without stopping at the first difference.
    private static func same(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var d: UInt8 = 0
        for i in x.indices { d |= x[i] ^ y[i] }
        return d == 0
    }

    /// Created 0600 under a temporary name and moved over the old one, so the token is never readable by others,
    /// not even for a moment, and a reader never sees half of it.
    static func writePrivately(_ data: Data, to url: URL) throws {
        let tmp = url.path + ".\(getpid()).tmp"
        unlink(tmp)
        let fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let written = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        close(fd)
        guard written == data.count, rename(tmp, url.path) == 0 else {
            unlink(tmp)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
