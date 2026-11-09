import Foundation

/// Cursor's agent (the app and cursor-agent): hooks posted to /cursor (plugins/cursor/hook.sh).
/// Its hook JSON is close to Claude Code's (`session_id`, `tool_name`, `tool_input`), with camelCase event names,
/// `workspace_roots` instead of `cwd`, no transcript, and the last reply in its own event (`afterAgentResponse`).
/// So it's translated to Claude Code's shape and handed to `ClaudeCodeHook`.
final class CursorProvider: TerminalAgentProvider, SessionProvider {
    let id = "cursor"
    let name = "Cursor"
    let profile = SourceProfile(isAgent: true, timbre: .pluck, fishKind: { _ in "angelfish" })
    let routes = ["/cursor"]
    let processNames = ["cursor-agent"]

    /// The last reply of each session, kept from `afterAgentResponse` until its `stop`.
    private var lastReply: [String: String] = [:]

    /// Cursor event → Claude Code event. A failed tool isn't a sick fish (the agent usually just tries again).
    /// Events not listed (thoughts, file reads, shell/MCP before/after, which
    /// `preToolUse` already covers) don't change anything.
    private static let events: [String: String] = [
        "sessionStart": "SessionStart", "sessionEnd": "SessionEnd", "beforeSubmitPrompt": "UserPromptSubmit",
        "preToolUse": "PreToolUse", "postToolUse": "PostToolUse", "postToolUseFailure": "PostToolUse",
        "subagentStop": "SubagentStop", "preCompact": "PreCompact", "stop": "Stop",
    ]

    override init() {
        super.init()
        // Cursor's own tool names, next to Claude Code's built-in ones
        ToolBehaviors.register(ToolBehavior(tools: ["Shell"], animation: .bubbles, label: { _ in "⌨︎ Shell" }))
        ToolBehaviors.register(ToolBehavior(tools: ["StrReplace", "Delete", "EditNotebook"], animation: .nibble,
                                            label: { "✏️ " + $0 }, timbre: .bell))
    }

    func handle(route: String, body: Data, headers: [String: String], tank: Tank) -> (Int, Data) {
        guard var m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let event = m["hook_event_name"] as? String else {
            return (400, Data(#"{"error":"expected the JSON of a Cursor hook"}"#.utf8))
        }
        let session = (m["session_id"] as? String) ?? (m["conversation_id"] as? String) ?? ""
        guard !session.isEmpty else { return (400, Data(#"{"error":"no session_id"}"#.utf8)) }
        m["session_id"] = session
        if m["cwd"] == nil, let root = (m["workspace_roots"] as? [String])?.first { m["cwd"] = root }
        m.removeValue(forKey: "transcript_path")   // null today; Cursor's transcript format isn't read

        switch event {
        case "afterAgentResponse":
            if let t = m["text"] as? String, !t.isEmpty { lastReply[session] = t }
            return (200, Data(#"{"ok":true}"#.utf8))
        case "subagentStart":
            // a subagent: a fry, the same as Claude Code's Task tool
            m["hook_event_name"] = "PreToolUse"
            m["tool_name"] = "Task"
        case "stop":
            m["hook_event_name"] = "Stop"
            let status = (m["status"] as? String) ?? "completed"
            if status == "error" { m["hook_event_name"] = "StopFailure" }
            else if status == "aborted" { m["hook_event_name"] = "Notification"; m["message"] = "waiting for your input" }
            else if let r = lastReply[session] { m["last_assistant_message"] = r }
            lastReply[session] = nil
        case "sessionEnd":
            lastReply[session] = nil
            m["hook_event_name"] = "SessionEnd"
        default:
            guard let e = Self.events[event] else { return (200, Data(#"{"ok":true,"ignored":"event"}"#.utf8)) }
            m["hook_event_name"] = e
        }
        guard let d = try? JSONSerialization.data(withJSONObject: m) else { return (400, Data()) }
        return ClaudeCodeHook.apply(d, headers: headers, at: tank, source: id, defaultLabel: "cursor")
    }

    /// Typing only works for cursor-agent in Rex, iTerm or tmux; the app's chat has no terminal to type into.
    func capabilities(_ f: Fish) -> Set<Capability> { terminalCapabilities(f) }
}
