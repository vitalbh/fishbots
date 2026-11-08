import Foundation
import QuartzCore

/// Sequencer: runs on the main thread and schedules notes ahead of time on the audio clock
/// (same scheme as the garden: look a little ahead and mark the exact sample).
///
/// Two layers:
/// - **signals** (always): each fish plays its motif only when something changes (arrived, finished, waiting, error);
/// - **ambient music** (optional): a piece generated with the ideas of the garden's generator (Generator.swift),
///   where the sessions take turns singing phrases built from their motif.
final class Music {
    let synth: Synth
    unowned let tank: Tank
    /// Visualizers: receive each note (position and color of whoever played), chord, piece and energy.
    var visual: Visual?

    var bpm: Double = 84
    private var step = 0
    private var nextT: Double = -1   // in samples

    // key of the signals: D pentatonic; with ambient music it follows the piece's key
    private var tonic = 62
    private let scale = [0, 2, 4, 7, 9]
    // chord for the event arpeggio when there's no ambient music
    private let fixedChord = [62, 66, 69, 74]

    // ambient music
    private(set) var piece: Piece?
    private var energy: Double = 0
    private var singer = 0
    private var arpIdx = 0
    private struct PendingNote {
        let midi: Int
        let vel: Float
        let timbre: Timbre
        let dur: Float
        let delay: Double        // in steps (swing and humanization)
        weak var fish: Fish?
        let pan: Float
        var lead = false           // melody note (visualizers show it even without a singer)
    }
    private var pending: [Int: [PendingNote]] = [:]

    var pieceName: String? { piece?.name }
    private let start = CACurrentMediaTime()
    private var lastArrival = -1000

    /// Your music (Spotify, Music) played since the ambient music was last turned on: it stays quiet until asked.
    var yielded = false
    private var lastUserMusic = false
    /// Your music paused while the ambient music was on and yielding: the app asks whether to play it.
    var onUserMusicPaused: (() -> Void)?
    var onUserMusicPlays: (() -> Void)?

    init(synth: Synth, tank: Tank) {
        self.synth = synth
        self.tank = tank
    }

    private var sr: Double { synth.sampleRate }
    private var samplesPerStep: Double { sr * 60 / bpm / 4 }

    func tick() {
        guard synth.running else { return }
        let now = Double(synth.now.load(ordering: .relaxed))
        if nextT < now { nextT = now + 0.05 * sr }
        let horizon = now + 0.15 * sr
        while nextT < horizon {
            play(step: step, at: nextT, now: now)
            step += 1
            nextT += samplesPerStep
        }
    }

    private func midi(_ degree: Int, octave: Int) -> Int {
        let n = scale.count
        let o = Int(floor(Double(degree) / Double(n)))
        let d = ((degree % n) + n) % n
        return tonic + scale[d] + 12 * (o + octave)
    }

    private func pan(_ f: Fish) -> Float { (f.pos.x / max(1, tank.size.x) * 2 - 1) * 0.6 }

    private func note(_ f: Fish, at t: Double, now: Double, midi m: Int, vel: Float, timbre: Timbre? = nil, dur: Float = 0, ring: Bool = true) {
        synth.play(at: Int64(t), midi: Double(m), vel: vel, dur: dur, timbre: timbre ?? f.timbre, pan: pan(f))
        let delay = (t - now) / sr
        tank.after(delay) { [weak f, weak tank, weak visual] in
            guard let f, let tank else { return }
            visual?.note(pos: f.pos, midi: m, vel: vel, color: f.color, projectKey: f.id)
            f.glow = max(f.glow, min(1, vel * 1.6))
            if ring { tank.ring(at: f.pos, color: f.color, size: f.size * 0.4, grow: 60, life: 0.8) }
        }
    }

    /// Plays the whole motif starting at `t`.
    private func motif(_ f: Fish, at t: Double, now: Double, vel: Float, octave o: Int, lastShift: Int = 0,
                       only: Int? = nil, compress: Bool = false, timbre: Timbre? = nil) {
        let notes = Motifs.pool[f.motif]
        let count = only.map { min($0, notes.count) } ?? notes.count
        for (i, n) in notes.prefix(count).enumerated() {
            let st = compress ? Double(i) : Double(n.step)
            var m = midi(n.degree, octave: o)
            if i == notes.count - 1 { m += lastShift }
            note(f, at: t + st * samplesPerStep, now: now, midi: m, vel: vel, timbre: timbre)
        }
    }

    /// The whale song: long, low notes on the flute, very quiet, with a pad underneath.
    func whaleSong() {
        guard synth.running else { return }
        let t0 = Double(synth.now.load(ordering: .relaxed)) + 0.1 * sr
        let notes: [(Double, Double, Float)] = [(0, 43, 2.6), (3.0, 47, 2.0), (5.4, 40, 3.2), (9.4, 45, 2.4)]
        for (when, m, dur) in notes {
            synth.play(at: Int64(t0 + when * sr), midi: m, vel: 0.13, dur: dur, timbre: .flute, pan: -0.3)
            synth.play(at: Int64(t0 + when * sr), midi: m - 12, vel: 0.05, dur: dur, timbre: .pad, pan: 0.3)
        }
    }

    // MARK: - the scene's sounds (presences and effects, docs/scene.md)

    /// Plays a scene voice now. The cue shapes it over the voice's root, in the current key: a hello (born), a
    /// question going up a fifth (waiting), a tritone (alert), a step down (error), a major arpeggio (done).
    func sceneSound(_ voice: String, cue: SceneCue, x: Float) {
        guard synth.running, voice != "none" else { return }
        let pan = (x * 2 - 1) * 0.6
        let t0 = Double(synth.now.load(ordering: .relaxed)) + 0.05 * sr
        let steps: [Int]
        switch cue {
        case .born, .effect: steps = [0]
        case .waiting: steps = [0, 7]
        case .alert: steps = [0, 6]
        case .error: steps = [0, -1]
        case .done: steps = [0, 4, 7]
        }
        let soft: Float = cue == .born ? 0.55 : 1
        func at(_ sec: Double) -> Int64 { Int64(t0 + sec * sr) }
        func line(_ timbre: Timbre, _ base: Int, vel: Float, gap: Double = 0.17, dur: Float = 0) {
            for (i, s) in steps.enumerated() {
                synth.play(at: at(Double(i) * gap), midi: Double(base + s), vel: vel * soft, dur: dur, timbre: timbre, pan: pan)
            }
        }
        let root = tonic
        switch voice {
        case "arpeggio": tank.pendingArp += 1
        case "whale": whaleSong()
        case "bass":
            line(.bass, root - 24, vel: 0.4, gap: 0.3)
            synth.play(at: at(0), midi: Double(root - 12), vel: 0.06 * soft, dur: 1.2, timbre: .pad, pan: pan)
        case "sonar":
            for (i, s) in steps.enumerated() {
                let m = Double(root + 22 + s), t = Double(i) * 0.5
                synth.play(at: at(t), midi: m, vel: 0.17 * soft, timbre: .bell, pan: pan)
                synth.play(at: at(t + 0.42), midi: m, vel: 0.07 * soft, timbre: .bell, pan: -pan)
                synth.play(at: at(t + 0.84), midi: m, vel: 0.03 * soft, timbre: .bell, pan: pan)
            }
        case "glass":
            for i in steps.indices {
                synth.playRaw(at: at(Double(i) * 0.14), freq: 1, vel: 0.3 * soft, timbre: .glass, pan: pan)
                synth.playRaw(at: at(Double(i) * 0.14 + 0.07), freq: 1, vel: 0.15 * soft, timbre: .glass, pan: pan)
            }
        case "tick":
            for (i, s) in steps.enumerated() {
                synth.play(at: at(Double(i) * 0.4), midi: Double(root + 26 + s), vel: 0.4 * soft, timbre: .tap, pan: pan)
                synth.play(at: at(Double(i) * 0.4 + 0.2), midi: Double(root + 19 + s), vel: 0.35 * soft, timbre: .tap, pan: pan)
            }
        case "clang":
            line(.bell, root - 10, vel: 0.22, gap: 0.35)
            synth.play(at: at(0), midi: Double(root - 29), vel: 0.3 * soft, timbre: .bass, pan: pan)
        case "bell": line(.bell, root + 12, vel: 0.2)
        case "chime": line(.bell, root + 24, vel: 0.12, gap: 0.1)
        case "kalimba": line(.kalimba, root + 12, vel: 0.35)
        case "flute": line(.flute, root, vel: 0.22, gap: 0.45, dur: 0.4)
        case "pad": line(.pad, root, vel: 0.12, gap: 0.6, dur: 1.2)
        case "soft": line(.soft, root + 12, vel: 0.35)
        case "pluck": line(.pluck, root + 12, vel: 0.3)
        case "tap": line(.tap, root + 19, vel: 0.4, gap: 0.12)
        case "bubble":
            for i in 0..<(steps.count + 2) {
                synth.play(at: at(Double(i) * 0.09), midi: Double(root + 24 + i * 3), vel: 0.3 * soft, timbre: .bubble, pan: pan)
            }
        case "thunder":
            synth.play(at: at(0), midi: 66, vel: 0.5, dur: 0.25, timbre: .rumble, pan: pan)        // the crack
            synth.play(at: at(0.15), midi: 43, vel: 0.9, dur: 1.8, timbre: .rumble, pan: -pan * 0.5) // the roll
        case "rumble":
            synth.play(at: at(0), midi: 38, vel: 0.85, dur: 2.2, timbre: .rumble, pan: 0)
            synth.play(at: at(0), midi: Double(root - 26), vel: 0.25, timbre: .bass, pan: 0)
        case "run":
            for (i, d) in [0, 2, 4, 7, 9, 12, 14, 16].enumerated() {
                synth.play(at: at(Double(i) * 0.06), midi: Double(root + 12 + d), vel: 0.22, timbre: .kalimba, pan: pan - 0.3 + Float(i) * 0.08)
            }
        case "glissando":
            for (i, d) in [31, 28, 26, 24, 21, 19].enumerated() {
                synth.play(at: at(Double(i) * 0.05), midi: Double(root + d), vel: 0.14 - Float(i) * 0.015, timbre: .bell, pan: pan)
            }
        default: break
        }
    }

    /// Plays a motif now (to hear it before choosing).
    func preview(motif m: Int, timbre: Timbre) {
        guard synth.running, m >= 0, m < Motifs.pool.count else { return }
        let t0 = Double(synth.now.load(ordering: .relaxed)) + 0.04 * sr
        for n in Motifs.pool[m] {
            synth.play(at: Int64(t0 + Double(n.step) * samplesPerStep), midi: Double(midi(n.degree, octave: 0)), vel: 0.5, timbre: timbre)
        }
    }

    private func play(step: Int, at t: Double, now: Double) {
        let s = step % 16
        let bar = step / 16
        let active = tank.fish.filter { !$0.decor && !$0.leaving }
        let focus = Attention.focus
        // the ambient music steps aside while Spotify or the Music app is playing, and doesn't come back by itself when
        // it pauses (the pause may be for silence: a meeting): the aquarium asks, and ⌘A brings it back
        let wanted = UserDefaults.standard.bool(forKey: "ambientMusic")
        if NowPlaying.playing != lastUserMusic {
            lastUserMusic = NowPlaying.playing
            if NowPlaying.playing { yielded = true; onUserMusicPlays?() }
            else if yielded && wanted { onUserMusicPaused?() }
        }
        let ambient = wanted && !focus && !NowPlaying.playing && !yielded

        if ambient {
            playAmbient(step: step, s: s, bar: bar, t: t, now: now, active: active)
        } else if piece != nil {
            // left ambient music: back to the signals' key and tempo
            piece = nil
            visual?.style = nil
            pending.removeAll()
            bpm = 84
            tonic = 62
        }

        // food / event: arpeggio of whatever chord is sounding
        if focus { tank.pendingArp = 0 }
        if tank.pendingArp > 0 && s % 4 == 0 {
            tank.pendingArp -= 1
            var tones = fixedChord
            if let p = piece { tones = Generator.voicing(p.chord(inBar: bar), center: 72) }
            tones.append(tones[0] + 12)
            for (i, m) in tones.enumerated() {
                synth.play(at: Int64(t + Double(i) * samplesPerStep * 0.5), midi: Double(m), vel: 0.24, timbre: .bell,
                           pan: Float(i) * 0.3 - 0.6)
            }
        }

        for f in active where !Motifs.muted(f.projectKey) {
            f.step = step
            // in focus mode, only those in a state that needs attention play
            if focus && Attention.level(f.source, f.state) == .ambient { f.intro = false; continue }
            playFish(f, s: s, t: t, now: now)
        }
    }

    private func playFish(_ f: Fish, s: Int, t: Double, now: Double) {
        // arrival: the whole motif, quick, rising
        if f.intro {
            if s == 0 {
                f.intro = false
                // arrival sound only for sessions, after the first 20 s, one at a time (every 2 bars),
                // quiet and on the felt piano. When the app opens and for plugins, everyone enters silently.
                let session = f.isAgent
                if session && tank.time - start > 20 && f.step - lastArrival >= 32 {
                    lastArrival = f.step
                    motif(f, at: t, now: now, vel: 0.28, octave: 0, compress: true, timbre: .soft)
                }
                if f.state == .born { tank.after(2) { [weak f] in if f?.state == .born { f?.state = .idle } } }
            }
            return
        }
        tool(f, s: s, step: f.step, t: t, now: now)
        signals(f, s: s, t: t, now: now)
    }

    // MARK: - ambient music (the garden's generator)

    private func playAmbient(step: Int, s: Int, bar: Int, t: Double, now: Double, active: [Fish]) {
        // energy: how many sessions are working, smoothed (rises and falls slowly)
        if s == 0 {
            let goal = min(1, Double(active.filter { $0.state == .busy }.count) / 3)
            energy += (goal - energy) * 0.08
            visual?.energy = Float(energy)
        }

        // new piece: at the start and when the current one ends (always at a phrase start)
        if s == 0 && bar % 4 == 0 && (piece == nil || bar >= piece!.start + piece!.bars) {
            let new = Piece.new(energy: energy, previous: piece, bar: bar)
            piece = new
            visual?.newPiece(style: new.style.id)
            bpm = new.bpm
            tonic = 60 + (new.key <= 6 ? new.key : new.key - 12)
        }
        guard let p = piece else { return }
        let rel = bar - p.start
        let chord = p.chord(inBar: bar)

        // jellyfish: the chord, long and quiet, and the bass on the root
        if s == 0 && rel % p.style.barsPerChord == 0 {
            let dur = Float(samplesPerStep * 16 * Double(p.style.barsPerChord) / sr)
            for (i, m) in Generator.voicing(chord, center: 57).enumerated() {
                synth.play(at: Int64(t), midi: Double(m), vel: 0.055, dur: dur, timbre: .pad, pan: Float(i) * 0.4 - 0.6)
            }
            var root = 36 + ((chord[0] - 36) % 12 + 12) % 12
            if root < 40 { root += 12 }
            synth.play(at: Int64(t), midi: Double(root), vel: 0.14, timbre: .soft)
            tank.after((t - now) / sr) { [weak tank, weak visual] in
                tank?.jellyGlow = 0.9
                visual?.chord(chord)
            }
        }

        // a phrase every 4 bars
        if s == 0 && rel % 4 == 0 { schedulePhrase(p, bar: bar, step: step, active: active) }

        follow(p, s: s, bar: bar, step: step, chord: chord)

        // notes scheduled for this step
        if let list = pending.removeValue(forKey: step) {
            for n in list {
                let tt = t + n.delay * samplesPerStep
                if let f = n.fish {
                    note(f, at: tt, now: now, midi: n.midi, vel: n.vel, timbre: n.timbre, dur: n.dur, ring: false)
                } else {
                    synth.play(at: Int64(tt), midi: Double(n.midi), vel: n.vel, dur: n.dur, timbre: n.timbre, pan: n.pan)
                    if n.lead {
                        let m = n.midi, v = n.vel
                        tank.after((tt - now) / sr) { [weak visual] in
                            visual?.note(pos: nil, midi: m, vel: v, color: [0.6, 0.9, 1], projectKey: "music")
                        }
                    }
                }
            }
        }
        // cleanup (steps left behind)
        if s == 0 { pending = pending.filter { $0.key >= step } }
    }

    private func mark(_ step: Int, _ n: PendingNote) { pending[step, default: []].append(n) }

    /// A 4-bar phrase (phrase) sung by a session, built from its motif.
    private func schedulePhrase(_ p: Piece, bar: Int, step: Int, active: [Fish]) {
        let voices = active.filter { !Motifs.muted($0.projectKey) && !$0.intro }
        let rest = p.style.rest + (voices.isEmpty ? 0.2 : 0)
        if Double.random(in: 0...1) < rest { return }
        var currentSinger: Fish?
        if !voices.isEmpty {
            singer = (singer + 1) % voices.count
            currentSinger = voices[singer]
        }
        let seed = currentSinger.flatMap { Generator.seed(do: Motifs.pool[$0.motif]) }
        let weights: [Double] = [3, 1, 2, 1, 2.5, 1, 2, 1]
        let phrase = Generator.phrase(bars: 4, barLen: 8, perBar: Int.random(in: p.style.notesPerBar),
                                  weights: weights, seed: seed)
        let scaleKey = p.style.scale.map { ($0 + p.key) % 12 }
        let register = currentSinger?.state == .busy ? 72 : 67
        let secPerEighth = Float(2 * samplesPerStep / sr)
        for (k, (e, d)) in phrase.enumerated() {
            let b = bar + e / 8
            let ac = p.chord(inBar: b)
            let m = Generator.note(degree: d, chord: ac, scale: Generator.chordScale(scaleKey, chord: ac), register: register)
            let next = k + 1 < phrase.count ? phrase[k + 1].0 : e + 4
            let dur = Float(min(4, max(1, next - e))) * secPerEighth * 0.9
            let swing = e % 2 == 1 ? p.swing * 1.33 : 0
            let vel = Float.random(in: 0.12...0.17) * (e % 8 == 0 ? 1.12 : 1)
            mark(step + e * 2, PendingNote(midi: m, vel: vel, timbre: p.lead, dur: dur,
                                          delay: swing + Double.random(in: -0.06...0.06), fish: currentSinger, pan: 0, lead: true))
        }
    }

    /// Style accompaniment: slow arpeggio (ambient, lullaby), lo-fi chords, the bossa beat.
    private func follow(_ p: Piece, s: Int, bar: Int, step: Int, chord: [Int]) {
        let tb = p.accompTimbre
        switch p.style.accomp {
        case .arpeggio:
            // one chord note per beat, sometimes, rising and falling slowly
            if s % 4 == 0 && Double.random(in: 0...1) < (p.style.id == "lullaby" ? 0.45 : 0.3) {
                let v = Generator.voicing(chord, center: 66)
                let upDown = v + v.dropFirst().dropLast().reversed()
                arpIdx += 1
                mark(step, PendingNote(midi: upDown[arpIdx % upDown.count], vel: Float.random(in: 0.05...0.08), timbre: tb, dur: 1,
                                      delay: Double.random(in: 0...0.08), fish: nil, pan: Float.random(in: -0.5...0.5)))
            }
        case .lofi:
            // chord on 1 and on the "and" of 2, with swing and a light strum
            let strokes: [(Int, Double)] = [(0, 0.85), (6, 0.5)]
            for (st, chance) in strokes where s == st && Double.random(in: 0...1) < chance {
                let sw = st % 4 == 2 ? p.swing * 1.33 : 0
                for (i, m) in Generator.voicing(chord, center: 60).enumerated() {
                    mark(step, PendingNote(midi: m, vel: 0.05, timbre: tb, dur: 1, delay: sw + Double(i) * 0.05,
                                          fish: nil, pan: -0.25))
                }
            }
        case .bossa:
            // 3 + 3 + 2 in eighths, and the bass on 1 and 3 (root and fifth)
            if [0, 6, 12].contains(s) {
                for (i, m) in Generator.voicing(chord, center: 62).enumerated() {
                    mark(step, PendingNote(midi: m, vel: 0.045, timbre: tb, dur: 1, delay: Double(i) * 0.03, fish: nil, pan: 0.25))
                }
            }
            if s == 0 || s == 8 {
                var r = 36 + ((chord[0] - 36) % 12 + 12) % 12
                if r < 40 { r += 12 }
                mark(step, PendingNote(midi: s == 0 ? r : r + 7, vel: 0.11, timbre: .soft, dur: 1, delay: 0, fish: nil, pan: 0))
            }
        }
    }

    // MARK: - signals (always)

    /// Plays only on changes: finished (resolves), started waiting for you (asks and knocks on the glass,
    /// with a reminder every 2.5 min) and error. Working makes no sound: it shows in the fish's movement.
    /// A fish just asked you something and finished calling (motif and knocks): seconds from now until it's quiet.
    /// The app reads the question aloud then, so the voice doesn't drown the knocks (it ducks the music while speaking).
    var called: ((Fish, Double) -> Void)?

    private func signals(_ f: Fish, s: Int, t: Double, now: Double) {
        guard s == 0 else { return }
        let changed = f.changed
        f.changed = false
        switch f.state {
        case .done where f.resolve:
            resolve(f, at: t, now: now)
        case .waiting:
            guard changed || tank.time - f.reminder > 150 else { return }
            f.reminder = tank.time
            motif(f, at: t, now: now, vel: 0.42, octave: 0, only: 2)
            var end = t + 4 * samplesPerStep
            if Attention.level(f.source, .waiting) >= .attention {
                knock(f, at: t + 12 * samplesPerStep, now: now)
                knock(f, at: t + 14 * samplesPerStep, now: now)
                end = t + 15 * samplesPerStep
            }
            if changed { called?(f, (end - now) / sr + 0.35) }
        case .error, .alert:
            if changed && Attention.level(f.source, f.state) >= .attention {
                motif(f, at: t, now: now, vel: 0.42, octave: 0, lastShift: 1)
            }
        default:
            break
        }
    }

    private func knock(_ f: Fish, at t: Double, now: Double) {
        synth.playRaw(at: Int64(t), freq: 1, vel: 0.35, timbre: .glass, pan: pan(f))
        tank.after((t - now) / sr) { [weak f, weak tank] in
            guard let f, let tank else { return }
            let dir: Float = f.vel.x >= 0 ? 1 : -1
            tank.ring(at: f.pos + [dir * f.size * 0.9, 0], color: [0.9, 0.97, 1], size: 6, grow: 90, life: 0.6)
        }
    }

    /// Finished: a discreet knock-knock on the glass, tuned to the motif's first two notes (you can guess who it was).
    private func resolve(_ f: Fish, at t: Double, now: Double) {
        f.resolve = false
        let notes = Motifs.pool[f.motif]
        let pitches = [midi(notes[0].degree, octave: 1), midi(notes[min(1, notes.count - 1)].degree, octave: 1)]
        for (i, m) in pitches.enumerated() {
            let tt = t + Double(i) * 1.4 * samplesPerStep
            synth.play(at: Int64(tt), midi: Double(m), vel: 0.22, timbre: .tap, pan: pan(f))
            tank.after((tt - now) / sr) { [weak f, weak tank, weak visual] in
                guard let f, let tank else { return }
                visual?.note(pos: f.pos, midi: m, vel: 0.35, color: f.color, projectKey: f.id)
                let dir: Float = f.vel.x >= 0 ? 1 : -1
                f.glow = max(f.glow, 0.4)
                tank.ring(at: f.pos + [dir * f.size * 0.9, 0], color: [0.9, 0.97, 1], size: 4, grow: 45, life: 0.45)
            }
        }
    }

    private func tool(_ f: Fish, s: Int, step: Int, t: Double, now: Double) {
        // tools: off by default (an active agent uses dozens per minute and it becomes noise).
        // When on, plays at most one note every 2 bars per session.
        if !f.ticks.isEmpty && !UserDefaults.standard.bool(forKey: "toolNotes") { f.ticks.removeAll() }
        if s % 2 == 1, !f.ticks.isEmpty, step - f.lastTick >= 32 {
            let tb = f.ticks.removeLast()
            f.ticks.removeAll()
            f.lastTick = step
            let notes = Motifs.pool[f.motif]
            let n = notes[f.tickIdx % notes.count]
            f.tickIdx += 1
            note(f, at: t, now: now, midi: midi(n.degree, octave: 1), vel: tb == .bubble ? 0.22 : 0.13, timbre: tb, ring: false)
        }
    }
}
