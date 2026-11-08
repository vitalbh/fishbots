import AppKit

/// "Where is it?": the 2nd line of the label and the click that takes you to the session.
///
/// With Rex, the app talks straight to `rex` (session › tab and focus on the right pane); with Herdr, to `herdr-app`
/// (shows the agent) and `herdr-core` (where it is, typing into it).
/// Without Rex, it runs a generic script (iTerm, Terminal, Ghostty, WezTerm, kitty, tmux, Warp, VS Code and its forks, Zed…),
/// which can be replaced by your own in ~/Library/Application Support/Fishbots/goto.sh.
enum Whereabouts {
    static func update(_ f: Fish, with o: [String: String]) {
        guard !o.isEmpty else { return }
        // if the event says where it came from (terminal, app, Rex…), that replaces what was there (the session may have moved);
        // otherwise, it only adds (e.g. the cwd)
        let provenance = ["term", "app", "rex_session", "rex_block", "herdr", "tty", "pid", "iterm", "tmux", "entrypoint"]
        var new = o.keys.contains(where: provenance.contains) ? o : f.whereabouts
        if new == o, let cwd = f.whereabouts["cwd"], o["cwd"] == nil { new["cwd"] = cwd }
        if new != o { for (k, v) in o { new[k] = v } }
        // a Rex pane found by lookup stays (the session's own events don't know it)
        if new["rex_block"] == nil, let (s, b) = foundInRex[f.id] {
            new["rex_session"] = s; new["rex_block"] = b; new["term"] = "rex"; new["rex_lookup"] = "done"
        }
        let changed = new != f.whereabouts
        f.whereabouts = new
        Providers.refresh(f)   // the shape can depend on the terminal
        if changed || f.sub == nil { detail(f) }
    }

    static func terminalName(_ t: String) -> String {
        switch t {
        case "iTerm.app": return "iTerm"
        case "Apple_Terminal": return "Terminal"
        case "vscode": return "VS Code"
        case "ghostty": return "Ghostty"
        case "WarpTerminal": return "Warp"
        case "zed": return "Zed"
        case "rex": return "Rex"
        case "herdr": return "Herdr"
        default: return t
        }
    }

    /// Recomputes the 2nd line of the label. For Rex, asks for the session and tab names.
    static func detail(_ f: Fish) {
        let o = f.whereabouts
        if let t = o["herdr"], let core = herdrCore {
            // "space / tab" from herdr-core, and the terminal's title (the conversation's)
            DispatchQueue.global(qos: .utility).async {
                let info = json(run(core, ["get", t, "--json"]))
                let place = ((info?["labels"] as? [String: Any])?["where"] as? String)?
                    .replacingOccurrences(of: " / ", with: " › ")
                let title = (info?["title"] as? String).map(cleanTitle).flatMap { $0.isEmpty ? nil : $0 }
                DispatchQueue.main.async {
                    f.sub = place.map { "Herdr · " + $0 } ?? "Herdr"
                    if let title { f.title = title }
                }
            }
            return
        }
        if let s = o["rex_session"], let b = o["rex_block"], let bin = rexBin(o) {
            DispatchQueue.global(qos: .utility).async {
                let sess = json(run(bin, ["--timeout", "3s", "session", "inspect", s, "--json"]))
                let blk = json(run(bin, ["--timeout", "3s", "block", "inspect", b, "--json"]))
                let tit = json(run(bin, ["--timeout", "3s", "block", "call", "-b", b, "title"]))?["title"] as? String
                var parts: [String] = []
                if let l = sess?["label"] as? String, !l.isEmpty { parts.append(l) }
                if let w = (blk?["block"] as? [String: Any])?["window_id"] as? String,
                   let wins = sess?["windows"] as? [[String: Any]],
                   let win = wins.first(where: { $0["window_id"] as? String == w }) {
                    if let wl = win["label"] as? String, !wl.isEmpty, !wl.hasPrefix("Window ") { parts.append(wl) }
                    if let pl = (blk?["block"] as? [String: Any])?["label"] as? String, !pl.isEmpty, !["shell", "terminal", "zsh", "bash"].contains(pl) {
                        parts.append(pl)
                    } else if let pos = position(block: b, window: win) { parts.append(pos) }
                }
                let sub = parts.isEmpty ? "Rex" : parts.joined(separator: " › ")
                let title = tit.map(cleanTitle).flatMap { $0.isEmpty ? nil : $0 }
                DispatchQueue.main.async { f.sub = sub; f.title = title }
            }
            return
        }
        // without the Rex variables, but maybe in a Rex pane: look it up by process (once)
        if o["rex_lookup"] == nil, o["entrypoint"] != "claude-desktop", o["herdr"] == nil, o["tty"] != nil || o["pid"] != nil, let bin = rexBin(o) {
            f.whereabouts["rex_lookup"] = "done"
            DispatchQueue.global(qos: .utility).async {
                if let (s, b) = findInRex(bin: bin, tty: o["tty"], pid: o["pid"]) {
                    DispatchQueue.main.async { attach(f, session: s, block: b) }
                } else {
                    DispatchQueue.main.async { findByTitle(f) }
                }
            }
        }
        var parts: [String] = []
        if o["entrypoint"] == "claude-desktop" { parts.append(tr("Claude (desktop)")) }
        else if o["term"] == "vscode", let app = o["app"] {
            // Cursor, Windsurf… say they're VS Code: the app they really run in has the name
            parts.append(((app as NSString).lastPathComponent as NSString).deletingPathExtension)
        }
        else if let t = o["term"] { parts.append(terminalName(t)) }
        else if let app = o["app"] {
            let name = ((app as NSString).lastPathComponent as NSString).deletingPathExtension
            parts.append(name == "ClaudeCode" ? tr("Claude Code (segundo plano)") : name)
        }
        if let tm = o["tmux"] { parts.append("tmux \(tm)") } else if let tty = o["tty"] { parts.append(tty) }
        if !parts.isEmpty { f.sub = parts.joined(separator: " · ") }
    }

    /// A session remembered from before the app restarted: where it was, including a Rex pane found by lookup.
    static func restore(_ f: Fish, _ o: [String: String]) {
        f.whereabouts = o
        if o["rex_lookup"] == "done", let s = o["rex_session"], let b = o["rex_block"] { foundInRex[f.id] = (s, b) }
        Providers.refresh(f)
        detail(f)
    }

    /// Rex panes found by lookup, by fish id.
    private static var foundInRex: [String: (String, String)] = [:]
    /// The title last searched for, by fish id (so each title is looked up once).
    private static var titleTried: [String: String] = [:]

    private static func attach(_ f: Fish, session s: String, block b: String) {
        foundInRex[f.id] = (s, b)
        f.whereabouts["rex_session"] = s
        f.whereabouts["rex_block"] = b
        f.whereabouts["term"] = "rex"
        Providers.refresh(f)
        detail(f)
    }

    /// Background sessions (Claude Code's "segundo plano") run outside the terminal: their Rex pane only shows a
    /// client, so the process lookup can't find it. The pane's title is the conversation's title, though: look for
    /// exactly one terminal pane with it. Called when the title is known (it comes from the transcript).
    static func findByTitle(_ f: Fish) {
        guard f.whereabouts["rex_block"] == nil, f.whereabouts["entrypoint"] != "claude-desktop",
              let t = (f.logTitle ?? f.title).map(cleanTitle), !t.isEmpty, titleTried[f.id] != t,
              let bin = rexBin(f.whereabouts) else { return }
        titleTried[f.id] = t
        DispatchQueue.global(qos: .utility).async {
            var found: [(String, String)] = []
            let sessions = (json(run(bin, ["--timeout", "3s", "ls", "--json"]))?["sessions"] as? [[String: Any]] ?? [])
                .compactMap { $0["session_id"] as? String }
            for s in sessions {
                let blocks = json(run(bin, ["--timeout", "3s", "block", "ls", "-s", s, "--json"]))?["blocks"] as? [[String: Any]] ?? []
                for b in blocks where (b["creator_name"] as? String) == "com.superlogical.terminal" {
                    guard let id = b["block_id"] as? String,
                          let pt = json(run(bin, ["--timeout", "3s", "block", "call", "-b", id, "title"]))?["title"] as? String else { continue }
                    if cleanTitle(pt) == t { found.append((s, id)) }
                }
            }
            guard found.count == 1 else { return }
            DispatchQueue.main.async { if f.whereabouts["rex_block"] == nil { attach(f, session: found[0].0, block: found[0].1) } }
        }
    }

    /// Strips the spinner (◐ ✳ ⠋…) from the start of the title.
    static func cleanTitle(_ t: String) -> String {
        let withoutSpinner = t.drop { !$0.isLetter && !$0.isNumber }
        return String(withoutSpinner.prefix(48)).trimmingCharacters(in: .whitespaces)
    }

    /// Position of the pane in the tab ("esquerda", "direita embaixo"…), if the tab has more than one.
    static func position(block: String, window: [String: Any]) -> String? {
        var rects: [String: [Double]] = [:]
        func walk(_ n: [String: Any]) {
            if let id = n["block_id"] as? String, let r = n["rect"] as? [NSNumber] { rects[id] = r.map(\.doubleValue) }
            if let sp = n["split"] as? [String: Any] {
                if let a = sp["before"] as? [String: Any] { walk(a) }
                if let b = sp["after"] as? [String: Any] { walk(b) }
            }
        }
        for l in (window["layers"] as? [[String: Any]]) ?? [] {
            if let lay = l["layout"] as? [String: Any] { walk(lay) }
        }
        guard rects.count > 1, let r = rects[block], r.count == 4 else { return nil }
        let cx = r[0] + r[2] / 2, cy = r[1] + r[3] / 2
        var p: [String] = []
        if r[2] < 0.67 { p.append(tr(cx < 0.4 ? "esquerda" : cx > 0.6 ? "direita" : "meio")) }
        if r[3] < 0.67 { p.append(tr(cy < 0.4 ? "em cima" : cy > 0.6 ? "embaixo" : "no meio")) }
        return p.isEmpty ? nil : p.joined(separator: " ")
    }

    /// Takes you to the fish. Returns false if there is nowhere to go.
    @discardableResult
    static func go(_ f: Fish) -> Bool {
        if let l = f.link, let u = URL(string: l) {
            NSWorkspace.shared.open(u)
            return true
        }
        let o = f.whereabouts
        if let s = o["rex_session"], let b = o["rex_block"], let bin = rexBin(o) {
            DispatchQueue.global(qos: .userInitiated).async { goRex(bin: bin, session: s, block: b, whereabouts: o) }
            return true
        }
        if let t = o["herdr"], let app = herdrApp {
            DispatchQueue.global(qos: .userInitiated).async { goHerdr(app: app, terminal: t) }
            return true
        }
        if o["entrypoint"] == "claude-desktop" {
            let app = o["app"].flatMap { $0.hasSuffix(".app") ? $0 : nil } ?? "/Applications/Claude.app"
            NSWorkspace.shared.open(URL(fileURLWithPath: app))
            return true
        }
        guard o["term"] != nil || o["tmux"] != nil || o["app"] != nil || o["cwd"] != nil else { return false }
        var env = o
        env["title"] = f.displayTitle   // the terminal's title often is the conversation's (Ghostty picks the tab by it)
        DispatchQueue.global(qos: .userInitiated).async { runScript(env) }
        return true
    }

    // MARK: - typing into the session (reply, stop)

    enum Target { case rex(bin: String, block: String), herdr(core: String, terminal: String), ghostty(tty: String), iterm(String), tmux(String) }

    /// Where it's safe to type into the session's exact terminal (Rex, Herdr, iTerm or tmux). Otherwise, nil.
    static func target(_ f: Fish) -> Target? {
        let o = f.whereabouts
        if let b = o["rex_block"], let bin = rexBin(o) { return .rex(bin: bin, block: b) }
        if let t = o["herdr"], let core = herdrCore { return .herdr(core: core, terminal: t) }
        if o["term"] == "ghostty", let tty = o["tty"], !tty.isEmpty { return .ghostty(tty: tty) }
        if o["term"] == "iTerm.app", let i = o["iterm"] { return .iterm(String(i.split(separator: ":").last ?? "")) }
        if let t = o["tmux"], !t.isEmpty { return .tmux(t) }
        return nil
    }

    /// Sends a reply (one line, with Enter). First checks it really is the agent in the terminal (Rex).
    static func reply(_ f: Fish, _ text: String, ready: @escaping (String?) -> Void) {
        let line = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, let d = target(f) else { ready(tr("não sei digitar nessa sessão")); return }
        let names = Providers.processNames(f.source)
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: String?
            switch d {
            case .rex(let bin, let block):
                if !agentInRex(bin: bin, block: block, names: names) { failure = tr("o terminal não está com o agente na frente") }
                else {
                    _ = run(bin, ["--timeout", "3s", "send", "-b", block, line])
                    // pause before Enter: text that arrives fast is treated as a paste, and a pasted Enter becomes a line break
                    Thread.sleep(forTimeInterval: 0.5)
                    _ = run(bin, ["--timeout", "3s", "send-key", "-b", block, "enter"])
                }
            case .herdr(let core, let t):
                if !agentInHerdr(core: core, terminal: t, source: f.source, names: names) { failure = tr("o terminal não está com o agente na frente") }
                else {
                    // pastes and submits; --force: a session waiting for you counts as "blocked", and that's when the card replies
                    _ = run(core, ["send", "--force", t, line])
                }
            case .ghostty(let tty):
                if !agentInGhostty(tty: tty, names: names) { failure = tr("o terminal não está com o agente na frente") }
                else {
                    failure = osa(ghosttyScript("input text (item 2 of argv) to t"), [tty, line])
                    Thread.sleep(forTimeInterval: 0.5)
                    if failure == nil { failure = osa(ghosttyScript("send key \"enter\" to t"), [tty]) }
                }
            case .iterm(let id):
                failure = osa(itermScript(id: id, action: "write text item 2 of argv newline NO"), [id, line])
                Thread.sleep(forTimeInterval: 0.5)
                if failure == nil { failure = osa(itermScript(id: id, action: "write text \"\""), [id]) }
            case .tmux(let pane):
                let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "tmux"
                _ = run(tmux, ["send-keys", "-t", pane, "-l", line])
                Thread.sleep(forTimeInterval: 0.5)
                _ = run(tmux, ["send-keys", "-t", pane, "Enter"])
            }
            DispatchQueue.main.async { ready(failure) }
        }
    }

    /// Esc: interrupts what the agent is doing.
    static func stop(_ f: Fish) {
        guard let d = target(f) else { return }
        let names = Providers.processNames(f.source)
        DispatchQueue.global(qos: .userInitiated).async {
            switch d {
            case .rex(let bin, let block):
                if agentInRex(bin: bin, block: block, names: names) { _ = run(bin, ["--timeout", "3s", "send-key", "-b", block, "escape"]) }
            case .herdr(let core, let t):
                if agentInHerdr(core: core, terminal: t, source: f.source, names: names) { _ = run(core, ["keys", t, "esc"]) }
            case .ghostty(let tty):
                if agentInGhostty(tty: tty, names: names) { _ = osa(ghosttyScript("send key \"escape\" to t"), [tty]) }
            case .iterm(let id):
                _ = osa(itermScript(id: id, action: "write text (character id 27) newline NO"), [id])
            case .tmux(let pane):
                let tmux = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux"].first { FileManager.default.isExecutableFile(atPath: $0) } ?? "tmux"
                _ = run(tmux, ["send-keys", "-t", pane, "Escape"])
            }
        }
    }

    /// Is the foreground process in the pane the session's agent?
    private static func agentInRex(bin: String, block: String, names: [String]) -> Bool {
        guard let pr = json(run(bin, ["--timeout", "3s", "block", "call", "-b", block, "process"])),
              let fg = pr["foreground"] as? [String: Any] else { return false }
        let all = ((fg["path"] as? String) ?? "") + " " + ((fg["argv0"] as? String) ?? "") + " " + ((fg["name"] as? String) ?? "")
        return Providers.isAgentProcess(all, names: names)
    }

    // MARK: - Ghostty

    /// A script acting on the session's Ghostty terminal (`t`), found by its tty (item 1 of argv: "ttys016").
    private static func ghosttyScript(_ action: String) -> String {
        """
        on run argv
          tell application id "com.mitchellh.ghostty"
            set t to first terminal whose tty is ("/dev/" & item 1 of argv)
            \(action)
          end tell
        end run
        """
    }

    /// Is the terminal's foreground process the agent? (Ghostty gives its pid.)
    private static func agentInGhostty(tty: String, names: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", ghosttyScript("return pid of t"), tty]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let pid = Int(String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        let ps = String(decoding: run("/bin/ps", ["-o", "comm=", "-p", String(pid)]), as: UTF8.self)
        return Providers.isAgentProcess(ps, names: names)
    }

    // MARK: - Herdr

    private static func local(_ name: String) -> String? {
        // the real home (not CFFIXED_USER_HOME's): that's where Herdr installs itself
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return [home + "/.local/bin/" + name, "/opt/homebrew/bin/" + name, "/usr/local/bin/" + name]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    private static var herdrCore: String? { local("herdr-core") ?? local("hc") }
    private static var herdrApp: String? { local("herdr-app") }
    private static let herdrBundle = "dev.herdr.app"

    /// Shows the agent's terminal in the Herdr window (opening it if needed) and brings Herdr forward.
    private static func goHerdr(app: String, terminal t: String) {
        if NSRunningApplication.runningApplications(withBundleIdentifier: herdrBundle).isEmpty {
            _ = run("/usr/bin/open", ["-b", herdrBundle])
            Thread.sleep(forTimeInterval: 1.5)
        }
        _ = run(app, ["do", "agent.focus", "--terminal", t])
        DispatchQueue.main.async {
            NSRunningApplication.runningApplications(withBundleIdentifier: herdrBundle).first?.activate()
        }
    }

    /// Is the terminal's foreground program still the session's agent (it may have exited back to the shell)?
    private static func agentInHerdr(core: String, terminal t: String, source: String, names: [String]) -> Bool {
        guard let info = json(run(core, ["get", t, "--json"])), info["state"] as? String == "live" else { return false }
        if let fg = info["foreground"] as? [String: Any] {
            let argv = (fg["argv"] as? [String])?.first ?? ""
            if Providers.isAgentProcess(argv + " " + ((fg["name"] as? String) ?? ""), names: names) { return true }
        }
        return ((info["status"] as? [String: Any])?["app"] as? String) == source
    }

    private static func itermScript(id: String, action: String) -> String {
        """
        on run argv
          tell application id "com.googlecode.iterm2"
            repeat with w in windows
              repeat with t in tabs of w
                repeat with s in sessions of t
                  if unique id of s is item 1 of argv then
                    tell s to \(action)
                    return
                  end if
                end repeat
              end repeat
            end repeat
          end tell
        end run
        """
    }

    /// Runs an AppleScript; returns the error message, if any.
    private static func osa(_ script: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script] + args
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return "\(error)" }
        p.waitUntilExit()
        return p.terminationStatus == 0 ? nil : String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    /// Renames the Rex pane where the session runs.
    static func renamePane(_ f: Fish, _ name: String) {
        guard let b = f.whereabouts["rex_block"], let bin = rexBin(f.whereabouts) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = run(bin, ["--timeout", "3s", "block", "rename", b, name])
            DispatchQueue.main.async { detail(f) }
        }
    }

    /// Renames the Rex session where the fish is.
    static func renameRex(_ f: Fish, _ name: String) {
        guard let s = f.whereabouts["rex_session"], let bin = rexBin(f.whereabouts) else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = run(bin, ["--timeout", "3s", "session", "rename", s, name])
            DispatchQueue.main.async { detail(f) }
        }
    }

    // MARK: - Rex

    private static func rexBin(_ o: [String: String]) -> String? {
        let candidates = [o["rex_bin"], NSString("~/.local/bin/rex").expandingTildeInPath, "/opt/homebrew/bin/rex", "/usr/local/bin/rex"]
        return candidates.compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Finds the Rex pane running the session, by Claude's pid or by the tty's processes.
    private static func findInRex(bin: String, tty: String?, pid: String?) -> (String, String)? {
        var pids = Set<Int>()
        if let pid, let n = Int(pid) { pids.insert(n) }
        if let tty, tty.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil {
            let out = String(decoding: run("/bin/ps", ["-o", "pid=", "-t", tty]), as: UTF8.self)
            for l in out.split(separator: "\n") { if let n = Int(l.trimmingCharacters(in: .whitespaces)) { pids.insert(n) } }
        }
        guard !pids.isEmpty else { return nil }
        let sessions = (json(run(bin, ["--timeout", "3s", "ls", "--json"]))?["sessions"] as? [[String: Any]] ?? [])
            .compactMap { $0["session_id"] as? String }
        for s in sessions {
            let blocks = json(run(bin, ["--timeout", "3s", "block", "ls", "-s", s, "--json"]))?["blocks"] as? [[String: Any]] ?? []
            for b in blocks where (b["creator_name"] as? String) == "com.superlogical.terminal" {
                guard let id = b["block_id"] as? String,
                      let pr = json(run(bin, ["--timeout", "3s", "block", "call", "-b", id, "process"])) else { continue }
                var fromThere: [Int] = []
                if let fg = (pr["foreground"] as? [String: Any])?["pid"] as? Int { fromThere.append(fg) }
                if let ch = (pr["child"] as? [String: Any])?["pid"] as? Int { fromThere.append(ch) }
                if fromThere.contains(where: pids.contains) { return (s, id) }
            }
        }
        return nil
    }

    private static func goRex(bin: String, session s: String, block b: String, whereabouts o: [String: String]) {
        let blk = json(run(bin, ["--timeout", "3s", "block", "inspect", b, "--json"]))?["block"] as? [String: Any]
        let window = blk?["window_id"] as? String
        let owner = blk?["owner"] as? String
        let clients = json(run(bin, ["--timeout", "3s", "client", "ls", "--json"]))?["clients"] as? [[String: Any]] ?? []
        func isApp(_ c: [String: Any]) -> Bool { (c["info"] as? [String: Any])?["kind"] as? String == "app" }
        let app = clients.first { isApp($0) && $0["client_id"] as? String == owner }
            ?? clients.first { isApp($0) && (($0["session_ids"] as? [String]) ?? []).contains(s) }
            ?? clients.first(where: isApp)
        guard let app, let cid = app["client_id"] as? String else {
            runScript(o)   // Rex without an open app: try the generic path
            return
        }
        var args = ["--timeout", "3s", "-C", cid, "do", "session.select", "session_id=\(s)"]
        if let window { args.append("window_id=\(window)") }
        _ = run(bin, args)
        _ = run(bin, ["--timeout", "3s", "block", "focus", b, "-s", s])
        if let pid = (app["principal"] as? [String: Any])?["pid"] as? Int {
            DispatchQueue.main.async { NSRunningApplication(processIdentifier: pid_t(pid))?.activate() }
        }
    }

    // MARK: - generic

    static let defaultScript = #"""
    #!/bin/sh
    # Takes you to a session's terminal. Fishbots passes:
    #   WHERE_TERM (TERM_PROGRAM), WHERE_ITERM, WHERE_TTY, WHERE_TMUX, WHERE_WEZTERM, WHERE_KITTY, WHERE_CWD,
    #   WHERE_APP (the .app the session runs in), WHERE_PID (the agent's process), WHERE_TITLE (the conversation's title)
    PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"

    if [ -n "$WHERE_TMUX" ] && command -v tmux >/dev/null; then
      tmux select-window -t "$WHERE_TMUX" 2>/dev/null
      tmux select-pane -t "$WHERE_TMUX" 2>/dev/null
    fi

    case "$WHERE_TERM" in
      iTerm.app)
        id="${WHERE_ITERM#*:}"
        osascript - "$id" <<'OSA'
    on run argv
      set alvo to item 1 of argv
      tell application id "com.googlecode.iterm2"
        activate
        repeat with w in windows
          repeat with t in tabs of w
            repeat with s in sessions of t
              if unique id of s is alvo then
                select w
                tell t to select
                tell s to select
                return
              end if
            end repeat
          end repeat
        end repeat
      end tell
    end run
    OSA
        ;;
      Apple_Terminal)
        osascript - "/dev/$WHERE_TTY" <<'OSA'
    on run argv
      set alvo to item 1 of argv
      tell application id "com.apple.Terminal"
        activate
        repeat with w in windows
          repeat with t in tabs of w
            if tty of t is alvo then
              set selected of t to true
              set index of w to 1
              return
            end if
          end repeat
        end repeat
      end tell
    end run
    OSA
        ;;
      WezTerm) wezterm cli activate-pane --pane-id "$WHERE_WEZTERM" 2>/dev/null; open -a WezTerm ;;
      kitty)   kitty @ focus-window --match "id:$WHERE_KITTY" 2>/dev/null; open -a kitty ;;
      ghostty)
        # Ghostty's AppleScript (1.3+): the session's own terminal by its tty; without that (older dictionaries), the
        # terminal in the session's folder, the one titled like the conversation if there are several; else just Ghostty
        osascript - "$WHERE_TTY" <<'OSA' 2>/dev/null || osascript - "$WHERE_CWD" "$WHERE_TITLE" <<'OSA2' 2>/dev/null || open -a Ghostty
    on run argv
      tell application id "com.mitchellh.ghostty"
        set t to first terminal whose tty is ("/dev/" & item 1 of argv)
        focus t
        activate
      end tell
    end run
    OSA
    on run argv
      set dir to item 1 of argv
      set wanted to item 2 of argv
      tell application id "com.mitchellh.ghostty"
        set found to every terminal whose working directory is dir
        if (count of found) is 0 then set found to every terminal whose working directory contains dir
        if (count of found) is 0 then error "not found"
        set pick to item 1 of found
        if wanted is not "" then
          repeat with t in found
            if name of t contains wanted then
              set pick to contents of t
              exit repeat
            end if
          end repeat
        end if
        focus pick
        activate
      end tell
    end run
    OSA2
        ;;
      vscode)
        # Cursor, Windsurf and other forks also say "vscode": open the app the session really runs in
        case "$WHERE_APP" in
          ""|*"Visual Studio Code"*)
            if command -v code >/dev/null; then code "$WHERE_CWD"; else open -a "Visual Studio Code" ${WHERE_CWD:+"$WHERE_CWD"}; fi ;;
          *) open -a "$WHERE_APP" ${WHERE_CWD:+"$WHERE_CWD"} ;;
        esac ;;
      WarpTerminal) open -a Warp ;;   # Warp can't be told which tab
      zed)     open -a Zed ${WHERE_CWD:+"$WHERE_CWD"} ;;
      tmux)    : ;;
      "")      if [ -n "$WHERE_APP" ]; then open -a "$WHERE_APP"; elif [ -n "$WHERE_CWD" ]; then open "$WHERE_CWD"; fi ;;
      *)       open -a "$WHERE_TERM" 2>/dev/null || { [ -n "$WHERE_CWD" ] && open "$WHERE_CWD"; } ;;
    esac
    """#

    /// goto.sh in the Fishbots folder (or ir.sh, its old name).
    static var userScript: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fishbots")
        let legacy = dir.appendingPathComponent("ir.sh")
        return FileManager.default.isReadableFile(atPath: legacy.path) ? legacy : dir.appendingPathComponent("goto.sh")
    }

    private static func runScript(_ o: [String: String]) {
        var env = ProcessInfo.processInfo.environment
        // WHERE_*; ONDE_* too, for scripts written for older versions
        for (k, v) in o { env["WHERE_" + k.uppercased()] = v; env["ONDE_" + k.uppercased()] = v }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        if FileManager.default.isReadableFile(atPath: userScript.path) {
            p.arguments = [userScript.path]
        } else {
            p.arguments = ["-c", defaultScript]
        }
        p.environment = env
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    // MARK: - utilities

    private static func run(_ bin: String, _ args: [String]) -> Data {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: bin)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return Data() }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return d
    }

    private static func json(_ d: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
}
