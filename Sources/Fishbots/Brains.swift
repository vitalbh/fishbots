import Foundation

/// A tool the brain wants to use and may not on its own: the card asks the person.
struct BrainRequest {
    let id: String
    let tool: String
    /// What it would do, in a line (the command, the file…).
    let summary: String
    let input: [String: Any]
}

/// What a brain says while it answers (always on the main thread).
enum BrainEvent {
    /// The conversation it's in (to go on with later) and the model answering.
    case started(session: String?, model: String?)
    /// More of the answer.
    case text(String)
    /// It's using a tool: its name and what with.
    case tool(String, String)
    case permission(BrainRequest)
    /// The turn is over; the whole answer, if it didn't come in pieces.
    case done(String?)
    case failed(String)
}

struct BrainSetup {
    /// The assistant's own folder: where the brain runs, with its instructions and notes.
    var folder: URL
    /// The instructions, for a brain that doesn't read them from the folder.
    var persona: String
    var model: String?
    /// The conversation to go on with (the id the brain gave it); nil: a new one.
    var session: String?
    var environment: [String: String]
}

/// What thinks for the resident assistant (Assistant.swift). The app has no model in it: a brain is the agent the
/// person already has, run in the background, or any command that takes text and gives text back. A new one is a
/// `Brain` registered in `Brains`. See docs/extensions.md, 12.
protocol Brain: AnyObject {
    var id: String { get }
    var name: String { get }
    /// The agent whose command line it runs (AgentCLIs: binary, parameters, variables), if it's one.
    var agent: String? { get }
    /// Can it run on this Mac? (It may ask the shell where the binary is: not on the main thread.)
    var installed: Bool { get }
    /// Sends `text` and reports through `events` until `.done` or `.failed`. One turn at a time.
    func ask(_ text: String, setup: BrainSetup, events: @escaping (BrainEvent) -> Void)
    /// The answer to a `.permission`.
    func decide(_ request: BrainRequest, allow: Bool)
    /// Stops the turn in flight.
    func interrupt()
    /// Lets go of whatever it keeps running between turns (a sleeping assistant costs nothing).
    func sleep()
    /// The command that goes on with this conversation in a terminal, for the person to take over; nil: it can't.
    func terminalCommand(session: String) -> [String]?
}

extension Brain {
    var agent: String? { nil }
    func decide(_ request: BrainRequest, allow: Bool) {}
    func terminalCommand(session: String) -> [String]? { nil }
}

enum Brains {
    private(set) static var all: [Brain] = [ClaudeBrain(), CodexBrain(), CommandBrain()]

    static func register(_ b: Brain) {
        all.removeAll { $0.id == b.id }
        all.append(b)
    }

    static func of(_ id: String) -> Brain? { all.first { $0.id == id } }

    /// How to make a brain of an agent's own, for a session that runs in the background (Background.swift): each
    /// session has its own process and conversation, apart from the assistant's.
    private(set) static var makers: [String: () -> Brain] = ["claude-code": { ClaudeBrain() }, "codex": { CodexBrain() }]
    static func register(agent: String, maker: @escaping () -> Brain) { makers[agent] = maker }
    static func fresh(_ agent: String) -> Brain? { makers[agent]?() }

    /// What a tool call does, in a line.
    static func summary(_ tool: String, _ input: [String: Any]) -> String {
        if let c = input["command"] as? String { return c }
        if let p = input["file_path"] as? String ?? input["path"] as? String { return (p as NSString).abbreviatingWithTildeInPath }
        if let s = input["skill"] as? String { return s }
        for k in ["query", "pattern", "url", "prompt", "description"] { if let v = input[k] as? String { return v } }
        return input.sorted { $0.key < $1.key }.compactMap { k, v in (v as? String).map { "\(k): \($0)" } }.joined(separator: ", ")
    }
}

/// Lines of JSON from a process's output, handed over one object at a time.
private final class JSONLines {
    private var buffer = Data()
    func feed(_ d: Data, _ each: ([String: Any]) -> Void) {
        buffer.append(d)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            if let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] { each(o) }
        }
    }
}

private func tail(_ s: String, _ n: Int = 300) -> String {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.count > n ? "…" + t.suffix(n) : t
}

/// Claude Code in the background, in its streaming mode: one process kept between turns (the next question is
/// answered in about a second), the answer arriving in pieces, and its permission requests coming through the
/// stream to be answered by the card. Its instructions are the CLAUDE.md in the assistant's folder.
final class ClaudeBrain: Brain {
    let id = "claude-code"
    let name = "Claude Code"
    let agent: String? = "claude-code"
    private let queue = DispatchQueue(label: "fishbots.brain.claude")
    private var process: Process?
    private var input: FileHandle?
    private var startedWith = ""
    private var events: ((BrainEvent) -> Void)?
    private var answering = false
    private var wroteText = false
    private var errors = ""

    var installed: Bool { AgentCLIs.executable("claude-code", usual: "claude") != nil }

    private func emit(_ e: BrainEvent) {
        let events = self.events
        DispatchQueue.main.async { events?(e) }
    }

    func ask(_ text: String, setup: BrainSetup, events: @escaping (BrainEvent) -> Void) {
        queue.async {
            self.events = events
            self.answering = true
            self.wroteText = false
            // another model or folder: another process
            let key = setup.folder.path + "|" + (setup.model ?? "")
            if self.process != nil, key != self.startedWith { self.letGo() }
            if self.process == nil {
                if let why = self.start(setup) { self.answering = false; self.emit(.failed(why)); return }
                self.startedWith = key
            }
            self.send(["type": "user", "message": ["role": "user", "content": text]])
        }
    }

    /// Starts the process; what went wrong, or nil.
    private func start(_ setup: BrainSetup) -> String? {
        guard let bin = AgentCLIs.executable("claude-code", usual: "claude") else { return tr("não achei o Claude Code neste Mac") }
        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                    "--include-partial-messages", "--permission-prompt-tool", "stdio"]
        if let m = setup.model, !m.isEmpty { args += ["--model", m] }
        if let s = setup.session { args += ["--resume", s] }
        args += AgentCLIs.arguments("claude-code")
        let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        p.currentDirectoryURL = setup.folder
        p.environment = AgentCLIs.processEnvironment("claude-code", extra: setup.environment)
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        let lines = JSONLines()
        errors = ""
        stdout.fileHandleForReading.readabilityHandler = { [weak self, weak p] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.queue.async { guard let self, self.process === p else { return }; lines.feed(d) { self.handle($0) } }
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.queue.async { self?.errors += String(data: d, encoding: .utf8) ?? "" }
        }
        p.terminationHandler = { [weak self] p in
            // (after the pipes had a moment to hand over what was left)
            self?.queue.asyncAfter(deadline: .now() + 0.2) {
                guard let self, self.process === p else { return }
                self.process = nil
                self.input = nil
                if self.answering {
                    self.answering = false
                    self.emit(.failed(self.errors.isEmpty ? tr("o agente saiu sem responder") : tail(self.errors)))
                }
            }
        }
        do { try p.run() } catch { return error.localizedDescription }
        process = p
        input = stdin.fileHandleForWriting
        return nil
    }

    private func send(_ o: [String: Any]) {
        guard let input, var d = try? JSONSerialization.data(withJSONObject: o) else { return }
        d.append(0x0A)
        try? input.write(contentsOf: d)
    }

    private func handle(_ o: [String: Any]) {
        switch o["type"] as? String {
        case "system":
            if o["subtype"] as? String == "init" { emit(.started(session: o["session_id"] as? String, model: o["model"] as? String)) }
        case "stream_event":
            // (a subagent's own text isn't the answer)
            guard o["parent_tool_use_id"] is NSNull || o["parent_tool_use_id"] == nil, let e = o["event"] as? [String: Any] else { return }
            if e["type"] as? String == "content_block_start", (e["content_block"] as? [String: Any])?["type"] as? String == "text", wroteText {
                emit(.text("\n\n"))          // what it says after a tool is another paragraph
            } else if e["type"] as? String == "content_block_delta", let d = e["delta"] as? [String: Any],
                      d["type"] as? String == "text_delta", let t = d["text"] as? String, !t.isEmpty {
                wroteText = true
                emit(.text(t))
            }
        case "assistant":
            guard o["parent_tool_use_id"] is NSNull || o["parent_tool_use_id"] == nil,
                  let blocks = (o["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return }
            for b in blocks where b["type"] as? String == "tool_use" {
                let name = b["name"] as? String ?? "?"
                emit(.tool(name, Brains.summary(name, b["input"] as? [String: Any] ?? [:])))
            }
        case "control_request":
            guard let id = o["request_id"] as? String, let r = o["request"] as? [String: Any] else { return }
            if r["subtype"] as? String == "can_use_tool" {
                let tool = r["tool_name"] as? String ?? "?", input = r["input"] as? [String: Any] ?? [:]
                emit(.permission(BrainRequest(id: id, tool: tool, summary: Brains.summary(tool, input), input: input)))
            } else {
                // something this host doesn't do: say so, or the agent waits for ever
                send(["type": "control_response", "response": ["subtype": "error", "request_id": id, "error": "not supported by this host"]])
            }
        case "result":
            answering = false
            let text = o["result"] as? String
            if o["is_error"] as? Bool == true { emit(.failed(text.map { tail($0) } ?? (o["subtype"] as? String ?? "error"))) }
            else { emit(.done(wroteText ? nil : text)) }
        default: break
        }
    }

    func decide(_ request: BrainRequest, allow: Bool) {
        queue.async {
            let answer: [String: Any] = allow ? ["behavior": "allow", "updatedInput": request.input]
                                              : ["behavior": "deny", "message": "The person said no to this in the aquarium's card."]
            self.send(["type": "control_response", "response": ["subtype": "success", "request_id": request.id, "response": answer]])
        }
    }

    func interrupt() {
        queue.async {
            guard self.answering else { return }
            self.send(["type": "control_request", "request_id": UUID().uuidString, "request": ["subtype": "interrupt"]])
        }
    }

    private func letGo() {
        answering = false
        let p = process
        process = nil
        try? input?.close()
        input = nil
        p?.terminate()
    }

    func sleep() { queue.async { self.letGo() } }

    func terminalCommand(session: String) -> [String]? { AgentCLIs.launch("claude-code", ["claude", "--resume", session]) }
}

/// Codex in the background (`codex exec --json`): one run per turn, the conversation resumed by its id. It has no
/// one to ask in this mode: it works inside its sandbox (its own folder, with the network, for the `fishbots`
/// command) and what the sandbox refuses is refused. Its instructions are the AGENTS.md in the assistant's folder.
final class CodexBrain: Brain {
    let id = "codex"
    let name = "Codex"
    let agent: String? = "codex"
    private let queue = DispatchQueue(label: "fishbots.brain.codex")
    private var process: Process?

    var installed: Bool { AgentCLIs.executable("codex", usual: "codex") != nil }

    func ask(_ text: String, setup: BrainSetup, events: @escaping (BrainEvent) -> Void) {
        queue.async {
            func emit(_ e: BrainEvent) { DispatchQueue.main.async { events(e) } }
            guard let bin = AgentCLIs.executable("codex", usual: "codex") else { emit(.failed(tr("não achei o Codex neste Mac"))); return }
            var args = ["exec"] + (setup.session != nil ? ["resume"] : [])
            args += ["--json", "--skip-git-repo-check", "-c", #"sandbox_mode="workspace-write""#, "-c", "sandbox_workspace_write.network_access=true"]
            if let m = setup.model, !m.isEmpty { args += ["-m", m] }
            args += AgentCLIs.arguments("codex")
            if let s = setup.session { args.append(s) }
            args.append("-")                      // the prompt comes on stdin
            let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = args
            p.currentDirectoryURL = setup.folder
            p.environment = AgentCLIs.processEnvironment("codex", extra: setup.environment)
            p.standardInput = stdin
            p.standardOutput = stdout
            p.standardError = stderr
            do { try p.run() } catch { emit(.failed(error.localizedDescription)); return }
            self.process = p
            try? stdin.fileHandleForWriting.write(contentsOf: Data(text.utf8))
            try? stdin.fileHandleForWriting.close()
            var errors = Data()
            let errorsRead = DispatchGroup()
            errorsRead.enter()
            DispatchQueue.global().async { errors = stderr.fileHandleForReading.readDataToEndOfFile(); errorsRead.leave() }
            let lines = JSONLines()
            var answer: [String] = [], failure: String?, finished = false
            while true {
                let d = stdout.fileHandleForReading.availableData
                if d.isEmpty { break }
                lines.feed(d) { o in
                    let item = o["item"] as? [String: Any] ?? [:]
                    switch o["type"] as? String {
                    case "thread.started": emit(.started(session: o["thread_id"] as? String, model: setup.model))
                    case "item.started":
                        if item["type"] as? String == "command_execution" { emit(.tool("shell", item["command"] as? String ?? "")) }
                    case "item.completed":
                        if item["type"] as? String == "agent_message", let t = item["text"] as? String {
                            emit(.text((answer.isEmpty ? "" : "\n\n") + t))
                            answer.append(t)
                        }
                    case "turn.completed": finished = true
                    case "turn.failed": failure = (o["error"] as? [String: Any])?["message"] as? String ?? "turn failed"
                    case "error": failure = o["message"] as? String ?? "error"
                    default: break
                    }
                }
            }
            p.waitUntilExit()
            errorsRead.wait()
            let stopped = self.process !== p            // interrupted, or put to sleep
            if self.process === p { self.process = nil }
            if let failure { emit(.failed(tail(failure))) }
            else if finished || !answer.isEmpty || stopped { emit(.done(nil)) }
            else { emit(.failed(tail(String(data: errors, encoding: .utf8) ?? "") .isEmpty ? tr("o agente saiu sem responder") : tail(String(data: errors, encoding: .utf8) ?? ""))) }
        }
    }

    // (called from the main thread while `ask` waits on its own queue: the process is only read here)
    func interrupt() { let p = process; process = nil; p?.terminate() }
    func sleep() { interrupt() }

    func terminalCommand(session: String) -> [String]? { AgentCLIs.launch("codex", ["codex", "resume", session]) }
}

/// Any command that takes the question on its input and writes the answer to its output (Preferences → Assistant):
/// a server's client, a script, another model's CLI. It remembers nothing between turns, so each question goes
/// with the instructions in front.
final class CommandBrain: Brain {
    let id = "command"
    var name: String { tr("Um comando seu") }
    private var process: Process?

    static var command: String {
        get { UserDefaults.standard.string(forKey: "assistantCommand") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "assistantCommand") }
    }

    var installed: Bool { !AgentCLIs.words(Self.command).isEmpty }

    func ask(_ text: String, setup: BrainSetup, events: @escaping (BrainEvent) -> Void) {
        let words = AgentCLIs.words(Self.command)
        DispatchQueue.global(qos: .userInitiated).async {
            func emit(_ e: BrainEvent) { DispatchQueue.main.async { events(e) } }
            guard let first = words.first else { emit(.failed(tr("nenhum comando configurado"))); return }
            let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = [NSString(string: first).expandingTildeInPath] + words.dropFirst()
            p.currentDirectoryURL = setup.folder
            p.environment = AgentCLIs.processEnvironment("", extra: setup.environment)
            p.standardInput = stdin
            p.standardOutput = stdout
            p.standardError = stderr
            do { try p.run() } catch { emit(.failed(error.localizedDescription)); return }
            self.process = p
            emit(.started(session: nil, model: nil))
            try? stdin.fileHandleForWriting.write(contentsOf: Data((setup.persona + "\n\n" + text).utf8))
            try? stdin.fileHandleForWriting.close()
            var errors = Data()
            let errorsRead = DispatchGroup()
            errorsRead.enter()
            DispatchQueue.global().async { errors = stderr.fileHandleForReading.readDataToEndOfFile(); errorsRead.leave() }
            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()
            errorsRead.wait()
            let stopped = self.process !== p
            if self.process === p { self.process = nil }
            let answer = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if stopped { emit(.done(nil)) }
            else if p.terminationStatus != 0 || answer.isEmpty {
                let why = tail(String(data: errors, encoding: .utf8) ?? "")
                emit(.failed(why.isEmpty ? tr("o comando não respondeu nada") : why))
            } else { emit(.done(answer)) }
        }
    }

    func interrupt() { let p = process; process = nil; p?.terminate() }
    func sleep() { interrupt() }
}
