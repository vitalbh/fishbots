import AVFoundation
import Foundation

/// The aquarium's sound on the phone: the Mac's own synth and music (Synth, Music, Generator), on the mirrored tank.
/// Each fish calls when it changes (finished, waiting, broke), and with the ambient music on, the sessions take turns
/// singing. Pack sounds come with the packs (`/packs/files?sounds=1`). It mixes with whatever else plays and keeps
/// quiet with the silent switch (the .ambient category); it stops when the app goes behind.
final class AquariumSound {
    private let mirror: TankMirror
    private let synth = Synth()
    private var music: Music?
    private var timer: Timer?

    /// The menu's switches (the ambient music's is the Mac's own key, which Music reads).
    static var on: Bool {
        get { UserDefaults.standard.object(forKey: "soundOn") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "soundOn") }
    }

    init(mirror: TankMirror) { self.mirror = mirror }

    func start() {
        guard timer == nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if music == nil {
            synth.start()
            let m = Music(synth: synth, tank: mirror.tank)
            m.visual = mirror.visual
            music = m
            // the music shows each note on the visualizers itself (the mirror did, while silent)
            mirror.tank.onState = nil
            mirror.tank.fauna.onWhale = { [weak m] in m?.whaleSong() }
        } else if !synth.engine.isRunning {
            try? synth.engine.start()
        }
        synth.muted.store(!Self.on, ordering: .relaxed)
        var n = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in
            guard let self, let music = self.music else { return }
            music.tick()
            n += 1
            if n % 50 == 0 { self.synth.setTurbidity(self.mirror.tank.turbidity) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        synth.engine.pause()
    }

    /// A knock on the glass (the Mac's own sound for it).
    func knock(x: Float) { music?.sceneSound("glass", cue: .effect, x: x) }

    func setOn(_ on: Bool) {
        Self.on = on
        synth.muted.store(!on, ordering: .relaxed)
    }
}
