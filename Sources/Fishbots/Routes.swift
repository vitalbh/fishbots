import AppKit

/// The local HTTP server: the protocol, the agents' hooks, packs and state (README, docs/).
extension AppDelegate {
    func startServer() {
        ClaudeCodeHook.sessionContinued = { [unowned self] source, session, event in self.permissions.sessionContinued(source: source, session: session, event: event) }
        permissions.changed = { [unowned self] in self.updateDock() }
        // the control routes' token for this run (ControlTokens.swift), written before anyone can ask
        ControlTokens.start(port: port)
        do {
            server = try Server(port: port) { [unowned self] method, path, headers, body in
                self.respond(method, path, headers, body)
            }
            Outputs.register(sessionControl)
            server?.deferred.append(sessionControl.handle)
            sessionControl.answer = { [unowned self] f, text in self.cards.answer(f, text) }
            sessionControl.permission = { [unowned self] f in
                self.permissions.request(ofFish: f.id).flatMap { $0.question == nil ? $0.tool + ": " + $0.summary : nil }
            }
            server?.deferred.append { [unowned self] method, path, headers, body, reply in
                let route = path.split(separator: "?").first.map(String.init) ?? path
                guard method == "POST", let (provider, isPermission) = Providers.route(route), isPermission else { return false }
                // the assistant's own brain, and a session run in the background, ask through their stream (on the
                // assistant's card, on the fish's): no decision from the hook
                if Assistant.owns(body) || Background.owns(body) { reply(200, Data("{}".utf8)); return true }
                guard let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { reply(400, Data()); return true }
                let mainRoute = provider.routes.first { route.hasPrefix($0 + "/") } ?? route
                self.permissionAsked(m, provider: provider, route: mainRoute, headers: headers, reply: reply)
                return true
            }
            // other devices see the same tank and answer the way the card does
            remote.local = { [unowned self] method, path, headers, body in self.respond(method, path, headers, body) }
            remote.reply = { [unowned self] f, text in self.cards.sendReply(f, text) }
            remote.decide = { [unowned self] id, action in self.cards.decide(id, action) }
            remote.can = { [unowned self] c, f in self.cards.can(c, f) }
            remote.useTheme = { [unowned self] id in self.themeKeeper.use(id) }
            Outputs.register(remote)
            remote.start()
            // a session with no terminal asks leave through its stream: the same request on its fish's card
            Background.tank = tank
            Background.askPermission = { [unowned self] session, request, answer in
                guard let id = session.session, let provider = Providers.of(session.agent), let route = provider.routes.first else { answer([:]); return }
                let m: [String: Any] = ["session_id": id, "tool_name": request.tool, "tool_input": request.input, "cwd": session.cwd]
                self.permissionAsked(m, provider: provider, route: route, headers: [:]) { _, data in
                    answer((try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
                }
            }
        } catch {
            FileHandle.standardError.write("fishbots: couldn't open port \(port): \(error)\n".data(using: .utf8)!)
        }
    }

    /// A session asks leave for a tool (its permission hook, or its stream when it runs in the background): its fish
    /// arrives or updates like on any PermissionRequest, and the request waits on its card until `reply` gets the
    /// decision.
    func permissionAsked(_ m: [String: Any], provider: SessionProvider, route: String, headers: [String: String],
                         reply: @escaping (Int, Data) -> Void) {
        let source = provider.id
        var ev = m; ev["hook_event_name"] = "PermissionRequest"
        if let d = try? JSONSerialization.data(withJSONObject: ev) {
            _ = provider.handle(route: route, body: d, headers: headers, tank: self.tank)
        }
        if let p = self.permissions.add(m, source: source, reply: reply), let f = self.tank.fish(source: source, entity: p.session) {
            // a question with a menu: what it asks, with its answers, for the card and for a session waiting on it
            if let q = p.question { f.asked = q.asText }
            Outputs.emit(TankEvent(type: "permission", fish: f, detail: p.tool + ": " + p.summary))
            if Attention.level(source, .waiting) == .urgent { self.notifier.notify(f, request: p.id, summary: p.tool + ": " + p.summary) }
        }
    }

    /// An answer right away: the routes the app knows, then the providers' own.
    private func respond(_ method: String, _ path: String, _ headers: [String: String], _ body: Data) -> (Int, Data) {
        let route = path.split(separator: "?").first.map(String.init) ?? path
        if method == "POST", let answer = testRoute(route, path) { return answer }
        switch (method, route) {
        case ("POST", "/event"), ("POST", "/events"), ("POST", "/evento"), ("POST", "/eventos"):
            return TankProtocol.apply(body, at: self.tank)
        case ("POST", "/summary"):
            self.recentSummary()
            return (200, Data(#"{"ok":true}"#.utf8))
        case ("POST", "/agents/reload"), ("GET", "/agents"):
            if method == "POST" { self.reloadAgents() }
            return (200, (try? JSONSerialization.data(withJSONObject: AgentManifests.json, options: [.prettyPrinted, .sortedKeys])) ?? Data())
        case ("POST", "/packs/reload"):
            self.themeKeeper.reloadPacks()
            return (200, ThemeKeeper.packsJSON())
        case ("GET", "/packs"):
            return (200, ThemeKeeper.packsJSON())
        case ("GET", "/packs/files"):
            // the screen saver copies the packs from here (it can't read the app's folder)
            return (200, Packs.filesJSON())
        case ("POST", "/packs/install"):
            // {"path": "/…/x.fishbotspack"}: installs it and reloads
            guard let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any], let p = j["path"] as? String else {
                return (400, Data(#"{"error":"send {\"path\": \"…\"}"}"#.utf8))
            }
            do {
                let id = try Packs.install(URL(fileURLWithPath: p))
                self.themeKeeper.reloadPacks()
                var out = (try? JSONSerialization.jsonObject(with: ThemeKeeper.packsJSON())) as? [String: Any] ?? [:]
                out["installed"] = id
                return (200, (try? JSONSerialization.data(withJSONObject: out)) ?? Data())
            } catch {
                return (400, (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data())
            }
        case ("GET", "/state"), ("GET", "/estado"):
            return (200, TankProtocol.state(self.tank))
        case ("GET", "/"):
            let routes = ["POST /event"] + Providers.allRoutes.map { "POST " + $0 } + ["GET /state", "GET /journal", "GET /packs", "POST /packs/reload", "POST /packs/install", "GET /agents", "POST /agents/reload", "GET /remote", "POST /remote/forget"] + SessionControl.routes
            return (200, (try? JSONSerialization.data(withJSONObject: ["fishbots": "ok", "routes": routes])) ?? Data())
        case ("GET", "/remote"):
            // pairing another device (Remote.swift): whether it's on, and the link its QR code carries
            return (200, self.remote.pairingJSON)
        case ("POST", "/remote/forget"):
            self.remote.forgetDevices()
            return (200, self.remote.pairingJSON)
        case ("POST", "/assistant/watch"):
            // the resident assistant asks to be woken when a session stops, to tell the person (`fishbots watch`)
            return self.assistant.watch(body)
        case ("GET", "/journal"):
            // what happened today (or in the last ?hours=N): tasks done, errors, who waited, PRs, events
            let hours = path.range(of: #"hours=([0-9.]+)"#, options: .regularExpression).flatMap { Double(path[$0].dropFirst(6)) }
            let since = hours.map { Date().addingTimeInterval(-$0 * 3600) } ?? Calendar.current.startOfDay(for: Date())
            return (200, self.journal.json(since: since))
        case ("POST", _):
            if let (p, isPermission) = Providers.route(route), !isPermission {
                // the resident assistant's brain runs an agent too: it's the creature in its burrow, not one more fish
                if Assistant.owns(body) { return (200, Data(#"{"ok":true}"#.utf8)) }
                return p.handle(route: route, body: body, headers: headers, tank: self.tank)
            }
            return (404, Data(#"{"error":"unknown route"}"#.utf8))
        default:
            return (404, Data(#"{"error":"unknown route"}"#.utf8))
        }
    }
}
