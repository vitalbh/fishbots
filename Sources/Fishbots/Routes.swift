import AppKit

/// The local HTTP server: the protocol, the agents' hooks, packs and state (README, docs/).
extension AppDelegate {
    func startServer() {
        ClaudeCodeHook.sessionContinued = { [unowned self] source, session, event in self.permissions.sessionContinued(source: source, session: session, event: event) }
        permissions.changed = { [unowned self] in self.updateDock() }
        do {
            server = try Server(port: port) { [unowned self] method, path, headers, body in
                self.respond(method, path, headers, body)
            }
            server?.deferred = { [unowned self] method, path, headers, body, reply in
                let route = path.split(separator: "?").first.map(String.init) ?? path
                guard method == "POST", let (provider, isPermission) = Providers.route(route), isPermission else { return false }
                let source = provider.id
                guard let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { reply(400, Data()); return true }
                // the fish arrives/updates like a normal PermissionRequest, and the request stays waiting
                var ev = m; ev["hook_event_name"] = "PermissionRequest"
                if let d = try? JSONSerialization.data(withJSONObject: ev) {
                    let mainRoute = provider.routes.first { route.hasPrefix($0 + "/") } ?? route
                    _ = provider.handle(route: mainRoute, body: d, headers: headers, tank: self.tank)
                }
                if let p = self.permissions.add(m, source: source, reply: reply), let f = self.tank.fish(source: source, entity: p.session) {
                    Outputs.emit(TankEvent(type: "permission", fish: f, detail: p.tool + ": " + p.summary))
                    if Attention.level(source, .waiting) == .urgent { self.notifier.notify(f, request: p.id, summary: p.tool + ": " + p.summary) }
                }
                return true
            }
        } catch {
            FileHandle.standardError.write("fishbots: couldn't open port \(port): \(error)\n".data(using: .utf8)!)
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
            self.reloadPacks()
            return (200, self.packsJSON())
        case ("GET", "/packs"):
            return (200, self.packsJSON())
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
                self.reloadPacks()
                var out = (try? JSONSerialization.jsonObject(with: self.packsJSON())) as? [String: Any] ?? [:]
                out["installed"] = id
                return (200, (try? JSONSerialization.data(withJSONObject: out)) ?? Data())
            } catch {
                return (400, (try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription])) ?? Data())
            }
        case ("GET", "/state"), ("GET", "/estado"):
            return (200, TankProtocol.state(self.tank))
        case ("GET", "/"):
            let routes = ["POST /event"] + Providers.allRoutes.map { "POST " + $0 } + ["GET /state", "GET /packs", "POST /packs/reload", "POST /packs/install", "GET /agents", "POST /agents/reload"]
            return (200, (try? JSONSerialization.data(withJSONObject: ["fishbots": "ok", "routes": routes])) ?? Data())
        case ("POST", _):
            if let (p, isPermission) = Providers.route(route), !isPermission {
                return p.handle(route: route, body: body, headers: headers, tank: self.tank)
            }
            return (404, Data(#"{"error":"unknown route"}"#.utf8))
        default:
            return (404, Data(#"{"error":"unknown route"}"#.utf8))
        }
    }
}
