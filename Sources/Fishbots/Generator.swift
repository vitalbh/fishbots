import Foundation

// The aquarium's ambient music: the ideas of the Jardim de Chuva generator (vitalbh.io/site/jardim, docs/gerador.md)
// brought over here, only the calm group. Rule + draw: each rule applies with some chance, choices are weighted
// and values come from ranges.

enum Accomp { case arpeggio, lofi, bossa }

struct Style {
    let id: String
    let name: String
    let bpm: ClosedRange<Double>
    let progs: [String]
    let scale: [Int]
    let barsPerChord: Int
    let lead: [Timbre]
    let accomp: Accomp
    let accompTimbre: [Timbre]
    let notesPerBar: ClosedRange<Int>
    let swing: ClosedRange<Double>
    let keys: [Int]
    let energy: Double        // 0 = very calm … 1 = more movement
    let rest: Double        // chance a phrase stays silent
}

enum Generator {
    /// Chords in C (the first is the root), like the garden's CHORDS.
    private(set) static var chords: [String: [Int]] = [
        "C": [0, 4, 7], "Cmaj7": [0, 4, 7, 11], "Dm7": [2, 5, 9, 0], "Em7": [4, 7, 11, 2],
        "F": [5, 9, 0], "Fmaj7": [5, 9, 0, 4], "Fm": [5, 8, 0], "G": [7, 11, 2], "G7": [7, 11, 2, 5],
        "Gsus4": [7, 0, 2], "Am": [9, 0, 4], "Am7": [9, 0, 4, 7], "Bb": [10, 2, 5], "A7": [9, 1, 4, 7],
    ]
    /// Progressions (the garden's PRESETS).
    private(set) static var presets: [String: [String]] = [
        "Pop": ["C", "G", "Am", "F"],
        "Melancholic": ["Am", "F", "C", "G"],
        "Dreamy": ["Cmaj7", "Fmaj7", "Cmaj7", "Fmaj7"],
        "Jazzy": ["Dm7", "G7", "Cmaj7", "Am7"],
        "Nostalgic": ["C", "Am", "F", "Fm"],
        "Open": ["C", "Gsus4", "Bb", "F"],
        "Bossa": ["Cmaj7", "A7", "Dm7", "G7"],
    ]
    static let major = [0, 2, 4, 5, 7, 9, 11]
    static let penta = [0, 2, 4, 7, 9]

    /// The registry of music styles (packs add more; see docs/extensions.md).
    private(set) static var styles: [Style] = [
        Style(id: "lullaby", name: "ninar", bpm: 52...62, progs: ["Dreamy", "Nostalgic", "Pop"], scale: penta,
               barsPerChord: 2, lead: [.kalimba, .soft], accomp: .arpeggio, accompTimbre: [.soft, .kalimba],
               notesPerBar: 2...3, swing: 0...0.1, keys: [0, 5, 7, 2], energy: 0, rest: 0.45),
        Style(id: "ambient", name: "ambient", bpm: 54...66, progs: ["Dreamy", "Open", "Nostalgic"], scale: major,
               barsPerChord: 2, lead: [.flute, .soft, .kalimba], accomp: .arpeggio, accompTimbre: [.soft, .kalimba],
               notesPerBar: 2...3, swing: 0...0, keys: [0, 2, 4, 5, 7, 9], energy: 0.15, rest: 0.4),
        Style(id: "lofi", name: "lo-fi", bpm: 68...80, progs: ["Jazzy", "Dreamy", "Melancholic", "Nostalgic"], scale: major,
               barsPerChord: 2, lead: [.rhodes, .flute, .soft], accomp: .lofi, accompTimbre: [.rhodes],
               notesPerBar: 3...4, swing: 0.35...0.55, keys: [0, 2, 5, 7, 9], energy: 0.55, rest: 0.25),
        Style(id: "bossa", name: "bossa", bpm: 76...88, progs: ["Bossa", "Jazzy", "Dreamy"], scale: major,
               barsPerChord: 1, lead: [.flute, .soft], accomp: .bossa, accompTimbre: [.rhodes, .soft],
               notesPerBar: 3...4, swing: 0.05...0.2, keys: [0, 2, 7, 5], energy: 0.85, rest: 0.25),
    ]

    /// Adds or replaces a style, with any chords and progressions it needs.
    static func register(_ s: Style, chords: [String: [Int]] = [:], progressions: [String: [String]] = [:]) {
        self.chords.merge(chords) { $1 }
        presets.merge(progressions) { $1 }
        if let i = styles.firstIndex(where: { $0.id == s.id }) { styles[i] = s } else { styles.append(s) }
    }

    /// The theme's style: chosen more often.
    static var preferredStyle: String?

    static func pick<T>(_ a: [T]) -> T { a[Int.random(in: 0..<a.count)] }

    // MARK: phrase

    /// A one-bar motif: positions (eighths, 0…barLen-1) and degrees.
    struct Motif {
        var hs: [Int]
        var ds: [Int]
    }

    /// Weighted random rhythm (strong beats weigh more) and a short path of degrees.
    static func motif(barLen: Int, perBar: Int, weights: [Double]) -> Motif {
        let k = max(2, min(perBar, barLen - 1))
        var on = Set<Int>()
        let total = weights.prefix(barLen).reduce(0, +)
        while on.count < k {
            var r = Double.random(in: 0..<total), i = 0
            while r - weights[i] > 0 && i < barLen - 1 { r -= weights[i]; i += 1 }
            on.insert(i)
        }
        let hs = on.sorted()
        var d = pick([0, 0, 1, 2, -1])
        let ds = hs.indices.map { j -> Int in
            if j == 0 { return d }
            d = max(-3, min(4, d + pick([-2, -1, -1, 1, 1, 2])))
            return d
        }
        return Motif(hs: hs, ds: ds)
    }

    /// The same idea with one detail changed: a note moves a step, or a degree changes.
    static func vary(_ m: Motif, barLen: Int) -> Motif {
        var hs = m.hs, ds = m.ds
        let j = Int.random(in: 0..<hs.count)
        if Bool.random() {
            let t = max(0, min(barLen - 1, hs[j] + pick([-1, 1])))
            if !hs.contains(t) { hs[j] = t }
        } else {
            ds[j] = max(-3, min(4, ds[j] + pick([-1, 1, 2])))
        }
        let ord = zip(hs, ds).sorted { $0.0 < $1.0 }
        return Motif(hs: ord.map(\.0), ds: ord.map(\.1))
    }

    /// A phrase of `bars` bars from motif A (the fish's, when there is one).
    /// Forms AA2 and AB (2 bars), AA2AB, ABAB2, ABAC, AABA (4). The question (middle) ends off the resting note
    /// and the answer (end) rests on degree 0, the chord note. Returns [(eighth, degree)].
    static func phrase(bars: Int, barLen: Int, perBar: Int, weights: [Double], seed: Motif?) -> [(Int, Int)] {
        let shape = bars >= 4 ? pick(["AA2AB", "ABAB2", "ABAC", "AABA"]) : pick(["AA2", "AB", "AB"])
        var mem: [String: Motif] = ["A": seed ?? motif(barLen: barLen, perBar: perBar, weights: weights)]
        var seq: [Motif] = []
        var letters: [String] = []
        var i = shape.startIndex
        while i < shape.endIndex {
            var l = String(shape[i]); i = shape.index(after: i)
            if i < shape.endIndex, shape[i] == "2" { l += "2"; i = shape.index(after: i) }
            letters.append(l)
        }
        for l in letters.prefix(bars) {
            if mem[l] == nil {
                if l.hasSuffix("2") { mem[l] = vary(mem[String(l.prefix(1))]!, barLen: barLen) }
                else if l == "C" { mem[l] = vary(motif(barLen: barLen, perBar: perBar, weights: weights), barLen: barLen) }
                else { mem[l] = motif(barLen: barLen, perBar: perBar, weights: weights) }
            }
            seq.append(mem[l]!)
        }
        while seq.count < bars { seq.append(seq[seq.count % 2]) }
        var out: [(Int, Int)] = []
        for (b, m) in seq.enumerated() {
            let last = b == bars - 1, middle = bars >= 2 && b == bars / 2 - 1
            for (j, h) in m.hs.enumerated() {
                var d = m.ds[j]
                if j == m.hs.count - 1 && last { d = 0 }                       // the answer rests
                else if j == m.hs.count - 1 && middle && d == 0 { d = pick([1, 2, -1]) } // the question hangs in the air
                out.append((b * barLen + h, d))
            }
        }
        return out
    }

    /// The fish's motif (sixteenths, pentatonic degrees) becomes an eighth-note motif with the same contour.
    static func seed(do fishMotif: [MotifNote]) -> Motif? {
        guard let first = fishMotif.first else { return nil }
        var seen = Set<Int>()
        var hs: [Int] = [], ds: [Int] = []
        for n in fishMotif {
            let h = min(7, n.step / 2)
            guard !seen.contains(h) else { continue }
            seen.insert(h)
            hs.append(h)
            ds.append(max(-3, min(4, n.degree - first.degree)))
        }
        return hs.count >= 2 ? Motif(hs: hs, ds: ds) : nil
    }

    // MARK: notes

    /// The bar's scale: the key's, with the chord notes replacing their neighbors (Fm swaps A for A♭, A7 brings C♯…).
    static func chordScale(_ scale: [Int], chord: [Int]) -> [Int] {
        scale.map { pc in
            if chord.contains(pc) { return pc }
            if let c = chord.first(where: { ($0 - pc + 12) % 12 == 1 || (pc - $0 + 12) % 12 == 1 }), !scale.contains(c) { return c }
            return pc
        }
    }

    /// Note for degree `d` from the chord's root, near the register.
    static func note(degree d: Int, chord: [Int], scale: [Int], register: Int) -> Int {
        let notes = (36...96).filter { scale.contains(($0 % 12 + 12) % 12) }
        let root = chord[0]
        let base = notes.filter { $0 % 12 == root }.min { abs($0 - register) < abs($1 - register) }
            ?? notes.min { abs($0 - register) < abs($1 - register) }!
        let i = notes.firstIndex(of: base)!
        return notes[max(0, min(notes.count - 1, i + d))]
    }

    /// Chord in close position near `center` (like the garden's chordNotes: always in the same region).
    static func voicing(_ chord: [Int], center: Int) -> [Int] {
        chord.map { pc in
            let base = center - ((center - pc) % 12 + 12) % 12
            return abs(base - center) <= 6 ? base : base + 12
        }.sorted()
    }
}

/// A piece playing: style, key, progression and tempo. Changes every ~2–3 min, guided by the energy.
struct Piece {
    let style: Style
    let key: Int
    let prog: [[Int]]        // chords already in the key (pitch classes)
    let progName: String
    let bpm: Double
    let swing: Double
    let lead: Timbre
    let accompTimbre: Timbre
    let start: Int          // bar where it started
    let bars: Int       // length (multiple of 4)

    func chord(inBar bar: Int) -> [Int] {
        let i = ((bar - start) / style.barsPerChord) % prog.count
        return prog[max(0, i)]
    }

    static let keyNames = ["Dó", "Ré♭", "Ré", "Mi♭", "Mi", "Fá", "Fá♯", "Sol", "Lá♭", "Lá", "Si♭", "Si"]
    var name: String { tr("%@ em %@", tr(style.name), tr(Self.keyNames[key])) }

    static func new(energy: Double, previous: Piece?, bar: Int) -> Piece {
        // style: weighted draw by distance from the energy (15% any), like the radio's energyPick
        let chosenStyle: Style
        if let id = Generator.preferredStyle, let s = Generator.styles.first(where: { $0.id == id }), Double.random(in: 0...1) < 0.6 {
            chosenStyle = s
        } else if Double.random(in: 0...1) < 0.15 {
            chosenStyle = Generator.pick(Generator.styles)
        } else {
            let weights = Generator.styles.map { exp(-pow($0.energy - energy, 2) / 0.06) }
            var r = Double.random(in: 0..<weights.reduce(0, +)), i = 0
            while r - weights[i] > 0 && i < weights.count - 1 { r -= weights[i]; i += 1 }
            chosenStyle = Generator.styles[i]
        }
        // key: 75% matches the previous one (the same, a fifth up or down, sometimes a whole step up)
        var key = Generator.pick(chosenStyle.keys)
        if let a = previous, Double.random(in: 0...1) < 0.75 {
            key = (a.key + Generator.pick([0, 0, 7, 5, 2])) % 12
        }
        let progName = Generator.pick(chosenStyle.progs)
        let prog = (Generator.presets[progName] ?? ["C"]).map { id in (Generator.chords[id] ?? [0, 4, 7]).map { ($0 + key) % 12 } }
        let lo = chosenStyle.bpm.lowerBound, hi = chosenStyle.bpm.upperBound
        let bpm = (lo + (hi - lo) * (0.3 + 0.7 * Double.random(in: 0...1) * (0.5 + energy * 0.5))).rounded()
        return Piece(style: chosenStyle, key: key, prog: prog, progName: progName, bpm: bpm,
                    swing: Double.random(in: chosenStyle.swing), lead: Generator.pick(chosenStyle.lead), accompTimbre: Generator.pick(chosenStyle.accompTimbre),
                    start: bar, bars: Generator.pick([32, 36, 40]))
    }
}
