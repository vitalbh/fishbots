import AppKit

/// What Spotify or the Music app is playing: it becomes a special fish (a betta that dances and lets out notes, with
/// "♪ track — artist" as its name) that glows when the song changes, fades and sinks while paused, and leaves when
/// the player stops. The aquarium's own ambient music steps aside while it plays.
/// No polling: both players announce every change (distributed notifications); the app asks once when it opens.
final class NowPlaying {
    struct Track: Equatable {
        let player: String      // "Spotify" or "Music"
        let title: String
        let artist: String
        let id: String          // Spotify's track URI (opens it on click); empty for Music
    }

    /// Something is playing right now (the ambient music waits).
    private(set) static var playing = false

    unowned let tank: Tank
    private var current: Track?
    private var leaveTimer: Timer?
    /// Where the song is: the position read at the last change, counted forward by the clock while it plays.
    fileprivate var clock: (pos: Double, at: CFTimeInterval, dur: Double, running: Bool)?
    /// Listens to the player so the visualizers dance with it (opt-in, SongEars.swift).
    let ears: SongEars

    static let source = "music"
    static let entity = "now-playing"
    private static let players = [("Spotify", "com.spotify.client"), ("Music", "com.apple.Music")]

    /// On by default; Preferências → Geral.
    static var enabled: Bool {
        get { UserDefaults.standard.flag("nowPlaying") }
        set { UserDefaults.standard.set(newValue, forKey: "nowPlaying"); if !newValue { shared?.clear() } else { shared?.askOnce() } }
    }
    private static weak var shared: NowPlaying?

    init(tank: Tank) {
        self.tank = tank
        ears = SongEars(tank: tank, source: Self.source, entity: Self.entity)
        ears.remaining = { [weak self] in self?.progress.map { $0.dur - $0.pos } }
        Self.shared = self
        SongEars.onToggle = { [weak self] on in
            guard let self else { return }
            self.ears.follow(on && Self.playing ? self.current?.player : nil)
        }
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] n in
            self?.heard("Spotify", n.userInfo)
        }
        dnc.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] n in
            self?.heard("Music", n.userInfo)
        }
        // a player closing doesn't always announce "stopped"
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if let self, let id = app?.bundleIdentifier, let name = Self.players.first(where: { $0.1 == id })?.0, self.current?.player == name { self.clear() }
        }
        askOnce()
    }

    /// From a player's announcement: "Player State" (Playing / Paused / Stopped), "Name", "Artist" and, on Spotify, "Track ID".
    private func heard(_ player: String, _ info: [AnyHashable: Any]?) {
        guard Self.enabled, let info else { return }
        let state = (info["Player State"] as? String ?? "").lowercased()
        if state == "playing" || state == "paused" { syncClock(player, running: state == "playing") }
        switch state {
        case "playing":
            let t = Track(player: player, title: info["Name"] as? String ?? "", artist: info["Artist"] as? String ?? "",
                          id: info["Track ID"] as? String ?? "")
            update(t, paused: false)
        case "paused":
            if current?.player == player || current == nil { update(nil, paused: true) }
        default:
            if current?.player == player { clear() }
        }
    }

    /// When the app opens (or the fish is turned back on): what was already playing, asked once, only to open players.
    private func askOnce() {
        guard Self.enabled else { return }
        let open = Self.players.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.1).isEmpty }
        guard !open.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            var found: Track?
            for (name, _) in open {
                let parts = Self.ask(name).components(separatedBy: "\t")
                if parts.first == "playing", parts.count >= 4 { found = Track(player: name, title: parts[1], artist: parts[2], id: parts[3]); break }
            }
            DispatchQueue.main.async {
                if let found { self.update(found, paused: false); self.syncClock(found.player, running: true) }
            }
        }
    }

    private func update(_ t: Track?, paused: Bool) {
        if let t {
            Self.playing = true
            leaveTimer?.invalidate()
            leaveTimer = nil
            let changed = t != current
            let wasPlaying = current != nil
            current = t
            ears.follow(t.player)
            let name = t.title + (t.artist.isEmpty ? "" : " — " + t.artist)
            tank.upsert(source: Self.source, entity: Self.entity, state: .busy, label: "♪ " + String(name.prefix(48)))
            guard let f = tank.fish(source: Self.source, entity: Self.entity) else { return }
            f.sub = t.artist
            // clicking it brings the player forward (the track itself, on Spotify)
            f.link = t.player == "Spotify" ? (t.id.hasPrefix("spotify:") ? t.id : "spotify:") : "music://"
            f.moment = nil
            f.mood = ears.mood
            f.progress = { [weak self] in self?.progress }
            if changed {
                // its album art: on the card, and its colors in the water's light and the aurora
                f.art = nil
                AlbumArt.load(player: t.player) { [weak self] img in
                    self?.tank.fish(source: Self.source, entity: Self.entity)?.art = img
                }
                // a new song: a glow, a ring of light and a burst of notes
                f.glow = 1
                tank.ring(at: f.pos, color: f.color, size: f.size * 0.5, grow: 130, life: 0.8)
                tank.notes(from: f, n: wasPlaying ? 8 : 4)
                if wasPlaying {
                    // and, from the second song on, it leaps out of the water and the song's name shows at the top
                    if f.jumpPhase == 0 { f.jumpPhase = 1; f.jumpDir = f.vel.x >= 0 ? 1 : -1 }
                    tank.notice = ("♪ " + name, tank.time)
                }
            }
        } else if paused, current != nil, let f = tank.fish(source: Self.source, entity: Self.entity) {
            // paused: it loses its color and sinks; after a few minutes it leaves
            Self.playing = false
            ears.follow(nil)
            tank.upsert(source: Self.source, entity: Self.entity, state: .idle, label: nil)
            f.moment = nil
            f.mood = tr("⏸ pausado")
            leaveTimer?.invalidate()
            leaveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in self?.clear() }
        }
    }

    private func clear() {
        Self.playing = false
        AlbumArt.clear()
        clock = nil
        ears.follow(nil)
        leaveTimer?.invalidate()
        leaveTimer = nil
        guard current != nil else { return }
        current = nil
        tank.remove(source: Self.source, entity: Self.entity)
    }

    // MARK: the song's progress

    /// Seconds into the song and its length (nil: not known yet).
    var progress: (pos: Double, dur: Double, playing: Bool)? {
        guard let c = clock, c.dur > 0 else { return nil }
        let pos = c.running ? c.pos + (CACurrentMediaTime() - c.at) : c.pos
        return (min(c.dur, max(0, pos)), c.dur, c.running)
    }

    /// Asks the player where it is (once per change: play, pause, a new track, a jump), off the main thread.
    fileprivate func syncClock(_ player: String, running: Bool) {
        if var c = clock {    // meanwhile, the clock stops or goes on at once
            if !running, c.running { c.pos += CACurrentMediaTime() - c.at }
            c.at = CACurrentMediaTime(); c.running = running
            clock = c
        }
        let script = player == "Spotify"
            ? "tell application \"Spotify\" to return (((player position * 1000) as integer) as string) & tab & ((duration of current track) as string)"
            : "tell application \"Music\" to return (((player position * 1000) as integer) as string) & tab & ((((duration of current track) * 1000) as integer) as string)"
        DispatchQueue.global(qos: .utility).async {
            let asked = CACurrentMediaTime()
            let parts = Self.run(script).components(separatedBy: "\t").compactMap(Double.init)
            guard parts.count == 2 else { return }
            DispatchQueue.main.async {
                self.clock = (parts[0] / 1000, asked, parts[1] / 1000, running)
            }
        }
    }

    /// "playing\ttitle\tartist\tid", "paused" or "stopped".
    private static func ask(_ player: String) -> String {
        let id = player == "Spotify" ? "(id of current track)" : "\"\""
        let script = """
        tell application "\(player)"
          if player state is playing then
            return "playing" & tab & (name of current track) & tab & (artist of current track) & tab & \(id)
          else
            return (player state as string)
          end if
        end tell
        """
        return run(script)
    }

    /// Jump to a point in the song (clicking or dragging the card's bar), then read the clock again.
    static func seek(_ player: String, to seconds: Double) {
        guard ["Spotify", "Music"].contains(player), seconds.isFinite, seconds >= 0 else { return }
        if var c = shared?.clock {                       // the bar moves at once; the player confirms after
            c.pos = seconds; c.at = CACurrentMediaTime(); shared?.clock = c
        }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = run("tell application \"\(player)\" to set player position to \(String(format: "%.2f", seconds))")
            DispatchQueue.main.async { shared?.syncClock(player, running: playing) }
        }
    }

    /// The player's buttons on the music fish's card: "playpause", "next track", "previous track".
    static func control(_ player: String, _ command: String) {
        guard ["playpause", "next track", "previous track"].contains(command), ["Spotify", "Music"].contains(player) else { return }
        DispatchQueue.global(qos: .userInitiated).async { _ = run("tell application \"\(player)\" to \(command)") }
    }

    private static func run(_ script: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
