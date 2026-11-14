import Foundation

/// Demo mode: a make-believe Mac inside the phone, for whoever has no Mac with Fishbots (and for App Review). It
/// answers what MacLink asks a real Mac (the stream's `state` and `permissions`, and the short requests) with a few
/// scripted sessions that work, finish, ask permission and take replies, so every screen works as it does paired.
/// Nothing leaves the phone and nothing is kept: closing the app ends it.
final class DemoMac {
    /// What the pairing screen and the status pill show for it; its key is never used (no connection is made).
    static var pairing: Pairing {
        var c = URLComponents()
        c.scheme = "fishbots"
        c.host = "pair"
        c.queryItems = [URLQueryItem(name: "name", value: tr("Mac de demonstração")), URLQueryItem(name: "port", value: "1"),
                        URLQueryItem(name: "key", value: Data(count: 32).base64EncodedString())]
        return Pairing(url: c.url!)!
    }

    /// What a session does next, in order (`loops`: then from the top again).
    private enum Step {
        case work(String, TimeInterval)
        case finish(String)
        case fail(String)
        case rest(TimeInterval)
        /// A permission request (`tool`, what it wants to run): the session waits until it's answered.
        case permission(String, String)
        /// A question with a menu of options.
        case question(String, [(String, String)])
    }

    private final class Session {
        let source, entity, label, title, cwd, model, branch, kind: String
        var state: State = .idle
        var doing = ""
        var context: Double
        var said: String?
        var script: [Step]
        let loops: Bool
        var at = 0
        var until: Date?
        var spawned = false

        init(_ source: String, _ entity: String, _ label: String, title: String, cwd: String, model: String, branch: String,
             kind: String, context: Double, loops: Bool = true, _ script: [Step]) {
            (self.source, self.entity, self.label, self.title, self.cwd, self.model, self.branch, self.kind) =
                (source, entity, label, title, cwd, model, branch, kind)
            self.context = context
            self.loops = loops
            self.script = script
        }

        var id: String { "\(source):\(entity)" }
    }

    private let emit: (_ event: String, _ obj: [String: Any]) -> Void
    private var sessions: [Session] = []
    private var permissions: [[String: Any]] = []
    private var nextPermission = 1
    private var journal: [[String: Any]] = []
    private var theme: String?
    private var timer: Timer?
    private var spawnedCount = 0

    /// `emit` gets what the stream would carry (`state`, `permissions`), on the main queue.
    init(emit: @escaping (_ event: String, _ obj: [String: Any]) -> Void) {
        self.emit = emit
        sessions = [
            Session("claude-code", "demo-site", "meu-site", title: tr("Página inicial nova"), cwd: "~/Dev/meu-site", model: "opus",
                    branch: "feat/hero", kind: "angelfish", context: 0.34, [
                        .work(tr("Lendo src/pages/index.tsx"), 5), .work(tr("Editando o componente Hero"), 7),
                        .work(tr("Rodando os testes"), 6),
                        .finish(tr("Troquei o topo da página inicial: título maior, a foto à direita e o botão \"Começar\" fixo no celular.\n\n- `src/components/Hero.tsx`: o layout novo\n- `src/pages/index.tsx`: usa o Hero\n\nOs 42 testes passaram.")),
                        .rest(25),
                    ]),
            Session("codex", "demo-api", "api", title: tr("Migração da tabela de pedidos"), cwd: "~/Dev/api", model: "gpt-5",
                    branch: "orders-v2", kind: "octopus", context: 0.58, [
                        .work(tr("Escrevendo a migração"), 6),
                        .permission("Bash", "npm run migrate -- --env staging"),
                        .work(tr("Migrando o staging"), 8),
                        .finish(tr("A migração rodou no staging: 18.204 pedidos copiados para `orders_v2`, nenhum erro. Produção fica para quando você quiser.")),
                        .rest(30),
                    ]),
            Session("claude-code", "demo-ios", "app-ios", title: tr("Ícone do app"), cwd: "~/Dev/app-ios", model: "sonnet",
                    branch: "main", kind: "betta", context: 0.12, [
                        .rest(14),
                        .question(tr("Qual ícone você prefere para o app?"), [
                            (tr("Peixe laranja"), tr("o de sempre, mais contraste")),
                            (tr("Peixe azul"), tr("combina com o tema noturno")),
                            (tr("Só a bolha"), tr("mais simples, lê bem pequeno")),
                        ]),
                        .work(tr("Gerando os tamanhos do ícone"), 7),
                        .finish(tr("Ícone trocado e gerado em todos os tamanhos do Assets.xcassets.")),
                        .rest(40),
                    ]),
            Session("claude-code", "demo-data", "dados", title: tr("Relatório semanal"), cwd: "~/Dev/dados", model: "opus",
                    branch: "main", kind: "stingray", context: 0.81, [
                        .work(tr("Consultando o banco"), 9), .fail(tr("A consulta passou do tempo limite (30 s) no banco de réplica.")),
                        .rest(12), .work(tr("Tentando com um índice"), 8),
                        .finish(tr("Relatório pronto em `reports/semana-46.csv`: vendas +12% sobre a semana passada.")),
                        .rest(35),
                    ]),
        ]
        // the chest (the last hours) has something to show from the start
        let iso = ISO8601DateFormatter()
        journal = [
            ["when": iso.string(from: Date().addingTimeInterval(-7200)), "kind": "done", "label": "meu-site", "fish": "claude-code:demo-site",
             "title": tr("Corrigir o menu no celular"), "said": tr("O menu agora fecha ao tocar fora dele.")],
            ["when": iso.string(from: Date().addingTimeInterval(-5400)), "kind": "merge", "label": "api", "fish": "codex:demo-api",
             "title": "orders-v1 → main"],
            ["when": iso.string(from: Date().addingTimeInterval(-3000)), "kind": "error", "label": "dados", "fish": "claude-code:demo-data",
             "title": tr("Relatório semanal"), "said": tr("Sem acesso ao banco: a VPN caiu.")],
        ]
    }

    func start() {
        guard timer == nil else { return }
        for s in sessions where s.until == nil && s.state == .idle { run(s) }
        sendAll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - the sessions' scripts

    private func tick() {
        let now = Date()
        for s in sessions { if let u = s.until, u <= now { s.until = nil; s.at += 1; run(s) } }
        for s in sessions where s.state == .busy { s.context = min(0.95, s.context + 0.004) }
        sendState()
    }

    /// Does the session's step `at` (past the end: from the top, or leaves).
    private func run(_ s: Session) {
        if s.at >= s.script.count {
            guard s.loops else { sessions.removeAll { $0 === s }; return }
            s.at = 0
        }
        switch s.script[s.at] {
        case .work(let what, let secs):
            s.state = .busy; s.doing = what; s.until = Date().addingTimeInterval(secs)
        case .finish(let said):
            s.state = .done; s.doing = ""; s.said = said; s.until = Date().addingTimeInterval(6)
            log("done", s, said: said)
        case .fail(let said):
            s.state = .error; s.doing = ""; s.said = said; s.until = Date().addingTimeInterval(8)
            log("error", s, said: said)
        case .rest(let secs):
            s.state = .idle; s.doing = ""; s.until = Date().addingTimeInterval(secs)
        case .permission(let tool, let command):
            ask(s, ["tool": tool, "summary": command])
        case .question(let text, let options):
            ask(s, ["tool": "AskUserQuestion", "summary": text,
                    "question": ["text": text, "multi": false, "options": options.map { ["label": $0.0, "about": $0.1] }]])
        }
    }

    private func ask(_ s: Session, _ extra: [String: Any]) {
        s.state = .waiting
        s.doing = ""
        var p: [String: Any] = ["id": nextPermission, "source": s.source, "entity": s.entity, "label": s.label]
        p.merge(extra) { $1 }
        nextPermission += 1
        permissions.append(p)
        log("waiting", s, said: extra["summary"] as? String)
        sendPermissions()
    }

    /// The person answered request `id`: the session goes on (allowed, answered) or stops there (denied).
    private func decide(_ id: Int, _ body: [String: Any]) -> Bool {
        guard let p = permissions.first(where: { $0["id"] as? Int == id }),
              let s = sessions.first(where: { $0.source == p["source"] as? String && $0.entity == p["entity"] as? String }) else { return false }
        permissions.removeAll { $0["id"] as? Int == id }
        if body["decision"] as? String == "deny" {
            s.said = tr("Tudo bem, não rodei. Me diga como prefere seguir.")
            s.state = .idle
            // it skips what it would have done and rests until its next round
            if let r = s.script[s.at...].firstIndex(where: { if case .rest = $0 { return true }; return false }) { s.at = r - 1 }
            s.until = Date().addingTimeInterval(4)
        } else {
            if let a = body["answer"] as? String { s.said = String(format: tr("Combinado: %@."), a) }
            s.at += 1
            run(s)
        }
        sendAll()
        return true
    }

    /// A reply from the card: it reads it, works a moment and answers.
    private func reply(_ s: Session, _ text: String) {
        permissions.removeAll { $0["source"] as? String == s.source && $0["entity"] as? String == s.entity }
        let rest = Array(s.script[min(s.at + 1, s.script.count)...])
        s.script = Array(s.script[..<min(s.at + 1, s.script.count)])
            + [.work(tr("Lendo a sua resposta"), 4),
               .finish(String(format: tr("Feito, como você pediu: \"%@\". (Isto é uma demonstração: no seu Mac, a resposta vai para a sessão de verdade.)"), text))]
            + rest
        s.until = nil
        s.at += 1
        run(s)
        sendAll()
    }

    private func spawn(agent: String, cwd: String, task: String) {
        spawnedCount += 1
        let label = (cwd as NSString).lastPathComponent
        let t = task.isEmpty ? tr("Sessão nova") : task
        let s = Session(agent, "demo-new-\(spawnedCount)", label.isEmpty ? "demo" : label, title: t, cwd: cwd,
                        model: agent == "codex" ? "gpt-5" : "opus", branch: "main", kind: ["neon", "puffer", "nautilus"][spawnedCount % 3],
                        context: 0.02, loops: false, [
                            .work(tr("Lendo o projeto"), 5), .work(t, 10),
                            .finish(String(format: tr("Terminei: %@. (Na demonstração nada roda de verdade; no seu Mac, isto abre o agente num terminal.)"), t)),
                            .rest(45),
                        ])
        s.state = .born
        s.until = Date().addingTimeInterval(2)
        s.at = -1
        sessions.append(s)
        sendState()
    }

    private func log(_ kind: String, _ s: Session, said: String?) {
        var e: [String: Any] = ["when": ISO8601DateFormatter().string(from: Date()), "kind": kind, "label": s.label, "fish": s.id, "title": s.title]
        if let said { e["said"] = said }
        journal.append(e)
        if journal.count > 60 { journal.removeFirst(journal.count - 60) }
    }

    // MARK: - what the stream carries

    private func sendAll() { sendState(); sendPermissions() }

    private func sendState() {
        let fish: [[String: Any]] = sessions.map { s in
            ["source": s.source, "entity": s.entity, "label": s.label, "state": s.state.rawValue, "title": s.title,
             "detail": s.source == "codex" ? "Codex" : "Claude Code", "doing": s.doing, "context": s.context, "model": s.model,
             "branch": s.branch, "where": ["cwd": s.cwd, "term": "iTerm.app"], "agent": true, "kind": s.kind,
             "can": ["reply", "stop"]]
        }
        var obj: [String: Any] = ["fish": fish, "presences": Self.presences, "gauges": [String: Any]()]
        if let theme { obj["theme"] = theme }
        emit("state", obj)
    }

    private func sendPermissions() { emit("permissions", ["permissions": permissions]) }

    /// The scene around them (docs/scene.md), as the Mac's demo has it.
    private static let presences: [[String: Any]] = [
        ["source": "demo", "presence": "prod", "kind": "pilot", "state": "ok", "label": "prod", "detail": "312 pods ok"],
        ["source": "demo", "presence": "deploy", "kind": "hourglass", "state": "busy", "label": "deploy", "detail": tr("faltam 4 min"), "value": 0.6],
        ["source": "demo", "presence": "site", "kind": "flag", "state": "ok", "label": "meu-site", "detail": "99,98% · 120 ms"],
    ]

    // MARK: - the short requests

    /// What `MacLink.request` would get back from a Mac; `done` runs on the main queue.
    func request(_ method: String, _ path: String, _ body: [String: Any]?, done: @escaping (Int, Data?) -> Void) {
        let (status, out) = answer(method, path, body ?? [:])
        let data = try? JSONSerialization.data(withJSONObject: out)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { done(status, data) }
    }

    private func answer(_ method: String, _ path: String, _ body: [String: Any]) -> (Int, [String: Any]) {
        let route = path.split(separator: "?").first.map(String.init) ?? path
        let q = URLComponents(string: path)?.queryItems ?? []
        func fish(_ source: String?, _ entity: String?) -> Session? { sessions.first { $0.source == source && $0.entity == entity } }
        switch (method, route) {
        case ("GET", "/journal"):
            let hours = q.first { $0.name == "hours" }?.value.flatMap(Double.init) ?? 3
            let since = Date().addingTimeInterval(-hours * 3600), iso = ISO8601DateFormatter()
            return (200, ["journal": journal.filter { ($0["when"] as? String).flatMap(iso.date(from:)).map { $0 >= since } ?? false }])
        case ("GET", "/said"):
            guard let s = fish(q.first { $0.name == "source" }?.value, q.first { $0.name == "entity" }?.value) else { return (404, ["error": "no such fish"]) }
            return (200, s.said.map { ["text": $0, "markdown": true] } ?? [:])
        case ("POST", "/reply"):
            guard let s = fish(body["source"] as? String, body["entity"] as? String) else { return (404, ["error": tr("essa sessão saiu do aquário")]) }
            reply(s, body["text"] as? String ?? "")
            return (200, ["ok": true])
        case ("POST", "/stop"):
            guard let s = fish(body["source"] as? String, body["entity"] as? String) else { return (404, ["error": tr("essa sessão saiu do aquário")]) }
            permissions.removeAll { $0["source"] as? String == s.source && $0["entity"] as? String == s.entity }
            s.state = .idle; s.doing = ""; s.said = tr("Parei onde estava.")
            s.until = Date().addingTimeInterval(20)
            sendAll()
            return (200, ["ok": true])
        case ("GET", "/spawn/options"):
            return (200, ["agents": [["id": "claude-code", "name": "Claude Code"], ["id": "codex", "name": "Codex"]],
                          "agent": "claude-code", "folders": ["~/Dev/meu-site", "~/Dev/api", "~/Dev/app-ios"], "canOpen": true])
        case ("POST", "/spawn"):
            guard sessions.count < 8 else { return (409, ["error": tr("o aquário da demonstração está cheio")]) }
            spawn(agent: body["agent"] as? String ?? "claude-code", cwd: body["cwd"] as? String ?? "~/Dev/demo", task: body["task"] as? String ?? "")
            return (200, ["ok": true])
        case ("POST", "/theme"):
            guard let id = body["id"] as? String, Themes.all.contains(where: { $0.id == id }) else { return (404, ["error": "no such theme"]) }
            theme = id
            sendState()
            return (200, ["ok": true])
        case ("POST", "/push/register"):
            return (200, ["ok": true])
        case ("POST", _) where route.hasPrefix("/permissions/"):
            guard let id = Int(route.dropFirst("/permissions/".count)), decide(id, body) else { return (404, ["error": "no such request"]) }
            return (200, ["ok": true])
        default:
            // what a newer Mac does that the demo doesn't (the packs among them): it just isn't there
            return (404, ["error": tr("isso não existe na demonstração")])
        }
    }
}
