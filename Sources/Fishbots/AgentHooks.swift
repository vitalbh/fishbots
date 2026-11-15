import Foundation

/// Connecting the coding agents to the aquarium from the app, and taking them out again: what
/// scripts/install-hooks.sh does from a clone, for whoever installed the app from the DMG (Preferences → General →
/// Agents). The hooks' scripts come inside the app (Contents/Resources/plugins, scripts/app.sh puts them there) and are
/// copied to a fixed place, ~/.local/share/fishbots/plugins, so moving or updating the app doesn't break them; each
/// launch copies them again, so they follow the app's version. The agent's settings get the same entries as
/// plugins/<agent>/hooks.json, pointing there.
///
/// A hook is Fishbots' when it runs …/plugins/<agent>/hook.sh or permission.sh, from any clone or from the app.
/// Every settings file it changes gets a backup next to it first (.bak-fishbots-…).
enum AgentHooks {
    struct Place {
        let agent: String
        let file: URL
    }

    /// The agents that connect through hooks, in the order Preferences lists them.
    struct Agent {
        let id: String
        let name: String
        /// It answers permission requests from the aquarium too (plugins/<agent>/permission.sh).
        let permissions: Bool
    }

    static let agents = [Agent(id: "claude-code", name: "Claude Code", permissions: true),
                         Agent(id: "codex", name: "Codex", permissions: true),
                         Agent(id: "cursor", name: "Cursor", permissions: false),
                         Agent(id: "antigravity", name: "Antigravity", permissions: false),
                         Agent(id: "opencode", name: "opencode", permissions: false)]

    private static var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    /// Where each agent keeps its hooks; Claude Code also in each folder CLAUDE_CONFIG_DIR may point at (~/.claude-*).
    static var places: [Place] {
        let claude = ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [])
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }.sorted()
            .map { Place(agent: "claude-code", file: home.appendingPathComponent($0).appendingPathComponent("settings.json")) }
        return claude + [Place(agent: "codex", file: home.appendingPathComponent(".codex/hooks.json")),
                         Place(agent: "cursor", file: home.appendingPathComponent(".cursor/hooks.json")),
                         Place(agent: "antigravity", file: home.appendingPathComponent(".gemini/config/hooks.json")),
                         Place(agent: "gemini", file: home.appendingPathComponent(".gemini/settings.json"))]
    }

    /// The file a new connection goes to (Claude Code: the usual folder).
    private static func target(_ agent: String) -> URL? {
        switch agent {
        case "claude-code": return home.appendingPathComponent(".claude/settings.json")
        default: return places.first { $0.agent == agent }?.file
        }
    }

    static var opencodeLink: URL { home.appendingPathComponent(".config/opencode/plugins/fishbots.js") }

    /// Where the app keeps the hooks' scripts (no spaces in the path: the agents run it as a command line).
    static var installed: URL { home.appendingPathComponent(".local/share/fishbots") }

    /// The hooks' scripts this app brings: inside the bundle, or the clone's when it runs from `swift run`.
    static var source: URL? {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("plugins"),
           FileManager.default.fileExists(atPath: r.appendingPathComponent("common/hook.sh").path) { return r }
        var dir = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<5 {
            let p = dir.appendingPathComponent("plugins")
            if FileManager.default.fileExists(atPath: p.appendingPathComponent("common/hook.sh").path) { return p }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: - state

    /// The agent is installed here (its settings folder exists).
    static func present(_ agent: String) -> Bool {
        let dir: String
        switch agent {
        case "claude-code": dir = ".claude"
        case "codex": dir = ".codex"
        case "cursor": dir = ".cursor"
        case "antigravity": dir = ".gemini/config"
        case "opencode": dir = ".config/opencode"
        default: return false
        }
        return FileManager.default.fileExists(atPath: home.appendingPathComponent(dir).path)
    }

    /// Its hooks are in (in any of its settings files).
    static func isConnected(_ agent: String) -> Bool {
        if agent == "opencode" { return isOurs(link: opencodeLink) }
        return places.contains { $0.agent == agent && (load($0.file).map { strip($0, agent: agent).removed > 0 } ?? false) }
    }

    /// Its permission hook is in.
    static func answersPermissions(_ agent: String) -> Bool {
        places.contains { $0.agent == agent && (load($0.file).map { strip($0, agent: agent, only: ["permission"]).removed > 0 } ?? false) }
    }

    /// The files that have Fishbots' hooks now.
    static func connected() -> [URL] {
        places.filter { p in load(p.file).map { strip($0, agent: p.agent).removed > 0 } ?? false }.map(\.file)
            + (isOurs(link: opencodeLink) ? [opencodeLink] : [])
    }

    // MARK: - connecting

    /// Copies the hooks' scripts to their fixed place (again: they follow this app's version). Only once some agent
    /// is connected through it, or when connecting one.
    @discardableResult
    static func installScripts() -> Bool {
        guard let source else { return false }
        let fm = FileManager.default
        let dest = installed.appendingPathComponent("plugins")
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for name in ["common"] + agents.map(\.id) + ["gemini"] {
                let from = source.appendingPathComponent(name), to = dest.appendingPathComponent(name)
                guard fm.fileExists(atPath: from.path) else { continue }
                try? fm.removeItem(at: to)
                try fm.copyItem(at: from, to: to)
            }
            return true
        } catch {
            return false
        }
    }

    /// Keeps the scripts in step with the app, at launch, if this app connected any agent.
    static func refreshScripts() {
        guard FileManager.default.fileExists(atPath: installed.appendingPathComponent("plugins/common/hook.sh").path),
              Bundle.main.resourceURL.map({ FileManager.default.fileExists(atPath: $0.appendingPathComponent("plugins").path) }) ?? false
        else { return }
        installScripts()
    }

    /// Puts the agent's hooks in its settings (pointing at the scripts copied by installScripts), with the permission
    /// hook when asked. An agent already connected from a clone stays as it is. Nil when it went in; otherwise why not.
    static func connect(_ agent: String, permissions: Bool = false) -> String? {
        guard installScripts(), let src = source else { return tr("Este app não trouxe os scripts dos hooks.") }
        let root = installed.path
        if agent == "opencode" {
            let link = opencodeLink
            let to = installed.appendingPathComponent("plugins/opencode/fishbots.js")
            do {
                try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
                if isOurs(link: link) { return nil }
                if FileManager.default.fileExists(atPath: link.path) { try backup(link); try FileManager.default.removeItem(at: link) }
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: to)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        guard let file = target(agent),
              let tdata = try? Data(contentsOf: src.appendingPathComponent("\(agent)/hooks.json")),
              let tstring = String(data: tdata, encoding: .utf8),
              let template = (try? JSONSerialization.jsonObject(with: Data(tstring.replacingOccurrences(of: "~/Dev/fishbots", with: root).utf8))) as? [String: Any]
        else { return tr("Não achei o modelo dos hooks desse agente.") }
        var data = load(file) ?? [:]
        var added = 0
        if agent == "antigravity" {
            if data["fishbots"] == nil, let ours = template["fishbots"] { data["fishbots"] = ours; added = 1 }
        } else {
            if agent == "cursor", data["version"] == nil { data["version"] = 1 }
            var hooks = data["hooks"] as? [String: Any] ?? [:]
            for (event, value) in template["hooks"] as? [String: Any] ?? [:] {
                for entry in value as? [[String: Any]] ?? [] {
                    let cmds = commands(entry)
                    if cmds.contains(where: { $0.hasSuffix("/permission.sh") }) && !permissions { continue }
                    let have = Set((hooks[event] as? [[String: Any]] ?? []).flatMap(commands).map { key($0, agent) })
                    if cmds.contains(where: { have.contains(key($0, agent)) }) { continue }
                    hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [entry]
                    added += 1
                }
            }
            data["hooks"] = hooks
        }
        guard added > 0 else { return nil }
        return write(data, to: file)
    }

    /// Takes out only the permission hook (the agent stays connected).
    static func stopAnsweringPermissions(_ agent: String) {
        for p in places where p.agent == agent {
            guard let obj = load(p.file) else { continue }
            let (clean, removed) = strip(obj, agent: agent, only: ["permission"])
            if removed > 0 { _ = write(clean, to: p.file) }
        }
    }

    // MARK: - disconnecting

    /// Takes them out (one agent, or all); one line per file it changed (or couldn't).
    @discardableResult
    static func disconnect(_ only: String? = nil) -> [String] {
        var report: [String] = []
        for p in places where only == nil || p.agent == only {
            guard let obj = load(p.file) else { continue }
            let (clean, removed) = strip(obj, agent: p.agent)
            guard removed > 0 else { continue }
            if let why = write(clean, to: p.file) {
                report.append(String(format: tr("%@: não consegui mudar (%@)"), tilde(p.file), why))
            } else {
                report.append(String(format: tr("%@: %d hook(s) removidos"), tilde(p.file), removed))
            }
        }
        if (only == nil || only == "opencode"), isOurs(link: opencodeLink) {
            do { try FileManager.default.removeItem(at: opencodeLink); report.append(String(format: tr("%@: removido"), tilde(opencodeLink))) }
            catch { report.append(String(format: tr("%@: não consegui mudar (%@)"), tilde(opencodeLink), error.localizedDescription)) }
        }
        return report
    }

    // MARK: -

    private static func load(_ file: URL) -> [String: Any]? {
        guard let d = try? Data(contentsOf: file) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// Writes the settings, after a backup of what was there. Nil when it went well.
    private static func write(_ obj: [String: Any], to file: URL) -> String? {
        do {
            if FileManager.default.fileExists(atPath: file.path) { try backup(file) }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .withoutEscapingSlashes])
            data.append(0x0A)
            try data.write(to: file, options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private static func backup(_ file: URL) throws {
        // (never over an earlier backup: one made in the same second gets a number)
        var path = file.path + ".bak-fishbots-" + stamp(), n = 2
        while FileManager.default.fileExists(atPath: path) { path = file.path + ".bak-fishbots-" + stamp() + "-\(n)"; n += 1 }
        try FileManager.default.copyItem(atPath: file.path, toPath: path)
    }

    /// Claude Code / Codex: {"hooks": [{"command"}]}; Cursor: {"command"}.
    private static func commands(_ entry: [String: Any]) -> [String] {
        (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } + [entry["command"] as? String].compactMap { $0 }
    }

    /// The same script from any clone or from the app counts as one.
    private static func key(_ command: String, _ agent: String) -> String {
        command.range(of: "/plugins/\(agent)/").map { String(command[$0.lowerBound...]) } ?? command
    }

    static func isOurs(command: String, agent: String, only names: [String] = ["hook", "permission"]) -> Bool {
        names.contains { name in
            guard let r = command.range(of: "/plugins/\(agent)/\(name).sh") else { return false }
            return r.upperBound == command.endIndex || command[r.upperBound].isWhitespace
        }
    }

    private static func isOurs(link: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))?.hasSuffix("/plugins/opencode/fishbots.js") ?? false
    }

    /// The settings without Fishbots' hooks (or only some of them), and how many came out. Claude Code, Codex and
    /// Gemini nest them (`{"hooks": {event: [{"hooks": [{"command"}]}]}}`), Cursor lists the command itself,
    /// Antigravity keys them by name.
    static func strip(_ obj: [String: Any], agent: String, only names: [String] = ["hook", "permission"]) -> (settings: [String: Any], removed: Int) {
        var out = obj, removed = 0
        if agent == "antigravity", names.contains("hook"), out["fishbots"] != nil { out["fishbots"] = nil; removed += 1 }
        guard var hooks = out["hooks"] as? [String: Any] else { return (out, removed) }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for var e in entries {
                if let c = e["command"] as? String, isOurs(command: c, agent: agent, only: names) { removed += 1; continue }
                if let inner = e["hooks"] as? [[String: Any]] {
                    let left = inner.filter { !isOurs(command: $0["command"] as? String ?? "", agent: agent, only: names) }
                    removed += inner.count - left.count
                    if left.isEmpty { continue }
                    e["hooks"] = left
                }
                kept.append(e)
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        out["hooks"] = hooks
        return (out, removed)
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private static func tilde(_ u: URL) -> String { u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}
