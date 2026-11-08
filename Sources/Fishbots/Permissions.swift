import AppKit

/// Permission requests waiting for an answer through the aquarium (Claude Code's PermissionRequest hook).
/// The request also shows up in the terminal; whoever answers first wins. If the session moves on
/// (answered in the terminal), the request here closes by itself, with no decision.
final class Permissions {
    struct Request {
        let id: Int
        let source: String
        let session: String
        let tool: String
        let summary: String       // the command, the file, the URL…
        let since: Date
        let reply: (Int, Data) -> Void
        var fishId: String { "\(source):\(session)" }
    }

    private(set) var pending: [Request] = []
    private var next = 1
    var changed: (() -> Void)?

    /// A request arrives: store it and hold the HTTP response until someone decides.
    func add(_ m: [String: Any], source: String, reply: @escaping (Int, Data) -> Void) -> Request? {
        guard let session = m["session_id"] as? String else { reply(400, Data()); return nil }
        // one request per session: a new one replaces the previous one (which gets no decision)
        for p in pending where p.session == session && p.source == source { p.reply(200, Data("{}".utf8)) }
        pending.removeAll { $0.session == session && $0.source == source }
        let tool = m["tool_name"] as? String ?? "ferramenta"
        let p = Request(id: next, source: source, session: session, tool: tool,
                       summary: Self.summary(tool, m["tool_input"] as? [String: Any] ?? [:]), since: Date(), reply: reply)
        next += 1
        pending.append(p)
        changed?()
        return p
    }

    static func summary(_ tool: String, _ e: [String: Any]) -> String {
        let s: String
        if let c = e["command"] as? String { s = c }
        else if let f = e["file_path"] as? String ?? e["notebook_path"] as? String { s = (f as NSString).abbreviatingWithTildeInPath }
        else if let u = e["url"] as? String { s = u }
        else if let q = e["query"] as? String { s = q }
        else if let p = e["pattern"] as? String { s = p }
        else if tool.hasPrefix("mcp__") { s = tool.components(separatedBy: "__").dropFirst().joined(separator: " · ") }
        else {
            let d = (try? JSONSerialization.data(withJSONObject: e, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
            s = d
        }
        return String(s.prefix(600))
    }

    func request(ofFish id: String) -> Request? { pending.last { $0.fishId == id } }
    func request(id: Int) -> Request? { pending.first { $0.id == id } }

    /// Replies: "allow", "deny" or nil (no decision: follows the terminal's normal flow).
    func reply(_ id: Int, _ decision: String?) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        let p = pending.remove(at: i)
        var body = "{}"
        if decision == "allow" { body = #"{"behavior":"allow"}"# }
        if decision == "deny" { body = "{\"behavior\":\"deny\",\"message\":\"\(tr("Negado pelo Fishbots."))\"}" }
        p.reply(200, Data(body.utf8))
        changed?()
    }

    /// The session moved on (answered in the terminal, or something else happened): close with no decision.
    func sessionContinued(source: String, session: String, event: String) {
        let now = Date()
        for p in pending where p.source == source && p.session == session {
            // the PreToolUse of the same call can arrive right after the request: ignore it during the first 2 s
            if event == "PreToolUse" && now.timeIntervalSince(p.since) < 2 { continue }
            reply(p.id, nil)
        }
    }

    /// When the app quits: release everyone (the terminal keeps asking).
    func releaseAll() { for p in pending { reply(p.id, nil) } }
}

/// The little window that opens when clicking the fish asking for permission.
final class RequestView: NSViewController {
    private let request: Permissions.Request
    private let label: String
    private let action: (String) -> Void

    init(request: Permissions.Request, label: String, action: @escaping (String) -> Void) {
        self.request = request
        self.label = label
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let title = NSTextField(labelWithString: tr("%@ quer usar %@", label, request.tool))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(wrappingLabelWithString: request.summary)
        detail.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 8
        detail.preferredMaxLayoutWidth = 380
        detail.isSelectable = true
        let hint = NSTextField(labelWithString: tr("Também está perguntando no terminal; vale quem responder primeiro."))
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor

        func button(_ t: String, _ id: String, _ key: String = "") -> NSButton {
            let b = NSButton(title: t, target: self, action: #selector(clicked(_:)))
            b.identifier = NSUserInterfaceItemIdentifier(id)
            b.keyEquivalent = key
            b.bezelStyle = .rounded
            return b
        }
        let allow = button(tr("Permitir"), "allow", "\r")
        let deny = button(tr("Negar"), "deny")
        let go = button(tr("Ir até lá"), "go")
        let buttons = NSStackView(views: [go, NSView(), deny, allow])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, detail, hint, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32).isActive = true
        stack.widthAnchor.constraint(equalToConstant: 420).isActive = true
        view = stack
    }

    @objc private func clicked(_ b: NSButton) { action(b.identifier?.rawValue ?? "") }
}
