import AppKit

/// Something that happened in the tank, as outputs see it.
struct TankEvent {
    /// "state" (a fish changed state), "permission" (a request is waiting for you) or "party" (left celebrating).
    let type: String
    let source: String
    let entity: String
    let label: String
    let state: String
    let previous: String?
    let title: String?
    let detail: String?

    init(type: String, fish f: Fish, previous: State? = nil, detail: String? = nil) {
        self.type = type
        source = f.source
        entity = String(f.id.dropFirst(f.source.count + 1))
        label = f.label
        state = f.state.rawValue
        self.previous = previous?.rawValue
        title = f.displayTitle
        self.detail = detail ?? f.sub
    }

    var json: [String: Any] {
        var d: [String: Any] = ["type": type, "source": source, "entity": entity, "label": label, "state": state,
                                "time": ISO8601DateFormatter().string(from: Date())]
        if let previous { d["previous"] = previous }
        if let title { d["title"] = title }
        if let detail { d["detail"] = detail }
        return d
    }
}

/// An output: receives what happens in the tank and sends it somewhere (a webhook, Slack, a desk light…).
/// See docs/extensions.md.
protocol EventSink: AnyObject {
    var id: String { get }
    func send(_ e: TankEvent)
}

/// The registry of outputs. Webhooks come from config.json:
///   {"webhooks": [{"url": "https://…", "types": ["state", "permission"], "states": ["waiting", "error", "done"]}]}
enum Outputs {
    private(set) static var sinks: [EventSink] = []
    private static var fromConfig: [EventSink] = []

    static func register(_ s: EventSink) {
        sinks.removeAll { $0.id == s.id }
        sinks.append(s)
    }

    static func emit(_ e: TankEvent) {
        guard e.source != "decor", e.source != "fry", e.source != NowPlaying.source else { return }
        for s in sinks + fromConfig { s.send(e) }
    }

    /// Reads the webhooks from config.json (called with the attention rules).
    static func reload(_ config: [String: Any]) {
        fromConfig = (config["webhooks"] as? [[String: Any]] ?? []).enumerated().compactMap { i, w in
            guard let s = w["url"] as? String, let url = URL(string: s), ["http", "https"].contains(url.scheme ?? "") else { return nil }
            return Webhook(id: "webhook-\(i)", url: url, types: w["types"] as? [String], states: w["states"] as? [String])
        }
    }
}

/// POSTs each event as JSON. Filters by event type and by state (nil: everything).
final class Webhook: EventSink {
    let id: String
    let url: URL
    let types: Set<String>?
    let states: Set<String>?

    init(id: String, url: URL, types: [String]?, states: [String]?) {
        self.id = id
        self.url = url
        self.types = types.map(Set.init)
        self.states = states.map(Set.init)
    }

    func send(_ e: TankEvent) {
        if let types, !types.contains(e.type) { return }
        if let states, !states.contains(e.state) { return }
        guard let body = try? JSONSerialization.data(withJSONObject: e.json) else { return }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, _, error in
            if let error { FileHandle.standardError.write("fishbots: webhook \(self.url.host ?? "") failed: \(error.localizedDescription)\n".data(using: .utf8)!) }
        }.resume()
    }
}

// MARK: - fish menu actions

/// An extra item in the fish menu. See docs/extensions.md.
struct FishAction {
    let id: String
    let title: String
    /// Shown only for fish where this is true.
    let when: (Fish) -> Bool
    let run: (Fish) -> Void
}

/// The registry of fish menu actions: built-ins, providers' and the ones in config.json:
///   {"actions": [{"title": "Abrir no Cursor", "command": ["/usr/bin/open", "-a", "Cursor", "{cwd}"]}]}
/// Commands run without a shell; {cwd}, {link}, {label}, {source}, {entity} and {title} are replaced (the action only
/// shows when every placeholder it uses has a value).
enum FishActions {
    private(set) static var registered: [FishAction] = [
        FishAction(id: "finder", title: "Abrir pasta no Finder", when: { $0.whereabouts["cwd"] != nil }) { f in
            if let c = f.whereabouts["cwd"] { NSWorkspace.shared.open(URL(fileURLWithPath: c)) }
        },
        FishAction(id: "copy-path", title: "Copiar caminho", when: { $0.whereabouts["cwd"] != nil }) { f in
            guard let c = f.whereabouts["cwd"] else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(c, forType: .string)
        },
    ]
    private static var fromConfig: [FishAction] = []

    static var all: [FishAction] { registered + fromConfig }

    static func register(_ a: FishAction) {
        registered.removeAll { $0.id == a.id }
        registered.append(a)
    }

    private static func values(_ f: Fish) -> [String: String] {
        var v = ["label": f.label, "source": f.source, "entity": String(f.id.dropFirst(f.source.count + 1))]
        v["cwd"] = f.whereabouts["cwd"]
        v["link"] = f.link
        v["title"] = f.displayTitle
        return v
    }

    /// Reads the actions from config.json (called with the attention rules).
    static func reload(_ config: [String: Any]) {
        fromConfig = (config["actions"] as? [[String: Any]] ?? []).enumerated().compactMap { i, a in
            guard let title = a["title"] as? String, let cmd = a["command"] as? [String], let exe = cmd.first, exe.hasPrefix("/") else { return nil }
            let used = cmd.flatMap { arg in ["cwd", "link", "label", "source", "entity", "title"].filter { arg.contains("{\($0)}") } }
            return FishAction(id: "config-\(i)", title: title, when: { f in used.allSatisfy { values(f)[$0] != nil } }) { f in
                let v = values(f)
                let args = cmd.dropFirst().map { arg in v.reduce(arg) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) } }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = Array(args)
                p.standardOutput = FileHandle.nullDevice
                p.standardError = FileHandle.nullDevice
                try? p.run()
            }
        }
    }
}
