import Foundation

/// Gemini CLI: hooks posted to /gemini (plugins/gemini/hook.sh), from `hooks` in ~/.gemini/settings.json.
/// Its hook JSON has Claude Code's common fields (`session_id`, `cwd`, `hook_event_name`, `tool_name`, `tool_input`)
/// with its own event and tool names, and the reply in `AfterAgent`'s `prompt_response`. So it's translated to
/// Claude Code's shape and handed to `ClaudeCodeHook`. Written from Gemini CLI's hook reference, not yet tried on a
/// real session.
final class GeminiProvider: TerminalAgentProvider, SessionProvider {
    let id = "gemini"
    let profile = SourceProfile(isAgent: true, timbre: .pluck, fishKind: TerminalAgentProvider.fishKind)
    let routes = ["/gemini"]
    let processNames = ["gemini"]

    /// Gemini event → Claude Code event. Model and tool-selection events change nothing.
    private static let events: [String: String] = [
        "SessionStart": "SessionStart", "SessionEnd": "SessionEnd", "BeforeAgent": "UserPromptSubmit",
        "AfterAgent": "Stop", "BeforeTool": "PreToolUse", "AfterTool": "PostToolUse",
        "Notification": "Notification", "PreCompress": "PreCompact",
    ]

    /// Gemini's built-in tools → Claude Code's, so they animate the same way (shell: bubbles, edits: nibbling…).
    private static let tools: [String: String] = [
        "run_shell_command": "Bash", "write_file": "Write", "replace": "Edit", "read_file": "Read",
        "read_many_files": "Read", "glob": "Glob", "search_file_content": "Grep", "grep_search": "Grep",
        "list_directory": "LS", "web_fetch": "WebFetch", "google_web_search": "WebSearch",
        "write_todos": "TodoWrite", "ask_user": "AskUserQuestion",
    ]

    func handle(route: String, body: Data, headers: [String: String], tank: Tank) -> (Int, Data) {
        guard var m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let event = m["hook_event_name"] as? String else {
            return (400, Data(#"{"error":"expected the JSON of a Gemini CLI hook"}"#.utf8))
        }
        guard let e = Self.events[event] else { return (200, Data(#"{"ok":true,"ignored":"event"}"#.utf8)) }
        m["hook_event_name"] = e
        m.removeValue(forKey: "transcript_path")   // Gemini's conversation file isn't Claude Code's format
        if let t = m["tool_name"] as? String, let mapped = Self.tools[t] { m["tool_name"] = mapped }
        switch event {
        case "AfterAgent":
            if let r = m["prompt_response"] as? String, !r.isEmpty { m["last_assistant_message"] = r }
        case "Notification":
            // today its only kind is ToolPermission: the session waits for you to allow a tool
            if (m["notification_type"] as? String) == "ToolPermission" {
                m["message"] = "permission: " + ((m["message"] as? String) ?? "")
            }
        default: break
        }
        guard let d = try? JSONSerialization.data(withJSONObject: m) else { return (400, Data()) }
        return ClaudeCodeHook.apply(d, headers: headers, at: tank, source: id, defaultLabel: "gemini")
    }

    /// Typing works in the exact terminal (Rex, Herdr, Ghostty, iTerm or tmux) when its foreground process is
    /// recognizable as Gemini (it runs on node, so not always).
    func capabilities(_ f: Fish) -> Set<Capability> { terminalCapabilities(f) }
}

/// Antigravity (Google's successor to Gemini CLI: the CLI `agy`, its IDE and app): hooks posted to /antigravity
/// (plugins/antigravity/hook.sh, in ~/.gemini/config/hooks.json). The payload is camelCase and doesn't name its event,
/// so the hook adds `hookEvent`. No PreToolUse (there a hook must decide, and a failure blocks the tool): tools
/// animate from PostToolUse. There are no permission events, so the fish can't show it's waiting for you, and the
/// reply isn't in any event (only in an undocumented transcript). Written from Antigravity's hook docs, not yet tried.
final class AntigravityProvider: TerminalAgentProvider, SessionProvider {
    let id = "antigravity"
    let profile = SourceProfile(isAgent: true, timbre: .pluck, prefersLogTitle: true, fishKind: TerminalAgentProvider.fishKind)
    let routes = ["/antigravity"]
    let processNames = ["agy", "antigravity"]

    /// Antigravity's tools → Claude Code's, so they animate the same way.
    private static let tools: [String: String] = [
        "run_command": "Bash", "view_file": "Read", "write_to_file": "Write", "replace_file_content": "Edit",
        "multi_replace_file_content": "MultiEdit", "grep_search": "Grep", "find_by_name": "Glob", "list_dir": "LS",
        "search_web": "WebSearch", "read_url_content": "WebFetch", "invoke_subagent": "Task",
    ]
    /// Conversations that already have a title (their first prompt).
    private var titled = Set<String>()

    func handle(route: String, body: Data, headers: [String: String], tank: Tank) -> (Int, Data) {
        guard let a = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let event = a["hookEvent"] as? String, let session = a["conversationId"] as? String, !session.isEmpty else {
            return (400, Data(#"{"error":"expected an Antigravity hook payload with hookEvent"}"#.utf8))
        }
        let call = a["toolCall"] as? [String: Any]
        let args = call?["args"] as? [String: Any] ?? [:]
        var m: [String: Any] = ["session_id": session]
        if let cwd = (a["workspacePaths"] as? [String])?.first ?? args["Cwd"] as? String { m["cwd"] = cwd }

        switch event {
        case "SessionStart":
            m["hook_event_name"] = "SessionStart"
        case "PreInvocation":
            m["hook_event_name"] = "UserPromptSubmit"
            // until the transcript can be read, the conversation is named by its first prompt
            if !titled.contains(session), let p = a["lastUserInput"] as? String, !p.isEmpty {
                titled.insert(session)
                m["session_title"] = String(p.prefix(80))
            }
        case "PostToolUse":
            // also fires for steps that aren't tools (toolCall null): nothing to show
            guard let name = call?["name"] as? String else { return (200, Data(#"{"ok":true,"ignored":"step"}"#.utf8)) }
            m["hook_event_name"] = "PreToolUse"   // the animation, a moment after the tool ran
            m["tool_name"] = Self.tools[name] ?? name
            m["tool_input"] = args
        case "Stop":
            // not fully idle: subagents are still working
            if (a["fullyIdle"] as? Bool) == false { return (200, Data(#"{"ok":true,"ignored":"not idle"}"#.utf8)) }
            let failed = !((a["error"] as? String) ?? "").isEmpty
            m["hook_event_name"] = failed ? "StopFailure" : "Stop"
        default:
            return (200, Data(#"{"ok":true,"ignored":"event"}"#.utf8))
        }
        guard let d = try? JSONSerialization.data(withJSONObject: m) else { return (400, Data()) }
        return ClaudeCodeHook.apply(d, headers: headers, at: tank, source: id, defaultLabel: "antigravity")
    }

    func capabilities(_ f: Fish) -> Set<Capability> { terminalCapabilities(f) }
}
