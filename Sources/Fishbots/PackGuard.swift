import Foundation
import QuartzCore

/// Keeps a pack's drawings from making the aquarium heavy. The renderer reports how long the GPU took for every frame;
/// when it stays over budget with pack drawings on screen, the guard hides them for a moment to see whether they are the
/// cause, then hides one pack at a time to find which one, and pauses that pack (it's left out of the shader until it's
/// turned back on). A frame that the GPU aborts with pack drawings on screen pauses those packs at once.
final class PackGuard {
    /// Told the pack to pause and why ("slow" or "gpu").
    var onCulprit: ((String, String) -> Void)?
    /// Over this average (ms per frame, for 3 s: under 30 frames a second) the guard looks into it.
    /// FISHBOTS_PACK_BUDGET_MS changes it.
    let budget: Double = Env.value("PACK_BUDGET_MS").flatMap(Double.init) ?? 33
    /// After a test that cleared the packs (the aquarium itself is slow here), it waits longer each time before trying
    /// again, so the pack drawings don't blink every minute on a machine that's just busy.
    private var backoff: Double = 60
    private let log = ProcessInfo.processInfo.environment["FISHBOTS_GUARDLOG"] == "1"

    private(set) var hidden: Set<String> = []
    private var present: Set<String> = []
    private var samples: [(t: Double, ms: Double)] = []
    private enum Phase {
        case watch
        case testAll(since: Double, before: Double)
        case testOne(queue: [String], at: Int, since: Double, before: Double, drops: [String: Double])
        case rest(until: Double)
    }
    private var phase: Phase = .watch
    /// The frames since a test began (the first few were already queued on the GPU before the drawings were hidden).
    private var testFrames: [Double] = []
    private func settled(_ since: Double, _ now: Double) -> Double? {
        let s = testFrames.dropFirst(4)
        guard s.count >= 8 || (s.count >= 2 && now - since > 4) else { return nil }
        return s.reduce(0, +) / Double(s.count)
    }

    /// The pack a sprite was drawn by (nil: the app's own).
    static func pack(of s: Sprite) -> String? {
        let i = Int(s.extra.z + 0.5)
        switch s.kind {
        case 0: return FishKinds.all.indices.contains(i) ? FishKinds.all[i].pack : nil
        case 35: return SceneryKinds.all.indices.contains(i) ? SceneryKinds.all[i].pack : nil
        case 36: return FaunaKinds.all.indices.contains(i) ? FaunaKinds.all[i].pack : nil
        case 37: return PackPresences.all.indices.contains(i) ? PackPresences.all[i].pack : nil
        default: return nil
        }
    }

    /// The frame's sprites without the ones being tested (and notes which packs are on screen).
    func filter(_ sprites: [Sprite]) -> [Sprite] {
        var seen = Set<String>()
        let out = sprites.filter { s in
            guard let p = Self.pack(of: s) else { return true }
            seen.insert(p)
            return !hidden.contains(p)
        }
        present = seen
        return out
    }

    /// Something of this pack is drawn this frame that isn't a sprite (its theme's background).
    func notePresent(_ pack: String) { present.insert(pack) }

    private func average(since t0: Double) -> (ms: Double, n: Int) {
        let s = samples.filter { $0.t >= t0 }
        return (s.isEmpty ? 0 : s.map(\.ms).reduce(0, +) / Double(s.count), s.count)
    }

    /// One frame done on the GPU: how long it took, and whether the GPU aborted it.
    func gpu(ms: Double, failed: Bool) {
        let now = CACurrentMediaTime()
        if failed {
            let on = present.subtracting(hidden)
            guard !on.isEmpty else { return }
            for p in on { onCulprit?(p, "gpu") }
            hidden = []; samples = []; phase = .rest(until: now + 30)
            return
        }
        if log {
            FileHandle.standardError.write(Data("guard: \(Int(ms)) ms, present \(present), hidden \(hidden), phase \(phase)\n".utf8))
        }
        samples.append((now, ms))
        samples.removeAll { $0.t < now - 4 }
        switch phase {
        case .watch:
            let (avg, n) = average(since: now - 3)
            guard !present.isEmpty, let first = samples.first else { return }
            // a little slow for 3 s, or very slow (a few frames are enough: at 1 frame a second there won't be many)
            let slow = n >= 30 && avg > budget && now - first.t > 2.8
            let crawling = n >= 2 && avg > 120
            guard slow || crawling else { return }
            // too slow with pack drawings on screen: hide them all for a moment
            phase = .testAll(since: now, before: avg)
            hidden = present
            testFrames = []
        case .testAll(let since, let before):
            testFrames.append(ms)
            guard let avg = settled(since, now) else { return }
            if avg < before * 0.6 {
                let queue = hidden.sorted()
                if queue.count == 1 { finish(queue[0], now) }
                else { phase = .testOne(queue: queue, at: 0, since: now, before: before, drops: [:]); hidden = [queue[0]]; testFrames = [] }
            } else {
                hidden = []; phase = .rest(until: now + backoff)    // not the packs: leave them alone for a while
                backoff = min(3600, backoff * 2)
            }
        case .testOne(let queue, let at, let since, let before, var drops):
            testFrames.append(ms)
            guard let avg = settled(since, now) else { return }
            drops[queue[at]] = before - avg
            if at + 1 < queue.count {
                phase = .testOne(queue: queue, at: at + 1, since: now, before: before, drops: drops)
                hidden = [queue[at + 1]]
                testFrames = []
            } else if let worst = drops.max(by: { $0.value < $1.value })?.key {
                finish(worst, now)
            }
        case .rest(let until):
            if now > until { phase = .watch }
        }
    }

    private func finish(_ pack: String, _ now: Double) {
        hidden = []; samples = []
        phase = .rest(until: now + 30)
        onCulprit?(pack, "slow")
    }
}
