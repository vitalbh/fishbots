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

    static let source = "music"
    private static let entity = "now-playing"
    private static let players = [("Spotify", "com.spotify.client"), ("Music", "com.apple.Music")]

    /// On by default; Preferências → Geral.
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "nowPlaying") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "nowPlaying"); if !newValue { shared?.clear() } else { shared?.askOnce() } }
    }
    private static weak var shared: NowPlaying?

    init(tank: Tank) {
        self.tank = tank
        Self.shared = self
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
            DispatchQueue.main.async { if let found { self.update(found, paused: false) } }
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
            let name = t.title + (t.artist.isEmpty ? "" : " — " + t.artist)
            tank.upsert(source: Self.source, entity: Self.entity, state: .busy, label: "♪ " + String(name.prefix(48)))
            guard let f = tank.fish(source: Self.source, entity: Self.entity) else { return }
            f.sub = t.artist
            // clicking it brings the player forward (the track itself, on Spotify)
            f.link = t.player == "Spotify" ? (t.id.hasPrefix("spotify:") ? t.id : "spotify:") : "music://"
            f.moment = nil
            if changed {
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
            tank.upsert(source: Self.source, entity: Self.entity, state: .idle, label: nil)
            f.moment = (tr("⏸ pausado"), tank.time + 1_000_000)
            leaveTimer?.invalidate()
            leaveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in self?.clear() }
        }
    }

    private func clear() {
        Self.playing = false
        leaveTimer?.invalidate()
        leaveTimer = nil
        guard current != nil else { return }
        current = nil
        tank.remove(source: Self.source, entity: Self.entity)
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
