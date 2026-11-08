import AVFoundation
import Synchronization

/// Synthesizer timbres.
enum Timbre: Int32 {
    case pluck = 0   // default fish (Claude Code)
    case bell = 1    // FM bell
    case pad = 2     // jellyfish, chords
    case bass = 3   // filter pump
    case glass = 4   // knock on the glass
    case bubble = 5   // bubble
    case soft = 6   // felt piano: the voice of the ambient music
    case rhodes = 7  // electric piano (FM)
    case flute = 8   // flute: slow attack, breath and vibrato; sustains for the duration
    case kalimba = 9 // music box / kalimba
    case tap = 10  // knuckle on the glass, tuned: the "knock knock" of finished
    case rumble = 11 // low-passed noise that rolls (thunder, quake): the frequency sets how dark, `dur` how long
}

struct NoteEvent {
    var start: Int64   // in samples, on the audio clock
    var freq: Float
    var vel: Float
    var dur: Float     // seconds (only the pad sustains)
    var timbre: Int32
    var pan: Float     // -1…1
}

/// Lock-free queue, one producer (main) and one consumer (audio thread).
final class EventRing {
    let capacity = 1024
    let buf: UnsafeMutablePointer<NoteEvent>
    let head = Atomic<Int>(0)
    let tail = Atomic<Int>(0)

    init() { buf = .allocate(capacity: capacity) }

    @discardableResult
    func push(_ e: NoteEvent) -> Bool {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        if h - t >= capacity { return false }
        buf[h % capacity] = e
        head.store(h + 1, ordering: .releasing)
        return true
    }

    func pop() -> NoteEvent? {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        if t == h { return nil }
        let e = buf[t % capacity]
        tail.store(t + 1, ordering: .releasing)
        return e
    }
}

struct Voice {
    var active = false
    var start: Int64 = 0
    var freq: Float = 440
    var vel: Float = 0
    var dur: Float = 0
    var timbre: Int32 = 0
    var gl: Float = 0.7
    var gr: Float = 0.7
    var ph1: Float = 0
    var ph2: Float = 0
    var lp: Float = 0
    var seed: UInt32 = 1
}

/// Custom polyphonic synthesizer inside an AVAudioSourceNode.
/// Nothing allocates or locks on the audio thread.
final class Synth {
    let engine = AVAudioEngine()
    let eq = AVAudioUnitEQ(numberOfBands: 1)
    let reverb = AVAudioUnitReverb()
    private(set) var source: AVAudioSourceNode!
    let ring = EventRing()
    let now = Atomic<Int>(0)
    let muted = Atomic<Bool>(false)
    private(set) var sampleRate: Double = 48000
    private(set) var running = false

    private let maxVoices = 48
    private let voices: UnsafeMutablePointer<Voice>
    private let clock: UnsafeMutablePointer<Int64>
    private let gain: UnsafeMutablePointer<Float>

    init() {
        voices = .allocate(capacity: maxVoices)
        voices.initialize(repeating: Voice(), count: maxVoices)
        clock = .allocate(capacity: 1)
        clock.initialize(to: 0)
        gain = .allocate(capacity: 1)
        gain.initialize(to: 0)
    }

    func start() {
        sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 48000 }
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        let src = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frameCount, abl -> OSStatus in
            self.render(Int(frameCount), abl)
            return noErr
        }
        source = src
        engine.attach(src)
        engine.attach(eq)
        engine.attach(reverb)
        let band = eq.bands[0]
        band.filterType = .lowPass
        band.frequency = 18000
        band.bypass = false
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 32
        engine.connect(src, to: eq, format: fmt)
        engine.connect(eq, to: reverb, format: fmt)
        engine.connect(reverb, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.9
        do {
            try engine.start()
            running = true
        } catch {
            FileHandle.standardError.write("fishbots: audio failed to start: \(error)\n".data(using: .utf8)!)
        }
    }

    /// Murky water muffles the sound (0…1).
    func setTurbidity(_ t: Float) {
        eq.bands[0].frequency = 18000 * powf(0.1, max(0, min(1, t)))
    }

    func play(at sample: Int64, midi: Double, vel: Float, dur: Float = 0, timbre: Timbre, pan: Float = 0) {
        // (the flute uses `dur` to sustain; so does the pad)
        let f = Float(440 * pow(2, (midi - 69) / 12))
        ring.push(NoteEvent(start: sample, freq: f, vel: vel, dur: dur, timbre: timbre.rawValue, pan: max(-1, min(1, pan))))
    }

    func playRaw(at sample: Int64, freq: Float, vel: Float, timbre: Timbre, pan: Float = 0) {
        ring.push(NoteEvent(start: sample, freq: freq, vel: vel, dur: 0, timbre: timbre.rawValue, pan: max(-1, min(1, pan))))
    }

    // MARK: - Audio thread

    private func render(_ n: Int, _ ablPtr: UnsafeMutablePointer<AudioBufferList>) {
        let abl = UnsafeMutableAudioBufferListPointer(ablPtr)
        guard abl.count >= 1, let lRaw = abl[0].mData else { return }
        let L = lRaw.assumingMemoryBound(to: Float.self)
        let R = (abl.count > 1 ? abl[1].mData : abl[0].mData)!.assumingMemoryBound(to: Float.self)
        let t0 = clock.pointee
        now.store(Int(t0), ordering: .relaxed)

        while let e = ring.pop() { allocate(e, t0) }

        for i in 0..<n { L[i] = 0; R[i] = 0 }
        let sr = Float(sampleRate)
        for v in 0..<maxVoices where voices[v].active {
            renderVoice(&voices[v], L, R, n, t0, sr)
        }

        // master gain with ramp (soft mute) and light saturation
        let target: Float = muted.load(ordering: .relaxed) ? 0 : 1
        var g = gain.pointee
        for i in 0..<n {
            g += (target - g) * 0.0005
            L[i] = tanhf(L[i] * 0.42) * g
            R[i] = tanhf(R[i] * 0.42) * g
        }
        gain.pointee = g
        clock.pointee = t0 + Int64(n)
    }

    private func allocate(_ e: NoteEvent, _ t0: Int64) {
        var slot = -1
        var oldest: Int64 = .max
        var oldestIdx = 0
        for v in 0..<maxVoices {
            if !voices[v].active { slot = v; break }
            if voices[v].start < oldest { oldest = voices[v].start; oldestIdx = v }
        }
        if slot < 0 { slot = oldestIdx }
        let a = (e.pan + 1) * 0.25 * Float.pi
        voices[slot] = Voice(active: true, start: e.start, freq: e.freq, vel: e.vel, dur: e.dur,
                             timbre: e.timbre, gl: cosf(a), gr: sinf(a), ph1: 0, ph2: 0, lp: 0,
                             seed: UInt32(truncatingIfNeeded: e.start) | 1)
    }

    private func renderVoice(_ v: inout Voice, _ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>,
                             _ n: Int, _ t0: Int64, _ sr: Float) {
        let twoPi = 2 * Float.pi
        let inc = v.freq / sr
        for i in 0..<n {
            let t = t0 + Int64(i)
            if t < v.start { continue }
            let ts = Float(t - v.start) / sr
            var s: Float = 0
            var maxLen: Float = 4

            switch v.timbre {
            case 0: // pluck
                maxLen = 3.5
                let env = ts < 0.004 ? ts / 0.004 : expf(-(ts - 0.004) / 0.55)
                v.ph1 += inc; if v.ph1 >= 1 { v.ph1 -= 1 }
                let p = twoPi * v.ph1
                s = (sinf(p) + 0.35 * sinf(2 * p) * expf(-ts * 6) + 0.15 * sinf(3 * p) * expf(-ts * 10)) * env
            case 1: // FM bell
                maxLen = 7
                let env = ts < 0.002 ? ts / 0.002 : expf(-ts / 1.5)
                v.ph1 += inc; if v.ph1 >= 1 { v.ph1 -= 1 }
                v.ph2 += inc * 3.5; if v.ph2 >= 1 { v.ph2 -= 1 }
                let idx = 2.2 * expf(-ts * 3)
                s = sinf(twoPi * v.ph1 + idx * sinf(twoPi * v.ph2)) * env * 0.8
            case 2: // pad
                maxLen = v.dur + 5
                let att: Float = 1.4
                var env = min(1, ts / att)
                if ts > v.dur { env *= expf(-(ts - v.dur) / 1.6) }
                v.ph1 += inc; if v.ph1 >= 1 { v.ph1 -= 1 }
                v.ph2 += inc * 1.0045; if v.ph2 >= 1 { v.ph2 -= 1 }
                let saw = (2 * v.ph1 - 1) + (2 * v.ph2 - 1)
                v.lp += 0.035 * (saw - v.lp)
                s = v.lp * env * 0.6
            case 3: // bass
                maxLen = 3
                let env = ts < 0.008 ? ts / 0.008 : expf(-(ts - 0.008) / 0.7)
                v.ph1 += inc; if v.ph1 >= 1 { v.ph1 -= 1 }
                let p = twoPi * v.ph1
                s = (sinf(p) + 0.25 * sinf(2 * p)) * env
            case 4: // glass
                maxLen = 0.45
                let a = sinf(twoPi * 2350 * ts) * expf(-ts / 0.09)
                let b = sinf(twoPi * 3640 * ts) * expf(-ts / 0.06) * 0.6
                let c = sinf(twoPi * 5210 * ts) * expf(-ts / 0.04) * 0.35
                v.seed = v.seed &* 1664525 &+ 1013904223
                let noise = (Float(v.seed >> 8) / Float(1 << 24) * 2 - 1) * (ts < 0.003 ? 1 - ts / 0.003 : 0)
                s = (a + b + c) * 0.5 + noise * 0.4
            case 6: // soft
                maxLen = 4.5
                let att: Float = 0.014
                let env = ts < att ? ts / att : expf(-(ts - att) / 1.7)
                v.ph1 += inc; if v.ph1 >= 1 { v.ph1 -= 1 }
                let p = twoPi * v.ph1
                let x = (sinf(p) + 0.16 * sinf(2 * p) * expf(-ts * 2) + 0.05 * sinf(3 * p) * expf(-ts * 4)) * env
                v.lp += 0.3 * (x - v.lp)
                s = v.lp
            case 7: // rhodes
                maxLen = 4.5
                let env = ts < 0.003 ? ts / 0.003 : expf(-ts / 1.3)
                v.ph1 += inc; if v.ph1 >= 1 { v.ph1 -= 1 }
                v.ph2 += inc * 14; if v.ph2 >= 1 { v.ph2 -= 1 }
                let p = twoPi * v.ph1
                let idx = 0.65 * expf(-ts * 3) + 0.1
                let tine = 0.07 * sinf(twoPi * v.ph2) * expf(-ts * 30)
                let x = (sinf(p + idx * sinf(p)) + tine) * env * 0.8
                v.lp += 0.35 * (x - v.lp)
                s = v.lp
            case 8: // flute
                let d = max(0.25, v.dur)
                maxLen = d + 0.6
                var env = min(1, ts / 0.09)
                if ts > d { env *= expf(-(ts - d) / 0.18) }
                let vib = ts > 0.25 ? 1 + 0.004 * sinf(twoPi * 5 * ts) : 1
                v.ph1 += inc * vib; if v.ph1 >= 1 { v.ph1 -= 1 }
                let p = twoPi * v.ph1
                v.seed = v.seed &* 1664525 &+ 1013904223
                let noise = Float(v.seed >> 8) / Float(1 << 24) * 2 - 1
                v.lp += 0.08 * (noise - v.lp)
                s = (sinf(p) + 0.12 * sinf(2 * p) + v.lp * 0.35) * env * 0.7
            case 9: // kalimba
                maxLen = 3
                let env = ts < 0.005 ? ts / 0.005 : expf(-ts / 0.85)
                v.ph1 += inc; if v.ph1 >= 1 { v.ph1 -= 1 }
                let p = twoPi * v.ph1
                let x = (sinf(p) + 0.09 * sinf(p * 5.4) * expf(-ts * 40) + 0.06 * sinf(2 * p)) * env
                v.lp += 0.3 * (x - v.lp)
                s = v.lp
            case 10: // tap on the glass, tuned and muffled
                maxLen = 0.3
                let a = sinf(twoPi * v.freq * ts) * expf(-ts / 0.045)
                let b = sinf(twoPi * v.freq * 2.76 * ts) * expf(-ts / 0.02) * 0.4
                v.seed = v.seed &* 1664525 &+ 1013904223
                let clique = (Float(v.seed >> 8) / Float(1 << 24) * 2 - 1) * (ts < 0.002 ? 1 - ts / 0.002 : 0) * 0.25
                let x = (a + b) * 0.7 + clique
                v.lp += 0.45 * (x - v.lp)
                s = v.lp
            case 11: // rumble: noise through two low-pass poles, rolling, fading after `dur`
                let d = max(0.3, v.dur)
                maxLen = d + 2
                var env = min(1, ts / 0.05)
                env *= ts < d ? 1 - 0.3 * ts / d : 0.7 * expf(-(ts - d) / 0.6)
                v.seed = v.seed &* 1664525 &+ 1013904223
                let noise = Float(v.seed >> 8) / Float(1 << 24) * 2 - 1
                let k = min(0.25, v.freq / sr * 6.3)
                v.lp += k * (noise - v.lp)
                v.ph2 += k * (v.lp - v.ph2)
                s = v.ph2 * env * (0.75 + 0.25 * sinf(twoPi * 2.7 * ts)) * 3.2
            default: // bubble
                maxLen = 0.3
                let env = (ts < 0.001 ? ts / 0.001 : 1) * expf(-ts / 0.05)
                v.ph1 += inc * (1 + ts * 18); if v.ph1 >= 1 { v.ph1 -= 1 }
                s = sinf(twoPi * v.ph1) * env * 0.7
            }

            if ts > maxLen { v.active = false; return }
            s *= v.vel
            L[i] += s * v.gl
            R[i] += s * v.gr
        }
    }
}
