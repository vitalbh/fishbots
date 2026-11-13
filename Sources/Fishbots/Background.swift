import Foundation

/// A session with no terminal at all: the aquarium runs the agent itself, in the background, through the same
/// brains the resident assistant thinks with (Brains.swift). Its hooks fire like any session's, so it's a fish like
/// the others (states, tools, its card, the last reply); what a terminal would do for it the aquarium does:
/// what you write on its card goes to the agent's input, Esc interrupts it, and what it asks leave for comes
/// through its stream and is asked on its card. It lives while the app is open.
final class BackgroundSession {
    /// The aquarium's name for it (its place: `whereabouts["background"]`).
    let id: String
    let agent: String
    let cwd: String
    let model: String?
    let environment: [String: String]
    fileprivate let brain: Brain
    /// The agent's own id for the conversation, once it says it (its fish is `agent:session`).
    fileprivate(set) var session: String?
    /// What it asked leave for and hasn't been answered yet, one at a time on the card.
    fileprivate var asking: [(request: BrainRequest, tries: Int)] = []

    fileprivate init(id: String, agent: String, cwd: String, model: String?, environment: [String: String], brain: Brain) {
        self.id = id
        self.agent = agent
        self.cwd = cwd
        self.model = model
        self.environment = environment
        self.brain = brain
    }
}

enum Background {
    private(set) static var sessions: [String: BackgroundSession] = [:]
    static weak var tank: Tank?
    /// The agent of a background session wants leave for a tool: the app asks the person on its fish's card, as it
    /// does for a permission hook, and answers with the decision's JSON ({"behavior": "allow"|"deny", …}; anything
    /// else: no decision).
    static var askPermission: ((_ session: BackgroundSession, _ request: BrainRequest, _ answer: @escaping ([String: Any]) -> Void) -> Void)?

    /// The background session behind this fish, if it's one.
    static func of(_ f: Fish) -> BackgroundSession? { f.whereabouts["background"].flatMap { sessions[$0] } }

    /// Is this hook event from a background session? (Its permission requests come through its stream: the
    /// permission hook, if the person has it installed, would ask the same thing twice.)
    static func owns(_ body: Data) -> Bool {
        guard !sessions.isEmpty, let o = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let id = o["session_id"] as? String else { return false }
        return sessions.values.contains { $0.session == id }
    }

    /// Starts one with its first task. The session, or what went wrong.
    static func start(agent: String, cwd: String, prompt: String, model: String?, environment: [String: String]) -> Result<BackgroundSession, LaunchError> {
        guard let brain = Brains.fresh(agent) else {
            return .failure(LaunchError(message: "\(agent) can't run without a terminal (Claude Code and Codex can)"))
        }
        let s = BackgroundSession(id: String(UUID().uuidString.prefix(8)).lowercased(), agent: agent, cwd: cwd, model: model,
                                  environment: environment, brain: brain)
        sessions[s.id] = s
        say(s, prompt)
        return .success(s)
    }

    /// Something for the session: its first task, or what the person writes on its card.
    static func say(_ s: BackgroundSession, _ text: String) {
        let setup = BrainSetup(folder: URL(fileURLWithPath: s.cwd), persona: "", model: s.model, session: s.session, environment: s.environment)
        s.brain.ask(text, setup: setup) { [weak s] e in
            guard let s, sessions[s.id] === s else { return }
            switch e {
            case .started(let session, _):
                if let session { s.session = session; place(s, tries: 60) }
            case .permission(let r):
                s.asking.append((r, 0))
                if s.asking.count == 1 { askNext(s) }
            case .failed(let why):
                if let t = tank { t.notice = (tr("sessão em segundo plano: %@", String(why.prefix(120))), t.time) }
            case .done, .text, .tool: break
            }
        }
    }

    /// Its fish is born from its hooks, which can't say where it runs: once it's there, it's put in its place, so
    /// the card writes to it and whoever launched it finds it.
    private static func place(_ s: BackgroundSession, tries: Int) {
        guard sessions[s.id] === s, let session = s.session else { return }
        if let f = tank?.fish.first(where: { $0.id == s.agent + ":" + session && !$0.leaving }) {
            if f.whereabouts["background"] != s.id { Whereabouts.put(f, in: ["term": "background", "background": s.id]) }
        } else if tries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { place(s, tries: tries - 1) }
        }
    }

    /// One request at a time on the card (the app keeps one per session). No decision (the request was let go because
    /// the session moved on with something else): asked again, a couple of times, then it's a no.
    private static func askNext(_ s: BackgroundSession) {
        guard sessions[s.id] === s, let (r, tries) = s.asking.first else { return }
        func answered(_ allow: Bool, _ input: [String: Any]?) {
            s.brain.decide(BrainRequest(id: r.id, tool: r.tool, summary: r.summary, input: input ?? r.input), allow: allow)
            if !s.asking.isEmpty { s.asking.removeFirst() }
            askNext(s)
        }
        guard let ask = askPermission else { answered(false, nil); return }
        ask(s, r) { decision in
            guard sessions[s.id] === s else { return }
            switch decision["behavior"] as? String {
            case "allow": answered(true, decision["updatedInput"] as? [String: Any])
            case "deny": answered(false, nil)
            default:
                if tries >= 2 { answered(false, nil); return }
                if !s.asking.isEmpty { s.asking[0].tries = tries + 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { askNext(s) }
            }
        }
    }

    static func interrupt(_ s: BackgroundSession) { s.brain.interrupt() }

    /// Ends it: its agent goes, whatever it's doing.
    static func end(_ id: String) {
        guard let s = sessions.removeValue(forKey: id) else { return }
        s.brain.sleep()
    }

    static func endAll() { for id in Array(sessions.keys) { end(id) } }
}

/// The launcher of last resort (Launchers.swift): no terminal to open a pane in, so the session runs in the
/// background. It needs a task to start with (there's no prompt to wait at), and an agent with a brain.
final class BackgroundLauncher: SessionLauncher {
    let id = "background"
    var name: String { tr("Segundo plano (sem terminal)") }
    var available: Bool { true }

    func hosts(_ o: [String: String]) -> Bool { o["background"] != nil }

    func launch(_ r: LaunchRequest, done: @escaping (Result<[String: String], LaunchError>) -> Void) {
        guard let prompt = r.prompt, !prompt.isEmpty else {
            done(.failure(LaunchError(message: "a session with no terminal needs a task to start with (and none of Rex, Herdr, iTerm or tmux is here to open one in)"))); return
        }
        switch Background.start(agent: r.agent, cwd: r.cwd, prompt: prompt, model: r.model, environment: r.env) {
        case .failure(let e): done(.failure(e))
        case .success(let s): done(.success(["term": "background", "background": s.id]))
        }
    }

    func close(_ place: [String: String], done: @escaping (String?) -> Void) {
        guard let id = place["background"] else { done("no background session to end"); return }
        Background.end(id)
        done(nil)
    }
}
