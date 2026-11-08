import AVFoundation
import Accelerate
import CoreAudio

/// Lets the visualizers dance to Spotify or the Music app: listens to that player's own sound (a Core Audio process
/// tap, macOS 14.2+, only that app, nothing else from the Mac) and turns it into what the ambient music gives them —
/// notes at each onset (pitch from the strongest partial), chords from the chroma, events on big drops, energy from the
/// loudness. The notes come from the now-playing betta, so it's the fish that "sings" the song.
/// Opt-in (Preferences → General): the first time it listens, macOS asks for "System Audio Recording".
/// Only on while a player is playing; nothing is recorded or kept, the sound is analyzed and dropped.
final class SongEars {
    /// Off by default: turning it on is what makes macOS ask for the permission.
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "listenToMusic") }
        set { UserDefaults.standard.set(newValue, forKey: "listenToMusic"); onToggle?(newValue) }
    }
    static var onToggle: ((Bool) -> Void)?

    enum Status: Equatable { case idle, listening, silent, failed(String) }
    /// What Preferences shows under the toggle (silent: the permission was probably denied).
    private(set) static var status: Status = .idle

    weak var visual: Visual?
    /// Seconds left in the song (nil: unknown), for the calm at the end.
    var remaining: () -> Double? = { nil }
    unowned let tank: Tank
    private let source: String, entity: String

    private var player: String?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "fishbots.song-ears", qos: .userInitiated)
    private var analyzer: Analyzer?
    private var retry: DispatchWorkItem?

    init(tank: Tank, source: String, entity: String) {
        self.tank = tank
        self.source = source
        self.entity = entity
    }

    /// The player that's playing now (nil: nothing, stop listening).
    func follow(_ player: String?) {
        guard Self.enabled, let player else { stop(); return }
        if player == self.player, procID != nil { return }
        stop()
        self.player = player
        start(attempt: 0)
    }

    func stop() {
        retry?.cancel()
        retry = nil
        player = nil
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        queue.sync { analyzer = nil }
        if Self.status == .listening { Self.status = .idle }
        moodLevel = 0
        mood = tr("🎧 curtindo")
        if let f = tank.fish(source: source, entity: entity), f.state == .busy { f.mood = mood }
    }

    // MARK: the tap

    private static let bundles = ["Spotify": "com.spotify.client", "Music": "com.apple.Music"]

    private func start(attempt: Int) {
        guard let player, let bundle = Self.bundles[player] else { return }
        let procs = Self.audioProcesses(bundlePrefix: bundle)
        // the player only shows up among audio processes once it's making sound: try again for a few seconds
        guard !procs.isEmpty else {
            if attempt < 8 {
                let w = DispatchWorkItem { [weak self] in self?.start(attempt: attempt + 1) }
                retry = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: w)
            }
            return
        }
        do { try open(procs) } catch {
            stop()
            Self.status = .failed(error.localizedDescription)
        }
    }

    private struct Failure: LocalizedError {
        let what: String, code: OSStatus
        var errorDescription: String? { "\(what) (\(code))" }
    }

    private func open(_ procs: [AudioObjectID]) throws {
        func check(_ s: OSStatus, _ what: String) throws { if s != noErr { throw Failure(what: what, code: s) } }

        let desc = CATapDescription(stereoMixdownOfProcesses: procs)
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(desc, &tapID), "tap")

        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd), "format")
        guard let format = AVAudioFormat(streamDescription: &asbd) else { throw Failure(what: "format", code: -1) }

        let agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Fishbots ears",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        try check(AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggregateID), "device")

        let an = Analyzer(sampleRate: Float(format.sampleRate)) { [weak self] out in
            DispatchQueue.main.async { self?.deliver(out) }
        }
        queue.sync { analyzer = an }
        try check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            guard let self, let an = self.analyzer,
                  let buf = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil),
                  let ch = buf.floatChannelData else { return }
            an.feed(ch, channels: Int(format.channelCount), frames: Int(buf.frameLength),
                    interleaved: format.isInterleaved)
        }, "io")
        try check(AudioDeviceStart(aggregateID, procID), "start")
        Self.status = .listening
    }

    /// Audio process objects whose app matches the player (its helpers included).
    private static func audioProcesses(bundlePrefix: String) -> [AudioObjectID] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            var s = UInt32(MemoryLayout<CFString?>.size)
            var name: Unmanaged<CFString>?
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &name) == noErr, let n = name?.takeRetainedValue() else { return false }
            return (n as String).hasPrefix(bundlePrefix)
        }
    }

    // MARK: the fish's mood

    /// How the music fish says it's doing: by the song's energy when listening, otherwise just enjoying it.
    private(set) var mood = tr("🎧 curtindo")
    private var moodLevel = 0

    private func feel(_ e: Float) {
        // with a margin, so it doesn't flicker at the edges
        let up: [Float] = [0.45, 0.75], down: [Float] = [0.35, 0.65]
        if moodLevel < 2, e > up[moodLevel] { moodLevel += 1 } else if moodLevel > 0, e < down[moodLevel - 1] { moodLevel -= 1 }
        let m = fade < 1 ? tr("🌅 acabando…") : [tr("🎧 curtindo"), tr("🎶 na vibe"), tr("💃 dançando")][moodLevel]
        guard m != mood else { return }
        mood = m
        if let f = tank.fish(source: source, entity: entity), f.state == .busy { f.mood = m }
    }

    // MARK: to the visualizers

    /// FISHBOTS_EARSLOG=1: a line per second with what was heard (to tune the thresholds).
    private static let log = ProcessInfo.processInfo.environment["FISHBOTS_EARSLOG"] != nil
    private var tally = (notes: 0, chords: 0, drops: 0, energy: Float(0), since: Date())

    /// 1 for most of the song, down to 0 in its last seconds: the lights calm down as it ends.
    private var fade: Float {
        guard let r = remaining() else { return 1 }
        return Float(max(0, min(1, (r - 1) / 9)))
    }

    private func deliver(_ out: Analyzer.Out) {
        if Self.log {
            switch out {
            case .note: tally.notes += 1
            case .chord: tally.chords += 1
            case .drop: tally.drops += 1
            case let .energy(e): tally.energy = e
            case .silent, .heard: FileHandle.standardError.write("ears: \(out)\n".data(using: .utf8)!)
            }
            if Date().timeIntervalSince(tally.since) >= 1 {
                FileHandle.standardError.write(String(format: "ears: %d notes/s, %d chords, %d drops, energy %.2f\n",
                                                      tally.notes, tally.chords, tally.drops, tally.energy).data(using: .utf8)!)
                tally = (0, 0, 0, tally.energy, Date())
            }
        }
        guard player != nil, let visual else { return }
        switch out {
        case .silent:
            Self.status = .silent
        case .heard:
            if Self.status == .silent { Self.status = .listening }
        case let .note(midi, strength):
            let fade = self.fade
            guard fade >= 1 || Float.random(in: 0...1) < fade else { return }
            let strength = strength * max(0.4, fade)
            let f = tank.fish(source: source, entity: entity)
            visual.note(pos: f?.pos, midi: midi, vel: strength / 3, color: f?.color ?? [0.6, 0.9, 1], projectKey: f?.id ?? "music")
        case let .chord(pcs):
            visual.chord(pcs)
        case .drop:
            if fade >= 1, let f = tank.fish(source: source, entity: entity) { visual.event(at: f.pos) }
        case let .energy(e):
            visual.energy = e * fade
            feel(e)
        }
    }
}

// MARK: - the analysis

/// Runs on the tap's queue: a mono mix, a 2048-point FFT every 1024 samples, and from it onsets (spectral flux with an
/// adaptive threshold), the pitch of the strongest partial, a smoothed chroma and the loudness.
private final class Analyzer {
    enum Out { case note(Int, Float), chord([Int]), drop, energy(Float), silent, heard }

    private let sr: Float
    private let emit: (Out) -> Void
    private let n = 2048, hop = 1024
    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private var ring: [Float] = []
    private var prevLog: [Float]
    private var fluxHistory: [Float] = []
    private var bassHistory: [Float] = []
    private var chroma = [Float](repeating: 0, count: 12)
    private var peakFlux: Float = 1e-3
    private var frames = 0, lastOnset = -100, lastChord = 0, lastDrop = -1000, quietFrames = 0
    private var loud: Float = 0, peakRms: Float = 0
    private var real: [Float], imag: [Float]

    init(sampleRate: Float, emit: @escaping (Out) -> Void) {
        sr = sampleRate
        self.emit = emit
        fft = vDSP.FFT(log2n: 11, radix: .radix2, ofType: DSPSplitComplex.self)!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: n, isHalfWindow: false)
        prevLog = [Float](repeating: 0, count: n / 2)
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        ring.reserveCapacity(n * 2)
    }

    func feed(_ ch: UnsafePointer<UnsafeMutablePointer<Float>>, channels: Int, frames count: Int, interleaved: Bool) {
        guard count > 0 else { return }
        if interleaved {
            let p = ch[0]
            for i in 0..<count {
                var s: Float = 0
                for c in 0..<channels { s += p[i * channels + c] }
                ring.append(s / Float(channels))
            }
        } else {
            for i in 0..<count {
                var s: Float = 0
                for c in 0..<channels { s += ch[c][i] }
                ring.append(s / Float(channels))
            }
        }
        while ring.count >= n {
            analyze(Array(ring[0..<n]))
            ring.removeFirst(hop)
        }
    }

    private func bin(_ hz: Float) -> Int { max(1, min(n / 2 - 1, Int(hz * Float(n) / sr))) }

    private func analyze(_ x: [Float]) {
        frames += 1
        let fps = sr / Float(hop)                 // ~47 analyses per second at 48 kHz

        // loudness; long stretches of exact zeros mean the permission was denied (macOS hands over silence)
        let rms = vDSP.rootMeanSquare(x)
        if rms == 0 { quietFrames += 1 } else { if quietFrames >= Int(fps * 8) { emit(.heard) }; quietFrames = 0 }
        if quietFrames == Int(fps * 8) { emit(.silent) }
        peakRms = max(rms, peakRms * 0.9995)
        loud += (min(1, rms / max(peakRms, 1e-3)) - loud) * 0.05
        if frames % 12 == 0 { emit(.energy(loud)) }
        guard rms > 1e-4 else { return }

        // spectrum
        let w = vDSP.multiply(x, window)
        var mag = [Float](repeating: 0, count: n / 2)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                w.withUnsafeBytes { wb in
                    vDSP_ctoz(wb.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(n / 2))
                }
                fft.forward(input: split, output: &split)
                mag.withUnsafeMutableBufferPointer { mp in vDSP_zvabs(&split, 1, mp.baseAddress!, 1, vDSP_Length(n / 2)) }
            }
        }
        let logMag = mag.map { log1pf($0) }

        // onset: how much the spectrum grew since the last frame, against the recent average
        var flux: Float = 0
        for k in 1..<(n / 2) { flux += max(0, logMag[k] - prevLog[k]) }
        prevLog = logMag
        let bass = mag[bin(30)...bin(150)].reduce(0, +)
        fluxHistory.append(flux); if fluxHistory.count > Int(fps / 2) { fluxHistory.removeFirst() }
        bassHistory.append(bass); if bassHistory.count > Int(fps * 2) { bassHistory.removeFirst() }
        let mean = fluxHistory.reduce(0, +) / Float(fluxHistory.count)
        peakFlux = max(flux, peakFlux * 0.999)

        // chroma: every bin from 80 Hz to 2 kHz adds to its pitch class
        var frame = [Float](repeating: 0, count: 12)
        var best = (k: 0, m: Float(0))
        for k in bin(80)...bin(2000) {
            let hz = Float(k) * sr / Float(n)
            let midi = 69 + 12 * log2f(hz / 440)
            let pc = (Int(midi.rounded()) % 12 + 12) % 12
            frame[pc] += mag[k]
            if hz >= 150, hz <= 1200, mag[k] > best.m { best = (k, mag[k]) }
        }
        for i in 0..<12 { chroma[i] = chroma[i] * 0.97 + frame[i] * 0.03 }

        let gap = Int(fps * 0.12)
        if flux > mean * 1.25 + peakFlux * 0.04, frames - lastOnset >= gap, best.k > 0 {
            lastOnset = frames
            let hz = Float(best.k) * sr / Float(n)
            let midi = Int((69 + 12 * log2f(hz / 440)).rounded())
            let strength = max(0.3, min(1, flux / peakFlux))
            emit(.note(midi, strength))

            // a drop: the bass far above its last two seconds, not too often
            let bassMean = bassHistory.reduce(0, +) / Float(bassHistory.count)
            if bass > bassMean * 2.6, strength > 0.75, frames - lastDrop > Int(fps * 8) {
                lastDrop = frames
                emit(.drop)
            }
        }

        // a chord every ~2 s: the three strongest pitch classes, the strongest first
        if frames - lastChord > Int(fps * 2) {
            lastChord = frames
            let pcs = chroma.indices.sorted { chroma[$0] > chroma[$1] }.prefix(3)
            if (chroma.max() ?? 0) > 0 { emit(.chord(Array(pcs))) }
        }
    }
}
