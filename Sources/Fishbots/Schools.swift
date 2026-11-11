import Foundation
import simd

/// Sessions launched by another one (`fishbots spawn`) and the one that launched them: a school. The leader is
/// drawn as the theme's leader kind and a little bigger, from its first child until its own session ends; the others are smaller, dressed with its markings, keep a
/// V behind it and are tied to it by a thread of light.
extension Tank {
    /// The fish of the session that launched this one, while it's in the tank.
    func leader(of f: Fish) -> Fish? {
        guard let id = f.leaderID else { return nil }
        return fish.first { $0.id == id && !$0.leaving }
    }

    /// The sessions this one launched, oldest first.
    func school(of f: Fish) -> [Fish] {
        fish.filter { $0.leaderID == f.id && !$0.decor && !$0.leaving }.sorted { $0.bornAt < $1.bornAt }
    }

    /// Where a session's own business (`target`, `speed`, `scale`) ends up once its school has a say; nil: it's in
    /// no school. Whoever waits for you still goes to the glass, the sick one still sinks, and one that's doing
    /// something (nibbling at a rock, foraging) goes and does it, then comes back to its place.
    func schooled(_ f: Fish, target: SIMD2<Float>, speed: Float, scale: Float) -> Heading? {
        let mine = school(of: f)
        if !mine.isEmpty, !f.leading { f.leading = true }
        if f.leading {
            // its shape is the leader's from the first one it launches until its session ends
            let kind = FishKinds.index(of: FishKinds.worn(by: f))
            if f.species != kind { f.species = kind }
            // with no one behind it right now, it goes about its own business (a little bigger than the rest)
            guard !mine.isEmpty else { return Heading(target: target, speed: speed, scale: max(scale, 1.2)) }
            // at the glass when it waits for you, sinking when it's sick, as anyone; otherwise it leads: out in the
            // open water, on a wide winding round of the tank (never down on the sand, where its school would have no
            // room behind it), brisk while any of them works and easy when they all rest, and lit up
            let working = mine.contains { $0.state == .busy || $0.state == .born || $0.state == .waiting }
            // (asleep with a school that rests too, it stays asleep)
            guard f.state != .waiting, f.state != .error, working || !sleeping(f) else {
                return Heading(target: target, speed: speed, scale: scale)
            }
            let t = Float(time) * (working ? 0.16 : 0.08) + Float(f.phase) * 1.9
            let round: SIMD2<Float> = [size.x * (0.5 + 0.34 * sinf(t) + 0.06 * sinf(t * 2.7 + 1)),
                                       size.y * (0.56 + 0.2 * sinf(t * 1.37 + 0.8) + 0.05 * cosf(t * 3.1))]
            f.glow = max(f.glow, 0.42 + 0.1 * sinf(Float(time) * 1.3))
            return Heading(target: round, speed: working ? 105 : 55, scale: max(scale, 1.4))
        }
        guard let leader = leader(of: f) else { return nil }
        // dressed as the leader's: the same markings and fin, in its own project's color
        if f.pattern != leader.pattern || f.cut != leader.cut { f.pattern = leader.pattern; f.cut = leader.cut }
        guard f.state != .waiting, f.state != .error else { return nil }
        var go = Heading(target: target, speed: speed, scale: min(scale, 0.74))
        guard f.action == nil, !sleeping(f) else { return go }
        // its place in the V: the first two right behind the leader, one on each side, the next two farther back
        let mates = school(of: leader)
        let i = mates.firstIndex { $0 === f } ?? 0
        let row = Float(i / 2 + 1), side: Float = i % 2 == 0 ? 1 : -1
        let facing: Float = leader.facingX >= 0 ? 1 : -1
        let gap = leader.size * 0.85 + 22
        let sway = SIMD2(cosf(Float(time) * 0.9 + Float(f.phase)), sinf(Float(time) * 1.3 + Float(f.phase))) * 5
        go.target = leader.pos + [-facing * gap * row, side * gap * 0.5 * row] + sway
        go.target.y = max(size.y * 0.12, min(size.y * 0.9, go.target.y))
        let away = simd_distance(f.pos, go.target)
        go.speed = min(190, 30 + away * 1.4)      // far from its place it hurries, in place it idles along
        return go
    }

    /// The threads of light from each leader to its school, behind the fish: a slack line that sags a little, with
    /// a spark running down it to whoever is working and back up from whoever just finished.
    func threads() -> [Sprite] {
        var out: [Sprite] = []
        for f in fish where !f.decor && !f.leaving && f.leaderID != nil && !isHidden(f) {
            guard let leader = leader(of: f), !isHidden(leader) else { continue }
            let a = leader.pos, b = f.pos
            let span = simd_distance(a, b)
            guard span > 6 else { continue }
            let sag = min(46, span * 0.16) + sinf(Float(time) * 0.8 + Float(f.phase)) * 4
            let mid = (a + b) / 2 - [0, sag]
            let depth = (leader.depth + f.depth) / 2
            let tint = mix(mix(f.color, leader.color, t: 0.5), SIMD3<Float>(0.85, 0.95, 1), t: 0.45)
            // the spark: toward the one at work, from the one that just finished; none while it rests
            var spark: Float? = nil
            let beat = Float(time) * 0.55 + Float(f.phase) * 0.37
            if f.state == .busy || f.state == .born { spark = beat - floorf(beat) }
            else if f.state == .done, time - f.since < 6 { spark = 1 - (beat * 1.6 - floorf(beat * 1.6)) }
            let pieces = 9
            var from = a
            for k in 1...pieces {
                let u = Float(k) / Float(pieces)
                let to = (1 - u) * (1 - u) * a + 2 * u * (1 - u) * mid + u * u * b
                let d = to - from, l = simd_length(d)
                if l > 0.5 {
                    var glow: Float = 0.2 + (f.state == .waiting ? 0.25 + 0.2 * sinf(Float(time) * 4) : 0)
                    if let s = spark { glow += 0.75 * expf(-powf((u - 0.5 / Float(pieces) - s) / 0.13, 2)) }
                    out.append(Sprite(pos: (from + to) / 2, dir: d / l, size: l / 2 + 0.6, kind: 7,
                                      glow: glow * (1 - 0.5 * depth), phase: 0,
                                      color: SIMD4(f.state == .waiting ? mix(tint, [1, 0.7, 0.3], t: 0.6) : tint, 1),
                                      extra: [1, 0, 0, 1.3]))
                }
                from = to
            }
        }
        return out
    }
}
