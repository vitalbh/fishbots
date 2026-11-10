import Foundation

/// A session to start: the agent's command (its provider's to say), where, and what the new pane should know.
struct LaunchRequest {
    let command: [String]
    let cwd: String
    let label: String?
    /// Where the one asking runs (its whereabouts), so the new session opens next to it; nil: wherever the host puts it.
    let near: [String: String]?
    /// In a pane beside the asker's instead of a tab of its own, where the host has panes.
    let beside: Bool
    /// Set in the new pane before the command (FISHBOTS_PARENT…).
    let env: [String: String]

    /// The command with its environment in front (`env K=V … command`): every host runs it the same way.
    var argv: [String] { ["/usr/bin/env"] + env.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" } + command }
}

struct LaunchError: Error {
    let message: String
}

/// Where a session is born: a terminal host that can open a pane running a command (Rex, Herdr, tmux). Creating a
/// session belongs to the host, not to a fish, so this sits next to the providers. See docs/extensions.md, 11.
protocol SessionLauncher: AnyObject {
    /// "rex", "herdr", "tmux"…
    var id: String { get }
    var available: Bool { get }
    /// Is this the host a session with these whereabouts runs in? (A session's children open where it is.)
    func hosts(_ whereabouts: [String: String]) -> Bool
    /// Opens the pane; `done` (on the main thread) gets its whereabouts, the same keys a hook would send
    /// (`rex_block`…), which is how the fish that's born in it is recognized.
    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], LaunchError>) -> Void)
}

/// The registry of launchers.
enum Launchers {
    private(set) static var all: [SessionLauncher] = [RexLauncher(), HerdrLauncher(), TmuxLauncher()]

    static func register(_ l: SessionLauncher) {
        all.removeAll { $0.id == l.id }
        all.append(l)
    }

    /// The one asked for by id; or the host the asker runs in; or the first that can launch now.
    static func pick(_ id: String?, near: [String: String]? = nil) -> SessionLauncher? {
        if let id { return all.first { $0.id == id && $0.available } }
        if let near, let own = all.first(where: { $0.available && $0.hosts(near) }) { return own }
        return all.first { $0.available }
    }

    /// The whereabouts keys that say which pane a session is in.
    static let placeKeys = ["rex_block", "herdr", "tmux"]

    /// Runs a host's CLI off the main thread and hands what it printed (and what it complained about) back on it.
    static func run(_ bin: String, _ args: [String], done: @escaping (_ out: String, _ err: String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err
            var printed = "", said = ""
            do {
                try p.run()
                printed = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                said = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit()
            } catch {
                said = error.localizedDescription
            }
            DispatchQueue.main.async { done(printed, said.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }

    static func failure(_ host: String, _ said: String) -> LaunchError {
        LaunchError(message: said.isEmpty ? "\(host) didn't open a pane" : "\(host): " + String(said.prefix(300)))
    }
}

/// Rex: `rex run` opens a window (a tab) in the asker's session, `rex split` a pane beside the asker's; neither
/// takes the focus.
final class RexLauncher: SessionLauncher {
    let id = "rex"

    var available: Bool { Whereabouts.rexPath([:]) != nil }

    func hosts(_ o: [String: String]) -> Bool { o["rex_block"] != nil }

    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], LaunchError>) -> Void) {
        guard let bin = Whereabouts.rexPath(r.near ?? [:]) else {
            done(.failure(LaunchError(message: "rex isn't installed"))); return
        }
        let session = r.near?["rex_session"]
        var args = ["--autostart=false", "--timeout", "10s"]
        if r.beside, let block = r.near?["rex_block"] { args += ["split", "-b", block] } else { args += ["run"] }
        // --interactive: agents often get into PATH from ~/.zshrc
        args += ["--focus=false", "--interactive", "--json", "-c", r.cwd]
        if let session { args += ["-s", session] }
        if let l = r.label, !l.isEmpty { args += ["--label", l] }
        Launchers.run(bin, args + ["--"] + r.argv) { out, err in
            guard let block = (Whereabouts.json(Data(out.utf8))?["block_ids"] as? [String])?.first else {
                done(.failure(Launchers.failure("rex", err))); return
            }
            var place = ["term": "rex", "rex_block": block, "rex_bin": bin]
            if let session { place["rex_session"] = session }
            done(.success(place))
        }
    }
}

/// Herdr: `herdr-core run --bg` starts a terminal that stays alive without anyone attached; started by a session
/// in Herdr, it's that terminal's child there too (but outlives it, and Herdr types no notes about it into the
/// parent: the asker waits through the aquarium). Herdr has no panes to put it beside.
final class HerdrLauncher: SessionLauncher {
    let id = "herdr"

    var available: Bool { Whereabouts.herdrCorePath != nil }

    func hosts(_ o: [String: String]) -> Bool { o["herdr"] != nil }

    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], LaunchError>) -> Void) {
        guard let core = Whereabouts.herdrCorePath else {
            done(.failure(LaunchError(message: "herdr isn't installed"))); return
        }
        var args = ["run", "--bg", "--json", "--no-notify", "--cwd", r.cwd]
        if let parent = r.near?["herdr"] { args += ["--parent", parent, "--outlive-parent"] } else { args += ["--no-parent"] }
        Launchers.run(core, args + ["--"] + r.argv) { out, err in
            guard let terminal = Whereabouts.json(Data(out.utf8))?["address"] as? String else {
                done(.failure(Launchers.failure("herdr", err))); return
            }
            done(.success(["term": "herdr", "herdr": terminal]))
        }
    }
}

/// tmux: `new-window` after the asker's window (or `split-window` beside its pane), detached so the asker keeps
/// the focus. Needs a tmux server that's running; without an asker in tmux, it's the most recent session's.
final class TmuxLauncher: SessionLauncher {
    let id = "tmux"

    private var bin: String? {
        ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var available: Bool { bin != nil }

    func hosts(_ o: [String: String]) -> Bool { o["tmux"] != nil }

    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], LaunchError>) -> Void) {
        guard let bin else { done(.failure(LaunchError(message: "tmux isn't installed"))); return }
        let pane = r.near?["tmux"]
        var args: [String]
        if r.beside, let pane {
            args = ["split-window", "-d", "-h", "-t", pane]
        } else {
            args = ["new-window", "-d"]
            if let pane { args += ["-a", "-t", pane] }
            if let l = r.label, !l.isEmpty { args += ["-n", l] }
        }
        // several arguments after the options are run as they are, without a shell in between
        args += ["-P", "-F", "#{pane_id}", "-c", r.cwd, "--"] + r.argv
        Launchers.run(bin, args) { out, err in
            let made = out.trimmingCharacters(in: .whitespacesAndNewlines)
            guard made.hasPrefix("%") else { done(.failure(Launchers.failure("tmux", err))); return }
            done(.success(["term": "tmux", "tmux": made]))
        }
    }
}
