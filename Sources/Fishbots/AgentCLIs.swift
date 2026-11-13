import Foundation

/// How the person runs each agent's command line on this Mac (Preferences → Agents): which binary, extra
/// parameters, and variables (the account's folder, for one). The aquarium uses it wherever it starts an agent
/// itself: a new session in a terminal (Launchers) and the resident assistant in the background (Brains).
/// A shell alias doesn't reach either of those, so what the alias did is written here instead.
struct AgentCLI: Equatable {
    /// A path or a name to look for in the shell's PATH; empty: the agent's usual command.
    var binary = ""
    /// Extra parameters, as typed in a shell (quotes keep words together).
    var arguments = ""
    /// `NAME=value` words (`CLAUDE_CONFIG_DIR=~/.claude-work`).
    var environment = ""
}

enum AgentCLIs {
    private static let key = "agentCLI"

    static func settings(_ agent: String) -> AgentCLI {
        let d = (UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]])?[agent] ?? [:]
        return AgentCLI(binary: d["binary"] ?? "", arguments: d["arguments"] ?? "", environment: d["environment"] ?? "")
    }

    static func set(_ agent: String, _ c: AgentCLI) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: [String: String]] ?? [:]
        let d = ["binary": c.binary, "arguments": c.arguments, "environment": c.environment]
            .mapValues { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.value.isEmpty }
        all[agent] = d.isEmpty ? nil : d
        UserDefaults.standard.set(all, forKey: key)
    }

    /// Words as a shell would split them: spaces separate, single and double quotes keep together, a backslash
    /// takes the next character as it is.
    static func words(_ s: String) -> [String] {
        var out: [String] = [], cur = "", quote: Character?, any = false, escaped = false
        for ch in s {
            if escaped { cur.append(ch); escaped = false; continue }
            if ch == "\\", quote != "'" { escaped = true; any = true; continue }
            if let q = quote { if ch == q { quote = nil } else { cur.append(ch) }; continue }
            if ch == "\"" || ch == "'" { quote = ch; any = true; continue }
            if ch.isWhitespace { if any || !cur.isEmpty { out.append(cur) }; cur = ""; any = false; continue }
            cur.append(ch)
        }
        if any || !cur.isEmpty { out.append(cur) }
        return out
    }

    /// The variables set for this agent (a leading `~` in a value is the home folder).
    static func environment(_ agent: String) -> [String: String] {
        var env: [String: String] = [:]
        for w in words(settings(agent).environment) {
            guard let eq = w.firstIndex(of: "="), eq != w.startIndex else { continue }
            let name = String(w[..<eq])
            guard name.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else { continue }
            env[name] = NSString(string: String(w[w.index(after: eq)...])).expandingTildeInPath
        }
        return env
    }

    static func arguments(_ agent: String) -> [String] { words(settings(agent).arguments) }

    /// A command for a terminal (`["claude", "--model", …]`) the way the person runs this agent: their binary
    /// instead of the usual name, their parameters right after it.
    static func launch(_ agent: String, _ command: [String]) -> [String] {
        guard let first = command.first else { return command }
        let s = settings(agent)
        let binary = s.binary.isEmpty ? first : NSString(string: s.binary).expandingTildeInPath
        return [binary] + words(s.arguments) + command.dropFirst()
    }

    // MARK: - finding the binary without a terminal

    private static var cachedPath: String?
    private static let lock = NSLock()

    /// The PATH of the person's login shell (the app, opened from the Finder, has only the system's). Asked once,
    /// from a background thread; the app's own PATH if the shell doesn't answer in time.
    static var shellPath: String {
        lock.lock(); defer { lock.unlock() }
        if let p = cachedPath { return p }
        let own = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        var found: String?
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if ["zsh", "bash"].contains((shell as NSString).lastPathComponent) {
            let p = Process(), out = Pipe()
            p.executableURL = URL(fileURLWithPath: shell)
            // a marker on its own line: the shell's startup files may print things of their own
            p.arguments = ["-ilc", #"printf '\n__FISHBOTS_PATH__%s\n' "$PATH""#]
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            if (try? p.run()) != nil {
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: killer)
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()
                let text = String(data: data, encoding: .utf8) ?? ""
                found = text.components(separatedBy: "\n").last { $0.hasPrefix("__FISHBOTS_PATH__") }
                    .map { String($0.dropFirst("__FISHBOTS_PATH__".count)) }
            }
        }
        // the usual places a CLI is installed, in case the shell said nothing
        let usual = ["~/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"].map { NSString(string: $0).expandingTildeInPath }
        let parts = ((found?.isEmpty == false ? found! : own).split(separator: ":").map(String.init) + usual)
        var seen = Set<String>()
        let path = parts.filter { seen.insert($0).inserted }.joined(separator: ":")
        cachedPath = path
        return path
    }

    /// Where this agent's executable is: the person's binary (a path, or a name looked for in the shell's PATH),
    /// or the usual name. nil: not installed. Don't call it on the main thread the first time (it asks the shell).
    static func executable(_ agent: String, usual: String) -> String? {
        let s = settings(agent).binary
        let name = s.isEmpty ? usual : NSString(string: s).expandingTildeInPath
        let fm = FileManager.default
        if name.contains("/") { return fm.isExecutableFile(atPath: name) ? name : nil }
        for dir in shellPath.split(separator: ":") {
            let p = String(dir) + "/" + name
            if fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }

    /// The environment for an agent the aquarium runs itself: the app's, with the shell's PATH, without what a
    /// Claude Code session leaves behind for its children (the app may have been opened from one), plus `extra`.
    static func processEnvironment(_ agent: String, extra: [String: String] = [:]) -> [String: String] {
        // not where the app itself was started from (a terminal's pane, a session it's the child of): the session's
        // hook would say it runs there. Its own leader, if it has one, comes back in `extra`
        let elsewhere: Set<String> = ["REX_SESSION", "REX_BLOCK", "HC_TERMINAL_ID", "TMUX", "TMUX_PANE", "ITERM_SESSION_ID",
                                      "WEZTERM_PANE", "KITTY_WINDOW_ID", "TERM_PROGRAM", "FISHBOTS_PARENT"]
        var env = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("CLAUDE_CODE_") && $0.key != "CLAUDECODE" && !elsewhere.contains($0.key)
        }
        env["PATH"] = shellPath
        env.merge(extra) { $1 }
        env.merge(environment(agent)) { $1 }
        return env
    }
}
