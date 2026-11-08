import Foundation

/// A motif note: step (sixteenth, 0…15), pentatonic degree and duration in steps.
struct MotifNote {
    let step: Int
    let degree: Int
    let len: Int
}

/// Motifs: the sonic identity of each thing. Each source+label gets one and it never changes.
enum Motifs {
    static let pool: [[MotifNote]] = [
        [n(0, 0, 2), n(2, 2, 2), n(4, 4, 4), n(8, 2, 4)],               // up, up, down
        [n(0, 4, 3), n(3, 3, 3), n(6, 2, 2), n(8, 0, 6)],               // descent
        [n(0, 0, 1), n(1, 0, 1), n(2, 4, 4), n(8, 3, 4)],               // repeat and leap
        [n(0, 2, 4), n(4, 1, 2), n(6, 2, 2), n(8, 5, 6)],               // there, back and leap
        [n(0, 5, 2), n(2, 4, 2), n(4, 5, 2), n(6, 7, 6)],               // high
        [n(0, 0, 6), n(6, 1, 2), n(8, 2, 2), n(10, 4, 6)],              // long and stairs
        [n(0, 3, 2), n(3, 3, 1), n(4, 2, 2), n(6, 0, 2), n(8, 1, 6)],
        [n(0, 0, 2), n(4, 4, 2), n(8, 0, 2), n(12, 5, 4)],              // spaced leaps
        [n(0, 2, 1), n(1, 3, 1), n(2, 4, 1), n(3, 5, 1), n(4, 4, 4)],   // quick little stairs
        [n(0, 4, 4), n(4, 2, 4), n(8, 4, 2), n(10, 6, 6)],
        [n(0, 1, 3), n(3, 0, 3), n(6, -1, 2), n(8, 0, 6)],              // around the tonic
        [n(0, 7, 2), n(2, 5, 2), n(4, 4, 2), n(6, 2, 2), n(8, 0, 4)],   // cascade
        [n(0, 0, 3), n(3, 4, 3), n(6, 3, 2), n(8, 4, 2), n(10, 7, 6)],
        [n(0, 2, 2), n(2, 2, 2), n(6, 4, 2), n(8, 2, 6)],
        [n(0, 5, 6), n(6, 4, 2), n(8, 2, 6)],
        [n(0, -1, 2), n(2, 0, 2), n(4, 2, 2), n(6, 4, 8)],
    ]

    private static func n(_ s: Int, _ d: Int, _ l: Int) -> MotifNote { MotifNote(step: s, degree: d, len: l) }

    static let key = "motifs"

    /// Fixed motif for the key (source:label). The first time it picks one not used yet,
    /// starting from the name's hash; after that it's stored.
    static func motif(for projectKey: String, present: Set<Int>) -> Int {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        if let m = stored[projectKey], m >= 0, m < pool.count { return m }
        let used = Set(stored.values)
        let base = Int(fnv(projectKey) % UInt64(pool.count))
        var choice = base
        if let freeSlot = (0..<pool.count).map({ (base + $0) % pool.count }).first(where: { !used.contains($0) }) {
            choice = freeSlot
        } else if let freeSlot = (0..<pool.count).map({ (base + $0) % pool.count }).first(where: { !present.contains($0) }) {
            choice = freeSlot
        }
        stored[projectKey] = choice
        UserDefaults.standard.set(stored, forKey: key)
        return choice
    }
}

extension Motifs {
    /// Deliberately changes a key's motif (from the fish menu).
    static func swap(_ projectKey: String, to m: Int) {
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        stored[projectKey] = m
        UserDefaults.standard.set(stored, forKey: key)
    }

    /// Options to switch to: motifs no present fish uses, starting from a random point.
    static func options(_ n: Int, avoiding used: Set<Int>) -> [Int] {
        let base = Int.random(in: 0..<pool.count)
        let freeSlots = (0..<pool.count).map { (base + $0) % pool.count }.filter { !used.contains($0) }
        return Array(freeSlots.prefix(n))
    }

    private static let mutedKey = "muted"
    static func muted(_ projectKey: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: mutedKey) ?? []).contains(projectKey)
    }
    static func mute(_ projectKey: String, _ on: Bool) {
        var l = Set(UserDefaults.standard.stringArray(forKey: mutedKey) ?? [])
        if on { l.insert(projectKey) } else { l.remove(projectKey) }
        UserDefaults.standard.set(Array(l), forKey: mutedKey)
    }
}

/// Hash stable across runs (Swift's hashValue changes on every run).
func fnv(_ s: String) -> UInt64 {
    var h: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 { h ^= UInt64(b); h &*= 0x0000_0100_0000_01b3 }
    return h
}
