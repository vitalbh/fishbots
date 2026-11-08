import Foundation

/// What can be done with a session from the aquarium.
enum Capability {
    case reply        // type a line into the session
    case stop         // Esc: interrupt what the agent is doing
    case renameChat   // rename the conversation
}

/// A kind of session the aquarium understands (Claude Code, Codex…): how its events arrive, what its fish are like
/// and what you can do with it. The card, the fish menu and the server only talk to this protocol, so a new agent
/// is one more provider. See docs/extensions.md.
protocol SessionProvider: AnyObject {
    /// The protocol `source` of its fish ("claude-code", "codex"…).
    var id: String { get }
    var profile: SourceProfile { get }
    /// HTTP routes it answers (POST), e.g. "/claude-code".
    var routes: [String] { get }
    /// Answers permission requests at "<route>/permission".
    var handlesPermissions: Bool { get }
    /// Words in the agent's process (path or argv, lowercased) that tell it's really this agent: in the Rex pane
    /// before typing into it, and on reopening the app, to know whether the session is still alive.
    var processNames: [String] { get }
    func handle(route: String, body: Data, headers: [String: String], tank: Tank) -> (Int, Data)
    /// What can be done with this fish right now.
    func capabilities(_ f: Fish) -> Set<Capability>
    /// Sends a reply; `done` gets an error message, or nil.
    func reply(_ f: Fish, _ text: String, done: @escaping (String?) -> Void)
    func stop(_ f: Fish)
    func renameChat(_ f: Fish, _ name: String, done: @escaping (String?) -> Void)
}

extension SessionProvider {
    var routes: [String] { [] }
    var handlesPermissions: Bool { false }
    var processNames: [String] { [] }
    func handle(route: String, body: Data, headers: [String: String], tank: Tank) -> (Int, Data) {
        (404, Data(#"{"error":"unknown route"}"#.utf8))
    }
    func capabilities(_ f: Fish) -> Set<Capability> { [] }
    func reply(_ f: Fish, _ text: String, done: @escaping (String?) -> Void) { done(tr("não sei responder essa sessão")) }
    func stop(_ f: Fish) {}
    func renameChat(_ f: Fish, _ name: String, done: @escaping (String?) -> Void) { done(tr("não sei renomear essa conversa")) }
}

/// The registry of session providers.
enum Providers {
    private(set) static var all: [String: SessionProvider] = [:]

    static func register(_ p: SessionProvider) { all[p.id] = p }

    static func of(_ source: String) -> SessionProvider? { all[source] }

    static func profile(_ source: String) -> SourceProfile { all[source]?.profile ?? SourceProfile() }

    /// Re-reads the profile (the shape can change when we learn where the session runs).
    static func refresh(_ f: Fish) { profile(f.source).apply(to: f) }

    /// The process names of this source's agent (read on the main thread; pass them along to background checks).
    static func processNames(_ source: String) -> [String] { all[source]?.processNames ?? [] }

    /// Is this process text (path, argv…) one of these agents?
    static func isAgentProcess(_ text: String, names: [String]) -> Bool {
        let t = text.lowercased()
        return names.contains { t.contains($0.lowercased()) }
    }

    /// Every POST route, for GET /.
    static var allRoutes: [String] {
        all.values.flatMap { p in p.routes + (p.handlesPermissions ? p.routes.map { $0 + "/permission" } : []) }.sorted()
    }

    /// The provider that answers this route, or its permission route.
    static func route(_ path: String) -> (SessionProvider, permission: Bool)? {
        for p in all.values {
            for r in p.routes {
                if path == r { return (p, false) }
                // "/permissao" is the route's old (Portuguese) name
                if p.handlesPermissions, path == r + "/permission" || path == r + "/permissao" { return (p, true) }
            }
        }
        // /agent/<id>: an agent without Swift, with or without a manifest
        return AgentManifests.provider(forRoute: path).map { ($0, false) }
    }

    static func registerBuiltIns() {
        register(ClaudeCodeProvider())
        register(CodexProvider())
        register(CursorProvider())
        register(GeminiProvider())
        register(AntigravityProvider())
        register(DemoProvider())
        // script plugins and other sources that only need a look and a sound
        register(PlainSource(id: "github", profile: SourceProfile(timbre: .bell, fishKind: { _ in "octopus" })))
        register(PlainSource(id: "ci", profile: SourceProfile(timbre: .bell)))
        register(PlainSource(id: "mac", profile: SourceProfile(timbre: .bass)))
        // what Spotify or the Music app is playing (NowPlaying.swift)
        register(PlainSource(id: NowPlaying.source, profile: SourceProfile(timbre: .soft, fishKind: { _ in "betta" }, sings: true)))
    }
}

/// A source with nothing but a look (plugins, `POST /event`).
final class PlainSource: SessionProvider {
    let id: String
    let profile: SourceProfile
    init(id: String, profile: SourceProfile) { self.id = id; self.profile = profile }
}

/// Agents that run in a terminal and are driven by typing into it (Rex, iTerm or tmux; see Whereabouts).
class TerminalAgentProvider {
    /// Fish kind by the app the session runs in: oval (Rex), slender (plain terminal), puffer (the Claude desktop
    /// app and ClaudeCode.app background sessions), angelfish (editors: VS Code and its forks, Zed).
    static func fishKind(_ f: Fish) -> String {
        let term = f.whereabouts["term"] ?? ""
        let app = (f.whereabouts["app"] ?? "").lowercased()
        if term == "rex" { return "oval" }
        if f.whereabouts["entrypoint"] == "claude-desktop" { return "puffer" }
        if term == "vscode" || term == "zed" || ["cursor", "visual studio code", "windsurf", "zed"].contains(where: app.contains) { return "angelfish" }
        if ["iTerm.app", "Apple_Terminal", "ghostty", "WezTerm", "kitty", "tmux", "Alacritty", "Hyper", "WarpTerminal"].contains(term) { return "slender" }
        if app.contains("claude") { return "puffer" }
        return "oval"
    }

    /// Typing is only safe in the exact terminal, with the agent idle at its prompt.
    func atPrompt(_ f: Fish) -> Bool {
        Whereabouts.target(f) != nil && [.waiting, .done, .idle, .ok].contains(f.state) && f.compactingSince == nil
    }

    func terminalCapabilities(_ f: Fish) -> Set<Capability> {
        var c: Set<Capability> = []
        if atPrompt(f) { c.insert(.reply) }
        if Whereabouts.target(f) != nil && f.state == .busy { c.insert(.stop) }
        return c
    }

    func reply(_ f: Fish, _ text: String, done: @escaping (String?) -> Void) { Whereabouts.reply(f, text, ready: done) }
    func stop(_ f: Fish) { Whereabouts.stop(f) }
}

/// Claude Code: hooks posted to /claude-code (plugins/claude-code/hook.sh), the transcript for title and context.
final class ClaudeCodeProvider: TerminalAgentProvider, SessionProvider {
    let id = "claude-code"
    let profile = SourceProfile(isAgent: true, timbre: .pluck, fishKind: TerminalAgentProvider.fishKind)
    let routes = ["/claude-code"]
    let handlesPermissions = true
    let processNames = ["claude"]

    func handle(route: String, body: Data, headers: [String: String], tank: Tank) -> (Int, Data) {
        ClaudeCodeHook.apply(body, headers: headers, at: tank, source: id, defaultLabel: "claude")
    }

    func capabilities(_ f: Fish) -> Set<Capability> {
        var c = terminalCapabilities(f)
        if atPrompt(f) { c.insert(.renameChat) }   // by typing /rename
        return c
    }

    /// Types /rename in the session: Claude renames the conversation itself.
    func renameChat(_ f: Fish, _ name: String, done: @escaping (String?) -> Void) {
        Whereabouts.reply(f, "/rename " + name) { [weak f] error in
            if error == nil { f?.fixedTitle = name }
            done(error)
        }
    }
}

/// Codex: the same hook format at /codex (plugins/codex/hook.sh); its conversation name lives in an index file.
final class CodexProvider: TerminalAgentProvider, SessionProvider {
    let id = "codex"
    let profile = SourceProfile(isAgent: true, timbre: .pluck, prefersLogTitle: true, fishKind: { _ in "stingray" })
    let routes = ["/codex"]
    let handlesPermissions = true
    let processNames = ["codex"]

    func handle(route: String, body: Data, headers: [String: String], tank: Tank) -> (Int, Data) {
        // internal tasks of the ChatGPT app (titles, suggestions…) have no saved conversation: they don't become fish
        ClaudeCodeHook.apply(body, headers: headers, at: tank, source: id, defaultLabel: "codex", requireTranscript: true)
    }

    func capabilities(_ f: Fish) -> Set<Capability> { terminalCapabilities(f).union([.renameChat]) }

    /// Adds a line to Codex's index (~/.codex/session_index.jsonl), which is where the name lives.
    func renameChat(_ f: Fish, _ name: String, done: @escaping (String?) -> Void) {
        let session = String(f.id.dropFirst((id + ":").count))
        if Transcript.renameCodex(session: session, name: name) {
            f.logTitle = name
            f.fixedTitle = nil
            done(nil)
        } else {
            done(tr("não consegui gravar no índice do Codex"))
        }
    }
}

/// Demo mode's fake sessions: look like Claude Code, but there's nothing to type into.
final class DemoProvider: SessionProvider {
    let id = "demo"
    let profile = SourceProfile(isAgent: true, timbre: .pluck, fishKind: TerminalAgentProvider.fishKind)
}
