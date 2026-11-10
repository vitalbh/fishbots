import AppKit

/// "Are you looking at it?": asked when a fish is about to call you (starts waiting, an error, an alert, a reminder):
/// is its terminal in front, with the focus on its pane? If so, it calls without sound (motif, knocks, the question
/// read aloud): you're already there. It still changes color, and the notice still arrives.
///
/// Rex: the pane with the focus in the active window of the fish's session (Rex doesn't say which session its window
/// shows, so another session's tab can still count: only the sound is silenced). Herdr: the terminal in the focused pane.
/// iTerm: the current session of the front window. tmux: the active pane of an attached session, with a terminal in front.
enum InView {
    /// Asks now; meanwhile the fish holds its call (`looking`), and Music plays it once the answer is in.
    static func check(_ f: Fish) {
        guard !f.looking else { return }
        let front = NSWorkspace.shared.frontmostApplication
        // FISHBOTS_FRONT=<app name or bundle id>: pretends that app is in front (tests)
        let pretend = ProcessInfo.processInfo.environment["FISHBOTS_FRONT"]
        guard !f.decor, !f.whereabouts.isEmpty,
              let app = App(bundle: pretend ?? front?.bundleIdentifier ?? "", name: pretend ?? front?.localizedName ?? "") else {
            f.inView = false
            f.lookedAt = Date()
            f.lookedSince = f.since
            return
        }
        let o = f.whereabouts
        let since = f.since
        f.looking = true
        DispatchQueue.global(qos: .userInitiated).async {
            let seen = look(app, o)
            DispatchQueue.main.async {
                f.inView = seen
                f.lookedAt = Date()
                f.lookedSince = since
                f.looking = false
            }
        }
    }

    private enum App {
        case rex, herdr, iterm, other
        init?(bundle: String, name: String) {
            if name.hasPrefix("Rex") { self = .rex }
            else if bundle == "dev.herdr.app" { self = .herdr }
            else if bundle == "com.googlecode.iterm2" { self = .iterm }
            else if terminals.contains(bundle) { self = .other }
            else { return nil }
        }
    }
    /// Terminals that may hold a tmux session.
    private static let terminals: Set<String> = ["com.apple.Terminal", "com.mitchellh.ghostty", "com.github.wez.wezterm",
                                                 "net.kovidgoyal.kitty", "org.alacritty", "dev.warp.Warp-Stable"]

    /// Is this session on screen, in the app in front?
    private static func look(_ app: App, _ o: [String: String]) -> Bool {
        switch app {
        case .rex:
            // the session's active window, and that window's focused pane
            guard let s = o["rex_session"], let b = o["rex_block"], let bin = Whereabouts.rexPath(o) else { return false }
            let d = Whereabouts.json(Whereabouts.run(bin, ["--timeout", "2s", "window", "ls", "-s", s, "--json"]))
            let active = d?["active_window_id"] as? String
            let win = (d?["windows"] as? [[String: Any]])?.first { $0["window_id"] as? String == active }
            return win?["focused_block_id"] as? String == b
        case .herdr:
            guard let t = o["herdr"], let app = Whereabouts.herdrAppPath else { return false }
            return Whereabouts.json(Whereabouts.run(app, ["status"]))?["agent"] as? String == t
        case .iterm:
            guard o["term"] == "iTerm.app", let i = o["iterm"] else { return tmux(o) }
            let out = Whereabouts.run("/usr/bin/osascript", ["-e",
                "tell application id \"com.googlecode.iterm2\" to get unique id of current session of current window"])
            let current = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return !current.isEmpty && i.split(separator: ":").last.map(String.init) == current
        case .other:
            return tmux(o)
        }
    }

    /// tmux (in whichever terminal is in front): the active pane of the active window, with a client attached.
    private static func tmux(_ o: [String: String]) -> Bool {
        guard let p = o["tmux"], !p.isEmpty,
              let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"].first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return false }
        let out = Whereabouts.run(tmux, ["display-message", "-p", "-t", p, "#{pane_active}#{window_active}#{session_attached}"])
        let r = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return r.hasPrefix("11") && r != "110"
    }
}
