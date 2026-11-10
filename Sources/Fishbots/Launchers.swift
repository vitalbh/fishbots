import Foundation

/// A session to start: the agent's command (its provider's to say), where, and what the new pane should know.
struct LaunchRequest {
    let command: [String]
    let cwd: String
    let label: String?
    /// Where the one asking runs (its whereabouts), so the new session opens next to it; nil: wherever the host puts it.
    let near: [String: String]?
    /// Set in the new pane before the command (FISHBOTS_PARENT…).
    let env: [String: String]
}

struct LaunchError: Error {
    let message: String
}

/// Where a session is born: a terminal host that can open a pane running a command (Rex; Herdr and tmux can be
/// one more each). Creating a session belongs to the host, not to a fish, so this sits next to the providers.
/// See docs/extensions.md, 11.
protocol SessionLauncher: AnyObject {
    /// "rex", "herdr", "tmux"…
    var id: String { get }
    var available: Bool { get }
    /// Opens the pane; `done` (on the main thread) gets its whereabouts, the same keys a hook would send
    /// (`rex_block`…), which is how the fish that's born in it is recognized.
    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], LaunchError>) -> Void)
}

/// The registry of launchers.
enum Launchers {
    private(set) static var all: [SessionLauncher] = [RexLauncher()]

    static func register(_ l: SessionLauncher) {
        all.removeAll { $0.id == l.id }
        all.append(l)
    }

    /// The one asked for by id, or the first that can launch now.
    static func pick(_ id: String?) -> SessionLauncher? {
        if let id { return all.first { $0.id == id && $0.available } }
        return all.first { $0.available }
    }

    /// The whereabouts keys that say which pane a session is in.
    static let placeKeys = ["rex_block", "herdr", "tmux"]
}

/// Rex: `rex run` opens a window (a tab) in the asker's session, without taking the focus.
final class RexLauncher: SessionLauncher {
    let id = "rex"

    var available: Bool { Whereabouts.rexPath([:]) != nil }

    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], LaunchError>) -> Void) {
        guard let bin = Whereabouts.rexPath(r.near ?? [:]) else {
            done(.failure(LaunchError(message: "rex isn't installed"))); return
        }
        let session = r.near?["rex_session"]
        // --interactive: agents often get into PATH from ~/.zshrc
        var args = ["--autostart=false", "--timeout", "10s", "run", "--focus=false", "--interactive", "--json", "-c", r.cwd]
        if let session { args += ["-s", session] }
        if let l = r.label, !l.isEmpty { args += ["--label", l] }
        args += ["--", "/usr/bin/env"] + r.env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" } + r.command
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            var result: Result<[String: String], LaunchError>
            do {
                try p.run()
                let made = Whereabouts.json(out.fileHandleForReading.readDataToEndOfFile())
                let said = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit()
                if let block = (made?["block_ids"] as? [String])?.first {
                    var place = ["term": "rex", "rex_block": block, "rex_bin": bin]
                    if let session { place["rex_session"] = session }
                    result = .success(place)
                } else {
                    let why = said.trimmingCharacters(in: .whitespacesAndNewlines)
                    result = .failure(LaunchError(message: why.isEmpty ? "rex didn't open a pane" : "rex: " + String(why.prefix(300))))
                }
            } catch {
                result = .failure(LaunchError(message: "couldn't run rex: \(error.localizedDescription)"))
            }
            DispatchQueue.main.async { done(result) }
        }
    }
}
