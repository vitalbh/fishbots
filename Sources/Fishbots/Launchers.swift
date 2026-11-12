import Foundation

/// A session to start: the agent's command (its provider's to say), where, and what the new pane should know.
struct LaunchRequest {
    let command: [String]
    let cwd: String
    let label: String?
    /// Where the one asking runs (its whereabouts), so the new session opens next to it; nil: wherever the host puts it.
    let near: [String: String]?
    /// In a tab of its own instead of a pane in the asker's, where the host has panes.
    let tab: Bool
    /// Where the asker's other children run, oldest first: the new pane joins their column.
    let siblings: [[String: String]]
    /// The person asked for it themselves (the aquarium's menu, the clutch of eggs): it gets a session of the host
    /// made for it, where the host has them. It doesn't take the focus either: the person is looking at the aquarium.
    var own = false
    /// Set in the new pane before the command (FISHBOTS_PARENT…).
    let env: [String: String]
    /// What the command was made of, for a launcher that doesn't run it in a terminal (Background.swift).
    var agent = ""
    var prompt: String? = nil
    var model: String? = nil

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
    /// Closes a pane it opened, whatever runs in it; `done` gets what went wrong, or nil.
    func close(_ place: [String: String], done: @escaping (String?) -> Void)
}

/// The registry of launchers.
enum Launchers {
    /// In order of preference: the terminals first, the background when there's none.
    private(set) static var all: [SessionLauncher] = [RexLauncher(), HerdrLauncher(), TmuxLauncher(), BackgroundLauncher()]

    /// A launcher that opens a terminal the person can see (to take a conversation there).
    static var terminal: SessionLauncher? { all.first { $0.available && $0.id != "background" } }

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
    static let placeKeys = ["rex_block", "herdr", "tmux", "background"]

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

    /// Where a new pane goes, for a host with panes (`key`: its whereabouts key): the first child to the right of
    /// the asker, the next ones below a sibling, taking turns so the column stays about even. `window`: the panes
    /// that share the asker's window (a sibling in a tab of its own, or closed, isn't in the column).
    static func anchor(_ r: LaunchRequest, _ key: String, window: Set<String>) -> (pane: String, below: Bool)? {
        guard !r.tab, let asker = r.near?[key] else { return nil }
        let column = r.siblings.compactMap { $0[key] }.filter { window.contains($0) }
        guard !column.isEmpty else { return (asker, false) }
        var power = 1
        while power * 2 <= column.count { power *= 2 }
        return (column[column.count - power], true)
    }

    static func failure(_ host: String, _ said: String) -> LaunchError {
        LaunchError(message: said.isEmpty ? "\(host) didn't open a pane" : "\(host): " + String(said.prefix(300)))
    }
}

/// Rex: a block in the asker's window (`rex run --split`: to its right, then down that column), or a window (a tab)
/// of its own in the asker's session; neither takes the focus. One the person opens themselves gets a Rex session
/// of its own (`rex new`), where its children's panes will go.
final class RexLauncher: SessionLauncher {
    let id = "rex"

    var available: Bool { Whereabouts.rexPath([:]) != nil }

    func hosts(_ o: [String: String]) -> Bool { o["rex_block"] != nil }

    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], LaunchError>) -> Void) {
        guard let bin = Whereabouts.rexPath(r.near ?? [:]) else {
            done(.failure(LaunchError(message: "rex isn't installed"))); return
        }
        let session = r.near?["rex_session"]
        var args = ["--autostart=false", "--timeout", "10s", "run", "--focus=false", "--json", "-c", r.cwd]
        if let session { args += ["-s", session] }
        if let l = r.label, !l.isEmpty { args += ["--label", l] }
        let asker = r.near?["rex_block"]
        // --interactive: agents often get into PATH from ~/.zshrc. A Rex from before that flag refuses it: there the
        // user's own shell reads its startup files and then becomes the command.
        func open(_ split: [String], interactive: Bool, else next: (() -> Void)?) {
            let command = interactive ? ["--interactive", "--"] + r.argv : ["--"] + Self.throughShell(r.argv)
            Launchers.run(bin, args + split + command) { out, err in
                if let block = (Whereabouts.json(Data(out.utf8))?["block_ids"] as? [String])?.first {
                    var place = ["term": "rex", "rex_block": block, "rex_bin": bin]
                    if let session { place["rex_session"] = session }
                    done(.success(place))
                } else if interactive, err.contains("unknown flag: --interactive") {
                    open(split, interactive: false, else: next)
                } else if let next {
                    next()
                } else {
                    done(.failure(Launchers.failure("rex", err)))
                }
            }
        }
        if r.own, session == nil { own(r, bin, interactive: true, done: done); return }
        guard !r.tab, let asker else { open([], interactive: true, else: nil); return }
        // which blocks share the asker's window: the siblings among them are the column
        var list = ["--autostart=false", "--timeout", "10s", "block", "ls", "--json"]
        if let session { list += ["-s", session] }
        Launchers.run(bin, list) { out, _ in
            let blocks = Whereabouts.json(Data(out.utf8))?["blocks"] as? [[String: Any]] ?? []
            let window = blocks.first { $0["block_id"] as? String == asker }?["window_id"] as? String
            let shared = Set(blocks.filter { window != nil && $0["window_id"] as? String == window }.compactMap { $0["block_id"] as? String })
            guard let anchor = Launchers.anchor(r, "rex_block", window: shared) else { open([], interactive: true, else: nil); return }
            // the sibling it would go under may have just been closed: then beside the asker, as the first one
            let besideAsker = { open(["--split", "right", "-b", asker], interactive: true, else: nil) }
            open(["--split", anchor.below ? "below" : "right", "-b", anchor.pane], interactive: true, else: anchor.below ? besideAsker : nil)
        }
    }

    /// A Rex session of its own, named after what it's for, with the command in its first block.
    private func own(_ r: LaunchRequest, _ bin: String, interactive: Bool, done: @escaping (Result<[String: String], LaunchError>) -> Void) {
        var args = ["--autostart=false", "--timeout", "10s", "new"]
        if let l = r.label, !l.isEmpty { args += [l] }
        args += ["--json", "-c", r.cwd]
        let command = interactive ? ["--interactive", "--"] + r.argv : ["--"] + Self.throughShell(r.argv)
        Launchers.run(bin, args + command) { out, err in
            let made = Whereabouts.json(Data(out.utf8))
            let first = (made?["initial_windows"] as? [[String: Any]])?.first?["block_ids"] as? [String]
            guard let session = made?["session_id"] as? String, let block = first?.first else {
                if interactive, err.contains("unknown flag: --interactive") { self.own(r, bin, interactive: false, done: done); return }
                done(.failure(Launchers.failure("rex", err))); return
            }
            done(.success(["term": "rex", "rex_session": session, "rex_block": block, "rex_bin": bin]))
        }
    }

    func close(_ place: [String: String], done: @escaping (String?) -> Void) {
        guard let bin = Whereabouts.rexPath(place), let block = place["rex_block"] else { done("rex: no pane to close"); return }
        var args = ["--autostart=false", "--timeout", "10s", "block", "close", block]
        if let session = place["rex_session"] { args += ["-s", session] }
        Launchers.run(bin, args) { _, err in done(err.isEmpty ? nil : "rex: " + err) }
    }

    /// The command run by the user's interactive login shell (zsh or bash; any other shell: the command as it is).
    static func throughShell(_ argv: [String]) -> [String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard ["zsh", "bash"].contains((shell as NSString).lastPathComponent) else { return argv }
        return [shell, "-ilc", #"exec "$@""#, "fishbots"] + argv
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

    func close(_ place: [String: String], done: @escaping (String?) -> Void) {
        guard let core = Whereabouts.herdrCorePath, let terminal = place["herdr"] else { done("herdr: no terminal to close"); return }
        Launchers.run(core, ["kill", terminal]) { _, err in done(err.isEmpty ? nil : "herdr: " + err) }
    }
}

/// tmux: `split-window` beside the asker's pane, then down that column (or `new-window` after the asker's window),
/// detached so the asker keeps the focus. Needs a tmux server that's running; without an asker in tmux, it's the most recent session's.
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
        func open(_ window: Set<String>) {
            var args: [String]
            if let anchor = Launchers.anchor(r, "tmux", window: window) {
                args = ["split-window", "-d", anchor.below ? "-v" : "-h", "-t", anchor.pane]
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
        guard !r.tab, let pane else { open([]); return }
        // the panes of the asker's window: the siblings among them are the column
        Launchers.run(bin, ["list-panes", "-t", pane, "-F", "#{pane_id}"]) { out, _ in
            open(Set(out.split(separator: "\n").map(String.init)))
        }
    }

    func close(_ place: [String: String], done: @escaping (String?) -> Void) {
        guard let bin, let pane = place["tmux"] else { done("tmux: no pane to close"); return }
        Launchers.run(bin, ["kill-pane", "-t", pane]) { _, err in done(err.isEmpty ? nil : "tmux: " + err) }
    }
}
