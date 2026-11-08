import AppKit

/// "Where is it?": the 2nd line of the label and the click that takes you to the session.
///
/// With Rex, the app talks straight to `rex` (session › tab and focus on the right pane).
/// Without Rex, it runs a generic script (iTerm, Terminal, WezTerm, kitty, tmux, VS Code…),
/// which can be replaced by your own in ~/Library/Application Support/Fishbots/goto.sh.
enum Whereabouts {
    static func update(_ f: Fish, with o: [String: String]) {
        guard !o.isEmpty else { return }
        // if the event says where it came from (terminal, app, Rex…), that replaces what was there (the session may have moved);
        // otherwise, it only adds (e.g. the cwd)
        let provenance = ["term", "app", "rex_session", "rex_block", "tty", "pid", "iterm", "tmux", "entrypoint"]
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
        case "rex": return "Rex"
        default: return t
        }
    }

    /// Recomputes the 2nd line of the label. For Rex, asks for the session and tab names.
    static func detail(_ f: Fish) {
        let o = f.whereabouts
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
        if o["rex_lookup"] == nil, o["entrypoint"] != "claude-desktop", o["tty"] != nil || o["pid"] != nil, let bin = rexBin(o) {
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
        if o["entrypoint"] == "claude-desktop" {
            let app = o["app"].flatMap { $0.hasSuffix(".app") ? $0 : nil } ?? "/Applications/Claude.app"
            NSWorkspace.shared.open(URL(fileURLWithPath: app))
            return true
        }
        guard o["term"] != nil || o["tmux"] != nil || o["app"] != nil || o["cwd"] != nil else { return false }
        DispatchQueue.global(qos: .userInitiated).async { runScript(o) }
        return true
    }

    // MARK: - typing into the session (reply, stop)

    enum Target { case rex(bin: String, block: String), iterm(String), tmux(String) }

    /// Where it's safe to type into the session's exact terminal (Rex, iTerm or tmux). Otherwise, nil.
    static func target(_ f: Fish) -> Target? {
        let o = f.whereabouts
        if let b = o["rex_block"], let bin = rexBin(o) { return .rex(bin: bin, block: b) }
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
    #   WHERE_APP (the .app that opened the session, when there is no TERM_PROGRAM), WHERE_PID (Claude's process)
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
      ghostty) open -a Ghostty ;;
      vscode)  if command -v code >/dev/null; then code "$WHERE_CWD"; else open -a "Visual Studio Code"; fi ;;
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
