import Foundation

/// The hooks Fishbots put in each agent's settings (scripts/install-hooks.sh), taken out again: the button in
/// Preferences, for whoever is leaving the aquarium. Once the clone is gone those hooks would run a script that isn't
/// there on every prompt and tool. scripts/uninstall.sh does the same from the terminal (install-hooks.sh --remove).
///
/// A hook is Fishbots' when it runs …/plugins/<agent>/hook.sh or permission.sh (permissao.sh before), from any clone.
/// Every file it changes gets a backup next to it first (.bak-fishbots-…).
enum AgentHooks {
    struct Place {
        let agent: String
        let file: URL
    }

    /// Where each agent keeps its hooks; Claude Code also in each folder CLAUDE_CONFIG_DIR may point at (~/.claude-*).
    static var places: [Place] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let claude = ((try? FileManager.default.contentsOfDirectory(atPath: home.path)) ?? [])
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }.sorted()
            .map { Place(agent: "claude-code", file: home.appendingPathComponent($0).appendingPathComponent("settings.json")) }
        return claude + [Place(agent: "codex", file: home.appendingPathComponent(".codex/hooks.json")),
                         Place(agent: "cursor", file: home.appendingPathComponent(".cursor/hooks.json")),
                         Place(agent: "antigravity", file: home.appendingPathComponent(".gemini/config/hooks.json")),
                         Place(agent: "gemini", file: home.appendingPathComponent(".gemini/settings.json"))]
    }

    static var opencodeLink: URL { URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/opencode/plugins/fishbots.js") }

    /// The files that have Fishbots' hooks now.
    static func connected() -> [URL] {
        places.filter { p in load(p.file).map { strip($0, agent: p.agent).removed > 0 } ?? false }.map(\.file)
            + (isOurs(link: opencodeLink) ? [opencodeLink] : [])
    }

    /// Takes them out; one line per file it changed (or couldn't).
    @discardableResult
    static func disconnect() -> [String] {
        var report: [String] = []
        for p in places {
            guard let obj = load(p.file) else { continue }
            let (clean, removed) = strip(obj, agent: p.agent)
            guard removed > 0 else { continue }
            do {
                // (never over an earlier backup: one made in the same second gets a number)
                var backup = p.file.path + ".bak-fishbots-" + stamp(), n = 2
                while FileManager.default.fileExists(atPath: backup) { backup = p.file.path + ".bak-fishbots-" + stamp() + "-\(n)"; n += 1 }
                try FileManager.default.copyItem(atPath: p.file.path, toPath: backup)
                var data = try JSONSerialization.data(withJSONObject: clean, options: [.prettyPrinted, .withoutEscapingSlashes])
                data.append(0x0A)
                try data.write(to: p.file, options: .atomic)
                report.append(String(format: tr("%@: %d hook(s) removidos"), tilde(p.file), removed))
            } catch {
                report.append(String(format: tr("%@: não consegui mudar (%@)"), tilde(p.file), error.localizedDescription))
            }
        }
        if isOurs(link: opencodeLink) {
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

    static func isOurs(command: String, agent: String) -> Bool {
        ["hook", "permission", "permissao"].contains { name in
            guard let r = command.range(of: "/plugins/\(agent)/\(name).sh") else { return false }
            return r.upperBound == command.endIndex || command[r.upperBound].isWhitespace
        }
    }

    private static func isOurs(link: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path))?.hasSuffix("/plugins/opencode/fishbots.js") ?? false
    }

    /// The settings without Fishbots' hooks, and how many came out. Claude Code, Codex and Gemini nest them
    /// (`{"hooks": {event: [{"hooks": [{"command"}]}]}}`), Cursor lists the command itself, Antigravity keys them by name.
    static func strip(_ obj: [String: Any], agent: String) -> (settings: [String: Any], removed: Int) {
        var out = obj, removed = 0
        if agent == "antigravity", out["fishbots"] != nil { out["fishbots"] = nil; removed += 1 }
        guard var hooks = out["hooks"] as? [String: Any] else { return (out, removed) }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            var kept: [[String: Any]] = []
            for var e in entries {
                if let c = e["command"] as? String, isOurs(command: c, agent: agent) { removed += 1; continue }
                if let inner = e["hooks"] as? [[String: Any]] {
                    let left = inner.filter { !isOurs(command: $0["command"] as? String ?? "", agent: agent) }
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
