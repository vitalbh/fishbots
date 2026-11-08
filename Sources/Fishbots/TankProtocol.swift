import Foundation

/// The aquarium protocol. Sources know nothing about music or fish: they only say what is happening.
///
///   {"source":"x","entity":"id","state":"busy","label":"name"}        entity (a fish)
///   {"source":"x","entity":"id","state":"end"}                        entity leaves the tank ("party":true: leaves celebrating)
///   {"source":"x","entity":"id","tool":"Bash"}                        activity pulse
///   optional on an entity: "detail" (2nd line of the label), "link" (opened on click),
///   "where" ({"term","tty","rex_session","rex_block","rex_bin","herdr","iterm","tmux","wezterm","kitty","cwd"})
///   {"source":"x","event":"deploy","label":"meu-site"}                event (food)
///   {"source":"x","gauge":"disk","value":0.87}                        gauge (0…1; null removes it; silent for 1 h: gone)
///   {"source":"x","effect":"fireworks","label":"deploy"}              effect (docs/scene.md)
///   {"source":"x","presence":"id","kind":"shark","state":"error","label":"prod","detail":"…"}   presence (docs/scene.md)
///
/// Accepts one object or a list of objects. The original Portuguese field names and states
/// ("fonte", "entidade", "estado", "ocupado", "fim"…) are still accepted, since installed hooks and plugins send them.
enum TankProtocol {
    /// Legacy (Portuguese) field names → current ones.
    static let legacyFields: [String: String] = [
        "fonte": "source", "entidade": "entity", "estado": "state", "rotulo": "label", "evento": "event",
        "medidor": "gauge", "valor": "value", "ferramenta": "tool", "detalhe": "detail", "onde": "where", "festa": "party",
    ]

    /// Copies legacy keys to their current names (the current name wins when both are present).
    static func normalized(_ m: [String: Any]) -> [String: Any] {
        var out = m
        for (old, new) in legacyFields where out[new] == nil {
            if let v = m[old] { out[new] = v }
        }
        return out
    }

    static func apply(_ body: Data, at tank: Tank) -> (Int, Data) {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            return (400, Data(#"{"error":"invalid json"}"#.utf8))
        }
        let items: [[String: Any]]
        if let list = json as? [[String: Any]] { items = list }
        else if let one = json as? [String: Any] { items = [one] }
        else { return (400, Data(#"{"error":"expected an object or a list"}"#.utf8)) }

        var errors: [String] = []
        for m in items {
            if let e = applyOne(normalized(m), tank) { errors.append(e) }
        }
        if errors.isEmpty { return (200, Data(#"{"ok":true}"#.utf8)) }
        let resp = (try? JSONSerialization.data(withJSONObject: ["ok": false, "errors": errors])) ?? Data()
        return (400, resp)
    }

    private static func text(_ v: Any?, max: Int = 80) -> String? {
        guard let s = v as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(max))
    }

    /// "#rrggbb" → color.
    private static func color(_ v: Any?) -> SIMD3<Float>? {
        guard let s = v as? String, s.hasPrefix("#"), s.count == 7, let n = UInt32(s.dropFirst(), radix: 16) else { return nil }
        return [Float((n >> 16) & 255) / 255, Float((n >> 8) & 255) / 255, Float(n & 255) / 255]
    }

    private static func fraction(_ v: Any?) -> Float? {
        guard let f = (v as? NSNumber)?.floatValue, f.isFinite else { return nil }
        return max(0, min(1, f))
    }

    private static func applyOne(_ m: [String: Any], _ tank: Tank) -> String? {
        guard let source = text(m["source"], max: 40) else { return "missing \"source\"" }
        let label = text(m["label"])

        if let id = text(m["presence"], max: 120) {
            let s = text(m["state"])
            if let s, State.isEnd(s) { tank.scene.remove(source: source, id: id, party: (m["party"] as? Bool) == true, tank); return nil }
            var state: State?
            if let s {
                guard let st = State(wire: s) else { return "unknown state: \(s) (use \(State.allCases.map(\.rawValue).joined(separator: ", ")), end)" }
                state = st
            }
            var link: String?
            if let l = text(m["link"], max: 2000) {
                guard let u = URL(string: l), ["http", "https"].contains(u.scheme ?? "") else { return "link must be http or https" }
                link = l
            }
            let detail = m["detail"] is String ? (text(m["detail"], max: 160) ?? "") : nil
            return tank.scene.upsert(tank, source: source, id: id, kind: text(m["kind"], max: 40), state: state, label: label,
                                     detail: detail, link: link, value: fraction(m["value"]), color: color(m["color"]), x: fraction(m["x"]),
                                     sound: text(m["sound"], max: 40))
        }
        if let effect = text(m["effect"], max: 40) {
            return tank.scene.effect(effect, tank, source: source, label: label, x: fraction(m["x"]), y: fraction(m["y"]), color: color(m["color"]),
                                     sound: text(m["sound"], max: 40))
        }

        if let entity = text(m["entity"], max: 120) {
            if let tool = text(m["tool"], max: 40) {
                tank.tool(source: source, entity: entity, name: tool)
            }
            if let e = text(m["state"]) {
                if State.isEnd(e) { tank.remove(source: source, entity: entity, party: (m["party"] as? Bool) == true); return nil }
                guard let state = State(wire: e) else {
                    return "unknown state: \(e) (use \(State.allCases.map(\.rawValue).joined(separator: ", ")), end)"
                }
                tank.upsert(source: source, entity: entity, state: state, label: label)
            }
            if let f = tank.fish(source: source, entity: entity) {
                if let link = text(m["link"], max: 2000), let u = URL(string: link), ["http", "https"].contains(u.scheme ?? "") {
                    f.link = link
                }
                if let sub = text(m["detail"]) { f.sub = sub }
                if let whereabouts = m["where"] as? [String: Any] {
                    var o: [String: String] = [:]
                    for (k, v) in whereabouts { if let t = text(v, max: 300) { o[String(k.prefix(40))] = t } }
                    Whereabouts.update(f, with: o)
                }
            }
            return nil
        }
        if let ev = text(m["event"]) {
            tank.event(source: source, name: ev, label: label)
            return nil
        }
        if let gauge = text(m["gauge"], max: 40) {
            // "value": null (or "state": "end") takes it away
            if m["value"] is NSNull || (text(m["state"]).map(State.isEnd) ?? false) {
                tank.removeGauge(source: source, name: gauge)
                return nil
            }
            guard let v = (m["value"] as? NSNumber)?.floatValue, v.isFinite else { return "gauge without a numeric \"value\" (null removes it)" }
            tank.gauge(source: source, name: gauge, value: v)
            return nil
        }
        return "needs \"entity\", \"presence\", \"effect\", \"event\" or \"gauge\""
    }

    /// More to show in /state (the app adds the packs; kept out of here so the screen saver doesn't need them).
    static var stateExtras: (() -> [String: Any])?

    static func state(_ tank: Tank) -> Data {
        let fishes: [[String: Any]] = tank.fish.filter { !$0.decor }.map {
            ["source": $0.source, "entity": String($0.id.dropFirst($0.source.count + 1)), "label": $0.label,
             "state": $0.state.rawValue, "motif": $0.motif, "leaving": $0.leaving,
             "detail": $0.sub ?? "", "title": $0.displayTitle ?? "", "branch": $0.branch ?? "", "context": $0.context ?? -1, "where": $0.whereabouts, "link": $0.link ?? "",
             "agent": $0.isAgent, "species": $0.species]
        }
        let presences: [[String: Any]] = tank.scene.presences.filter { !$0.leaving }.map {
            ["source": $0.source, "presence": String($0.id.dropFirst($0.source.count + 1)), "kind": $0.kind.id, "state": $0.state.rawValue,
             "label": $0.label, "detail": $0.detail ?? "", "link": $0.link ?? "", "value": $0.value ?? -1,
             "sound": $0.sound ?? $0.kind.sound]
        }
        var obj: [String: Any] = ["fish": fishes, "presences": presences, "gauges": tank.gauges, "theme": Themes.current.id]
        if let extras = stateExtras?() { obj.merge(extras) { $1 } }
        return (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}

/// Built-in Claude Code plugin: receives the raw hook JSON and translates it to the protocol.
enum ClaudeCodeHook {
    /// The agent's text without markdown markup (for reading on the card).
    static func stripMarkdown(_ t: String) -> String {
        var s = t
        // code blocks become a single line
        while let a = s.range(of: "```") {
            if let b = s.range(of: "```", range: a.upperBound..<s.endIndex) { s.replaceSubrange(a.lowerBound..<b.upperBound, with: tr("[código]")) }
            else { s.replaceSubrange(a, with: ""); break }
        }
        let rules: [(String, String)] = [
            (#"\[([^\]]+)\]\([^)]+\)"#, "$1"),          // [text](link) → text
            (#"(?m)^#{1,6}\s*"#, ""),                    // headings
            (#"(?m)^\s*[-*+]\s+"#, "• "),               // lists
            (#"(?m)^\s*\|?\s*:?-{3,}.*$"#, ""),          // table separators
            (#"\*\*|__|`"#, ""),                         // bold, code
            (#"(?<![\w*])\*(?!\s)([^*\n]+)\*"#, "$1"),   // italic
            (#"\n{3,}"#, "\n\n"),
        ]
        for (pattern, swap) in rules {
            s = s.replacingOccurrences(of: pattern, with: swap, options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// If the reply ends with a question, returns the question sentence.
    static func question(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = String(t.suffix(4)).unicodeScalars.filter { !$0.properties.isEmojiPresentation && $0 != "\u{FE0F}" && $0 != "*" && $0 != "`" }
        guard end.contains("?") else { return nil }
        let phrase = t.split(whereSeparator: { ".!\n".contains($0) }).last.map(String.init) ?? t
        return String(phrase.trimmingCharacters(in: .whitespaces).prefix(90))
    }

    /// Called on every event of a session (to close a permission request that was answered in the terminal).
    static var sessionContinued: ((_ source: String, _ session: String, _ event: String) -> Void)?

    /// `requireTranscript`: events without a saved conversation are ignored (Codex's internal tasks).
    static func apply(_ body: Data, headers: [String: String], at tank: Tank, source: String,
                      defaultLabel: String, requireTranscript: Bool = false) -> (Int, Data) {
        guard let m = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let session = m["session_id"] as? String, let event = m["hook_event_name"] as? String else {
            return (400, Data(#"{"error":"expected the JSON of a Claude Code hook"}"#.utf8))
        }
        let cwd = (m["cwd"] as? String) ?? ""
        let label = cwd.isEmpty ? defaultLabel : (cwd as NSString).lastPathComponent
        let input = m["tool_input"] as? [String: Any] ?? [:]
        let tool = m["tool_name"] as? String
        // tools that are the agent asking you something
        let question = ["AskUserQuestion", "ExitPlanMode", "request_user_input", "AskQuestion"].contains(tool ?? "")
        let msg = ((m["message"] as? String) ?? "").lowercased()

        if requireTranscript {
            let t = (m["transcript_path"] as? String) ?? ""
            if t.isEmpty || !FileManager.default.fileExists(atPath: t) {
                tank.remove(source: source, entity: session)
                return (200, Data(#"{"ok":true,"ignored":"no conversation"}"#.utf8))
            }
        }
        func state(_ e: State) { tank.upsert(source: source, entity: session, state: e, label: label) }

        if !["PermissionRequest", "Notification", "PreCompact", "SubagentStop"].contains(event) { sessionContinued?(source, session, event) }
        let compacted = event == "SessionStart" && (m["source"] as? String) == "compact"
        switch event {
        case "SessionStart" where compacted:
            // end of compaction: not a new session
            if let f = tank.fish(source: source, entity: session) {
                f.compactingSince = nil
                f.transcriptReadAt = 0
                tank.burst(at: f.pos, n: 10)
            }
        case "SessionStart":
            state(.born)
        case "UserPromptSubmit":
            state(.busy)
        case "PreToolUse" where question:
            state(.waiting)
        case "PreToolUse":
            state(.busy)
            if let tool {
                tank.tool(source: source, entity: session, name: tool)
                if tool == "Task" || tool == "Agent" { tank.fry(source: source, entity: session) }   // subagent: fry
                if tool.hasPrefix("mcp__") {
                    // MCP: the seahorse brings a little letter; the label shows the server
                    let parts = tool.components(separatedBy: "__")
                    let server = parts.count > 1 ? parts[1] : "mcp"
                    tank.mail(source: source, entity: session, server: server)
                    tank.fish(source: source, entity: session)?.tool = "mcp · " + server
                }
                if tool == "Skill" { tank.shine(source: source, entity: session) }
                if tool == "TodoWrite", let list = input["todos"] as? [[String: Any]] {
                    let done = list.filter { ($0["status"] as? String) == "completed" }.count
                    tank.todos(source: source, entity: session, total: list.count, done: done)
                }
            }
        case "PostToolUse":
            state(.busy)
        case "PermissionRequest":
            state(.waiting)
        case "Notification":
            if msg.contains("permission") || msg.contains("permissão") || msg.contains("approve") {
                state(.waiting)
            } else if msg.contains("waiting for your input") {
                state(.idle)
            } else {
                state(.waiting)
            }
        case "Stop":
            // ended with a question for you? then it waits for the answer.
            // The text comes in the hook (Codex) or, if not, from the last reply in the transcript (Claude Code).
            if let last = m["last_assistant_message"] as? String, !last.isEmpty {
                tank.fish(source: source, entity: session)?.lastReply = Self.stripMarkdown(last)
                if let q = Self.question(Self.stripMarkdown(last)) {
                    state(.waiting)
                    tank.fish(source: source, entity: session)?.asked = q
                } else {
                    state(.done)
                }
            } else {
                state(.done)
                if let t = m["transcript_path"] as? String {
                    Transcript.lastReply(t) { text in
                        if let text { tank.fish(source: source, entity: session)?.lastReply = Self.stripMarkdown(text) }
                        guard let text, let q = Self.question(Self.stripMarkdown(text)),
                              let f = tank.fish(source: source, entity: session), f.state == .done else { return }
                        tank.upsert(source: source, entity: session, state: .waiting, label: nil)
                        f.asked = q
                    }
                }
            }
        case "SubagentStop":
            tank.removeFry(source: source, entity: session)
        case "PreCompact":
            if tank.fish(source: source, entity: session) == nil { state(.busy) }
            tank.fish(source: source, entity: session)?.compactingSince = tank.time
        case "SessionEnd":
            tank.remove(source: source, entity: session)
        default:
            if event.contains("Failure") || event.contains("Error") { state(.error) }
        }
        if let f = tank.fish(source: source, entity: session) {
            var o: [String: String] = [:]
            // X-Where-* headers (the legacy X-Onde-* still work)
            for (k, v) in headers {
                guard let prefix = ["x-where-", "x-onde-"].first(where: k.hasPrefix) else { continue }
                o[String(k.dropFirst(prefix.count)).replacingOccurrences(of: "-", with: "_")] = String(v.prefix(300))
            }
            if !cwd.isEmpty { o["cwd"] = cwd }
            Whereabouts.update(f, with: o)
            if let t = m["transcript_path"] as? String { f.transcriptPath = t; Transcript.read(t, to: f, now: tank.time) }
            // any other event after a while also ends the compaction
            if event != "PreCompact", let c = f.compactingSince, tank.time - c > 5, !compacted { f.compactingSince = nil; f.transcriptReadAt = 0 }
        }
        return (200, Data(#"{"ok":true}"#.utf8))
    }
}

/// Reads the end of Claude's transcript (JSONL) to find the conversation title and the branch.
enum Transcript {
    static func read(_ path: String, to f: Fish, now: Double) {
        guard now - f.transcriptReadAt > 10 else { return }   // at most every 10 s per fish
        f.transcriptReadAt = now
        // only Claude session files, inside your home folder
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension == "jsonl", url.path.hasPrefix(NSHomeDirectory() + "/") else { return }
        if url.path.contains("/.codex/sessions/") { readCodex(url, to: f); return }
        guard url.path.contains("/projects/") else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let h = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? h.close() }
            let size = (try? h.seekToEnd()) ?? 0
            let window: UInt64 = 512 * 1024
            try? h.seek(toOffset: size > window ? size - window : 0)
            guard let d = try? h.readToEnd() else { return }
            var title: String?
            var branch: String?
            var used: Double?
            var fixed: String?
            for line in d.split(separator: UInt8(ascii: "\n")).reversed() {
                if title != nil && branch != nil && used != nil && fixed != nil { break }
                if fixed == nil, line.firstRange(of: Data("\"custom-title\"".utf8)) != nil,
                   let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                   let t = obj["customTitle"] as? String, !t.isEmpty { fixed = String(t.prefix(48)) }
                // context: the usage of the last reply (input + cache + output)
                if used == nil, line.firstRange(of: Data("\"usage\"".utf8)) != nil,
                   line.firstRange(of: Data("\"type\":\"assistant\"".utf8)) != nil,
                   let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                   let u = (obj["message"] as? [String: Any])?["usage"] as? [String: Any] {
                    let n = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens"]
                        .compactMap { (u[$0] as? NSNumber)?.doubleValue }.reduce(0, +)
                    if n > 0 { used = n }
                }
                // cheap filter before decoding
                let hasTitle = title == nil && line.count < 4000 && line.firstRange(of: Data("\"ai-title\"".utf8)) != nil
                let hasBranch = branch == nil && line.firstRange(of: Data("\"gitBranch\"".utf8)) != nil
                guard hasTitle || hasBranch,
                      let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any] else { continue }
                if hasTitle, let t = obj["aiTitle"] as? String, !t.isEmpty { title = String(t.prefix(48)) }
                if hasBranch, let b = obj["gitBranch"] as? String, !b.isEmpty { branch = b }
            }
            DispatchQueue.main.async {
                if let title { f.logTitle = title }
                if let fixed { f.fixedTitle = fixed }
                if title != nil { Whereabouts.findByTitle(f) }
                if let branch { f.branch = branch }
                if let used {
                    // limit: 200k, or 1 million when the session has already gone past that
                    let limit = used > 200_000 ? 1_000_000.0 : 200_000.0
                    f.context = Float(min(1, used / limit))
                }
            }
        }
    }

    /// Codex: the conversation file (rollout) has the token usage with the real limit (token_count), the branch in
    /// session_meta, and the title lives in the index ~/.codex/session_index.jsonl (thread_name by id).
    private static func readCodex(_ url: URL, to f: Fish) {
        let session = String(f.id.split(separator: ":", maxSplits: 1).last ?? "")
        DispatchQueue.global(qos: .utility).async {
            guard let h = try? FileHandle(forReadingFrom: url) else { return }
            defer { try? h.close() }
            let start = (try? h.read(upToCount: 64 * 1024)) ?? Data()
            let size = (try? h.seekToEnd()) ?? 0
            let window: UInt64 = 512 * 1024
            try? h.seek(toOffset: size > window ? size - window : 0)
            let end = (try? h.readToEnd()) ?? Data()

            // context: the last token_count (input tokens of the last reply / model window)
            var context: Float?
            for line in end.split(separator: UInt8(ascii: "\n")).reversed() where line.firstRange(of: Data("\"token_count\"".utf8)) != nil {
                guard let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                      let info = (obj["payload"] as? [String: Any])?["info"] as? [String: Any],
                      let last = info["last_token_usage"] as? [String: Any] else { continue }
                let used = ((last["input_tokens"] as? NSNumber)?.doubleValue ?? 0) + ((last["output_tokens"] as? NSNumber)?.doubleValue ?? 0)
                let limit = (info["model_context_window"] as? NSNumber)?.doubleValue ?? 272_000
                if used > 0, limit > 0 { context = Float(min(1, used / limit)) }
                break
            }
            // branch: in session_meta, right at the start
            var branch: String?
            if let first = start.split(separator: UInt8(ascii: "\n")).first,
               let obj = (try? JSONSerialization.jsonObject(with: Data(first))) as? [String: Any],
               let git = (obj["payload"] as? [String: Any])?["git"] as? [String: Any] {
                branch = git["branch"] as? String
            }
            // title: the last thread_name of this session in the index
            var title: String?
            let indexURL = URL(fileURLWithPath: NSHomeDirectory() + "/.codex/session_index.jsonl")
            if let hi = try? FileHandle(forReadingFrom: indexURL) {
                let t = (try? hi.seekToEnd()) ?? 0
                try? hi.seek(toOffset: t > 256 * 1024 ? t - 256 * 1024 : 0)
                let d = (try? hi.readToEnd()) ?? Data()
                try? hi.close()
                for line in d.split(separator: UInt8(ascii: "\n")).reversed() where line.firstRange(of: Data(session.utf8)) != nil {
                    if let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                       obj["id"] as? String == session, let n = obj["thread_name"] as? String, !n.isEmpty {
                        title = String(n.prefix(48)); break
                    }
                }
            }
            DispatchQueue.main.async {
                if let title { f.logTitle = title }
                if let branch { f.branch = branch }
                if let context { f.context = context }
            }
        }
    }

    /// The text of the assistant's last reply in the Claude Code transcript.
    static func lastReply(_ path: String, _ ready: @escaping (String?) -> Void) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.pathExtension == "jsonl", url.path.hasPrefix(NSHomeDirectory() + "/") else { ready(nil); return }
        // give Claude a moment to finish writing the reply
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.8) {
            var text: String?
            if let h = try? FileHandle(forReadingFrom: url) {
                let t = (try? h.seekToEnd()) ?? 0
                try? h.seek(toOffset: t > 512 * 1024 ? t - 512 * 1024 : 0)
                let d = (try? h.readToEnd()) ?? Data()
                try? h.close()
                for line in d.split(separator: UInt8(ascii: "\n")).reversed() where line.firstRange(of: Data("\"type\":\"assistant\"".utf8)) != nil {
                    guard let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                          let content = (obj["message"] as? [String: Any])?["content"] as? [[String: Any]] else { continue }
                    let parts = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                    if !parts.isEmpty { text = parts.joined(separator: "\n"); break }
                }
            }
            DispatchQueue.main.async { ready(text) }
        }
    }

    /// Codex: renames the conversation by appending a line to the index (~/.codex/session_index.jsonl), which is where the name lives.
    static func renameCodex(session: String, name: String) -> Bool {
        let url = URL(fileURLWithPath: NSHomeDirectory() + "/.codex/session_index.jsonl")
        let fmt = ISO8601DateFormatter(); fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = try? JSONSerialization.data(withJSONObject: ["id": session, "thread_name": name, "updated_at": fmt.string(from: Date())]),
              let h = try? FileHandle(forWritingTo: url) else { return false }
        defer { try? h.close() }
        h.seekToEndOfFile()
        h.write(d + Data("\n".utf8))
        return true
    }
}
