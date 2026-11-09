import AppKit

/// Agents without Swift: any agent whose hook (or plugin) posts Claude Code-shaped events to `POST /agent/<id>`
/// becomes a full agent fish: tool animations, fry for subagents, the card with its last reply, where it runs, and
/// reply/Esc in the exact terminal (Rex, Herdr, Ghostty, iTerm, tmux) after checking the agent is in front.
///
/// A manifest is optional; without one, `<id>` is also the process name and the fish follows the terminal. With one,
/// in ~/Library/Application Support/Fishbots/agents/<id>.json (read when the app opens and on Preferences → Agents →
/// Recarregar or POST /agents/reload; not in packs, which are only the aquarium's look):
///
///   {"id": "aider", "name": "Aider",
///    "processNames": ["aider"],              // words in the agent's process (to type into it safely)
///    "fish": "slender",                      // a fish kind id (packs can add kinds); default: by the terminal
///    "timbre": "pluck",                      // pluck, bell, pad, bass, glass, bubble, soft, rhodes, flute, kalimba
///    "events": {"BeforeAgent": "UserPromptSubmit"},   // its event names → Claude Code's (unlisted ones pass as-is)
///    "tools": {"run_command": "Bash"}}       // its tool names → Claude Code's, for the animations
///
/// The events it understands are Claude Code's: SessionStart, UserPromptSubmit, PreToolUse (`tool_name`,
/// `tool_input`), PostToolUse, Notification (`message`: "permission…" → waiting), Stop (`last_assistant_message`),
/// StopFailure, PreCompact, SubagentStop, SessionEnd; plus `session_id`, `cwd` and an optional `session_title`.
/// Where it runs comes in the X-Where-* headers (plugins/common/hook.sh sends them). See docs/extensions.md.
final class ManifestAgent: TerminalAgentProvider, SessionProvider {
    let id: String
    let name: String
    let profile: SourceProfile
    let routes: [String]
    let processNames: [String]
    private let events: [String: String]
    private let tools: [String: String]

    init(id: String, json: [String: Any] = [:]) {
        self.id = id
        name = json["name"] as? String ?? id
        routes = ["/agent/" + id]
        processNames = (json["processNames"] as? [String]).flatMap { $0.isEmpty ? nil : $0 } ?? [id]
        events = json["events"] as? [String: String] ?? [:]
        tools = json["tools"] as? [String: String] ?? [:]
        let kind = json["fish"] as? String
        // the title its events send (session_title) wins over the terminal's
        profile = SourceProfile(isAgent: true, timbre: (json["timbre"] as? String).flatMap { AgentManifests.timbres[$0] } ?? .pluck,
                                prefersLogTitle: true,
                                fishKind: kind.map { k in { _ in k } } ?? TerminalAgentProvider.fishKind)
    }

    func handle(route: String, body: Data, headers: [String: String], tank: Tank) -> (Int, Data) {
        guard var m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let event = m["hook_event_name"] as? String else {
            return (400, Data(#"{"error":"expected a JSON object with hook_event_name (Claude Code's hook shape)"}"#.utf8))
        }
        m["hook_event_name"] = events[event] ?? event
        if let t = m["tool_name"] as? String, let mapped = tools[t] { m["tool_name"] = mapped }
        m.removeValue(forKey: "transcript_path")   // only Claude Code's and Codex's conversation files are read
        guard let d = try? JSONSerialization.data(withJSONObject: m) else { return (400, Data()) }
        return ClaudeCodeHook.apply(d, headers: headers, at: tank, source: id, defaultLabel: id)
    }

    func capabilities(_ f: Fish) -> Set<Capability> { terminalCapabilities(f) }
}

/// Loads agent manifests and answers `/agent/<id>` for agents without one.
enum AgentManifests {
    static let timbres: [String: Timbre] = [
        "pluck": .pluck, "bell": .bell, "pad": .pad, "bass": .bass, "glass": .glass, "bubble": .bubble,
        "soft": .soft, "rhodes": .rhodes, "flute": .flute, "kalimba": .kalimba,
    ]

    /// Manifests that failed to load (Preferences → General → Agents).
    private(set) static var problems: [String] = []
    /// The agents that came from a manifest file, by id → its name.
    private(set) static var loaded: [String: String] = [:]

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fishbots/agents", isDirectory: true)
    }

    /// Lowercase letters, digits and dashes: it's a route and a fish's source.
    static func validID(_ s: String) -> Bool { s.range(of: #"^[a-z0-9][a-z0-9-]{0,39}$"#, options: .regularExpression) != nil }

    /// Registers a manifest; returns why it couldn't, or nil. Built-in agents can't be replaced.
    @discardableResult
    static func register(_ json: [String: Any]) -> String? {
        guard let id = json["id"] as? String, validID(id) else {
            return tr("agente sem \"id\" válido (letras minúsculas, números e -)")
        }
        if let p = Providers.of(id), !(p is ManifestAgent) { return tr("%@: já é um agente do app", id) }
        let agent = ManifestAgent(id: id, json: json)
        Providers.register(agent)
        loaded[id] = agent.name
        return nil
    }

    /// Reads ~/Library/Application Support/Fishbots/agents/*.json (each one manifest). An agent whose manifest is gone
    /// goes back to the defaults (its fish keep working); `fish` get their look again (kind, timbre).
    static func load(fish: [Fish] = []) {
        let before = Set(loaded.keys)
        problems = []
        loaded = [:]
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for f in files {
            guard let d = try? Data(contentsOf: f), let json = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
                problems.append(tr("%@: JSON inválido", f.lastPathComponent))
                continue
            }
            if let e = register(json) { problems.append(f.lastPathComponent + ": " + e) }
        }
        for id in before.subtracting(loaded.keys) { Providers.register(ManifestAgent(id: id)) }
        for f in fish where Providers.of(f.source) is ManifestAgent { Providers.refresh(f) }
    }

    /// Every agent the aquarium understands: built in (Swift), and through /agent/<id> (with a manifest, or without
    /// one once it has sent an event). For Preferences → Agents and GET /agents.
    static var builtIn: [SessionProvider] {
        Providers.all.values.filter { $0.profile.isAgent && !($0 is ManifestAgent) && $0.id != "demo" }.sorted { $0.name < $1.name }
    }
    static var viaRoute: [(id: String, name: String, manifest: Bool)] {
        Providers.all.values.compactMap { $0 as? ManifestAgent }
            .map { ($0.id, $0.name, loaded[$0.id] != nil) }
            .sorted { $0.name < $1.name }
    }

    static var json: [String: Any] {
        ["builtIn": builtIn.map { ["id": $0.id, "name": $0.name] },
         "agents": viaRoute.map { ["id": $0.id, "name": $0.name, "route": "/agent/" + $0.id, "manifest": $0.manifest] },
         "problems": problems, "folder": folder.path]
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// The agent for `/agent/<id>`: its manifest's, or one with the defaults (registered on first use).
    static func provider(forRoute path: String) -> SessionProvider? {
        guard path.hasPrefix("/agent/") else { return nil }
        let id = String(path.dropFirst("/agent/".count))
        guard validID(id) else { return nil }
        if let p = Providers.of(id) { return p is ManifestAgent ? p : nil }
        let p = ManifestAgent(id: id)
        Providers.register(p)
        return p
    }
}
