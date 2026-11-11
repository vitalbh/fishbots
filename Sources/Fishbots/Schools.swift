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
            // its own turn is over: the pearls it gathered from its school are let go, down to the sand
            if f.state == .done, !f.necklace.isEmpty {
                for (n, c) in f.necklace.enumerated() {
                    addParticle(Particle(pos: f.pos + [Float(n % 4 - 2) * 7, -f.size * 0.3], vel: [Float.random(in: -14...14), Float.random(in: -70 ... -36)],
                                         life: 0, maxLife: Float.random(in: 1.6...2.4), size: 5, grow: 0, kind: 4, color: SIMD4(c, 1)))
                }
                f.necklace = []
            }
            // (asleep with a school that rests too, it stays asleep)
            guard f.state != .waiting, f.state != .error, working || !sleeping(f) else {
                return Heading(target: target, speed: speed, scale: scale)
            }
            f.glow = max(f.glow, 0.42 + 0.1 * sinf(Float(time) * 1.3))
            // waiting on its school (`fishbots wait`): it holds still, turned to them, listening
            if let them = awaited[f.id], !them.isEmpty {
                let there = mine.filter { them.contains($0.id) }.map(\.pos)
                let middle = there.isEmpty ? f.pos : there.reduce(SIMD2<Float>(0, 0), +) / Float(there.count)
                let to = middle - f.pos, far = simd_length(to)
                let hover = f.pos + (far > 1 ? to / far * 10 : [0, 0]) + [0, sinf(Float(time) * 0.9 + Float(f.phase)) * 6]
                // (from too high or too low it first swims to the open water, then holds)
                let y = max(size.y * 0.34, min(size.y * 0.76, hover.y))
                let x = max(size.x * 0.12, min(size.x * 0.88, hover.x))
                let out = abs(f.pos.y - y) > 28 || abs(f.pos.x - x) > 28
                return Heading(target: [x, y], speed: out ? 75 : 9, scale: max(scale, 1.4))
            }
            let t = Float(time) * (working ? 0.16 : 0.08) + Float(f.phase) * 1.9
            let round: SIMD2<Float> = [size.x * (0.5 + 0.34 * sinf(t) + 0.06 * sinf(t * 2.7 + 1)),
                                       size.y * (0.56 + 0.2 * sinf(t * 1.37 + 0.8) + 0.05 * cosf(t * 3.1))]
            return Heading(target: round, speed: working ? 105 : 55, scale: max(scale, 1.4))
        }
        guard let leader = leader(of: f) else { return nil }
        // dressed as the leader's: the same markings and fin, in its own project's color
        if f.pattern != leader.pattern || f.cut != leader.cut { f.pattern = leader.pattern; f.cut = leader.cut }
        // done: its pearl goes up the thread (2 s) and stays with the leader, one for each piece of work
        if f.state != .done { f.pearlGiven = false }
        else if !f.pearlGiven, time - f.since >= Self.pearlTrip {
            f.pearlGiven = true
            leader.necklace.append(f.color)
            if leader.necklace.count > 12 { leader.necklace.removeFirst() }
            leader.glow = 1
        }
        guard f.state != .waiting, f.state != .error else { return nil }
        var go = Heading(target: target, speed: speed, scale: min(scale, 0.74))
        guard f.action == nil, !sleeping(f) else { return go }
        // its place in the V: the first two right behind the leader, one on each side, the next two farther back
        let mates = school(of: leader)
        let i = mates.firstIndex { $0 === f } ?? 0
        let row = Float(i / 2 + 1), side: Float = i % 2 == 0 ? 1 : -1
        let facing: Float = leader.facingX >= 0 ? 1 : -1
        var gap = leader.size * 0.85 + 22
        // the last one has just finished: they close in around the leader for a moment, as if reporting
        let resting = mates.allSatisfy { [.done, .idle, .ok].contains($0.state) }
        if resting, let last = mates.filter({ $0.state == .done }).map(\.since).max(), time - last < 6 { gap *= 0.55 }
        let sway = SIMD2(cosf(Float(time) * 0.9 + Float(f.phase)), sinf(Float(time) * 1.3 + Float(f.phase))) * 5
        go.target = leader.pos + [-facing * gap * row, side * gap * 0.5 * row] + sway
        go.target.y = max(size.y * 0.12, min(size.y * 0.9, go.target.y))
        let away = simd_distance(f.pos, go.target)
        go.speed = min(190, 30 + away * 1.4)      // far from its place it hurries, in place it idles along
        return go
    }

    /// How long a finished child's pearl takes to go up its thread, in seconds.
    static let pearlTrip: Double = 2

    /// The threads of light from each leader to its school, behind the fish, and what goes along them:
    /// - a bubble of light down to a child that was just told something (its task, a reply);
    /// - a short pulse up for every tool a child uses, so a busy thread flickers and an idle one is still;
    /// - a pearl up from a child that finished, which stays strung behind the leader;
    /// - taut and blinking amber to one that waits for the person, red and slack to one in error;
    /// - while the leader waits on its school, the threads to those it waits for are lit and the others dim.
    func threads() -> [Sprite] {
        var out: [Sprite] = []
        let now = Float(time)
        for f in fish where !f.decor && !f.leaving && f.leaderID != nil && !isHidden(f) {
            guard let leader = leader(of: f), !isHidden(leader) else { continue }
            let a = leader.pos, b = f.pos
            let span = simd_distance(a, b)
            guard span > 6 else { continue }
            let slack = min(46, span * 0.16)
            let sag: Float = f.state == .waiting ? 1.5 : f.state == .error ? slack * 2.3 + 14 + sinf(now * 0.5 + Float(f.phase)) * 6
                : slack + sinf(now * 0.8 + Float(f.phase)) * 4
            let mid = (a + b) / 2 - [0, sag]
            func at(_ u: Float) -> SIMD2<Float> { (1 - u) * (1 - u) * a + 2 * u * (1 - u) * mid + u * u * b }
            let depth = (leader.depth + f.depth) / 2
            let dim = 1 - 0.5 * depth
            var tint = mix(mix(f.color, leader.color, t: 0.5), SIMD3<Float>(0.85, 0.95, 1), t: 0.45)
            var base: Float = 0.17
            switch f.state {
            case .waiting:
                tint = mix(tint, [1, 0.7, 0.3], t: 0.7)
                base = sinf(now * 6.5) > 0 ? 0.6 : 0.16                                  // it blinks
            case .error:
                tint = mix(tint, [1, 0.25, 0.2], t: 0.75)
                base = 0.3
            case .busy, .born: base = 0.22
            case .done: base = time - f.since < 8 ? 0.34 : 0.2
            default: break
            }
            // the leader waits on its school: lit to those it waits for, dim to the rest
            if let them = awaited[leader.id], !them.isEmpty, f.state != .waiting, f.state != .error {
                base = them.contains(f.id) ? max(base, 0.4 + 0.06 * sinf(now * 1.6 + Float(f.phase))) : 0.1
            }
            // pulses going up: one for each tool it used in the last second
            let pulses: [Float] = f.state == .busy ? f.toolTimes.suffix(6).compactMap { t in
                let age = Float(time - t)
                return age >= 0 && age < 0.9 ? 1 - age / 0.9 : nil
            } : []
            let pieces = 10
            var from = a
            for k in 1...pieces {
                let u = Float(k) / Float(pieces)
                let to = at(u)
                let d = to - from, l = simd_length(d)
                if l > 0.5 {
                    var glow = base
                    for p in pulses { glow += 0.7 * expf(-powf((u - 0.5 / Float(pieces) - p) / 0.1, 2)) }
                    out.append(Sprite(pos: (from + to) / 2, dir: d / l, size: l / 2 + 0.6, kind: 7, glow: glow * dim, phase: 0,
                                      color: SIMD4(tint, 1), extra: [1, 0, 0, f.state == .error ? 1 : 1.3]))
                }
                from = to
            }
            // told something: a bubble of light goes down to it
            let told = Float(time - f.toldAt) / 1.4
            if told >= 0, told < 1 {
                let p = at(told)
                out.append(Sprite(pos: p, dir: [1, 0], size: 5.5, kind: 4, glow: 0.9 * dim, phase: 0, color: [0.8, 0.95, 1, 1], extra: [1, 0, 0, 0]))
                out.append(Sprite(pos: p, dir: [1, 0], size: 6.5, kind: 1, glow: 0.5, phase: 0, color: [0.85, 0.95, 1, 0.9], extra: [1, 0, 0, 0]))
            }
            // finished: its pearl goes up to the leader
            if f.state == .done, !f.pearlGiven {
                let u = 1 - Float(min(1, max(0, (time - f.since) / Self.pearlTrip)))
                out.append(Sprite(pos: at(u), dir: [1, 0], size: 6, kind: 12, glow: 1, phase: Float(f.phase),
                                  color: SIMD4(f.color, 1), extra: [1, 0, 0, 0]))
            }
        }
        // each leader's pearls, strung behind it and swaying after it
        for l in fish where !l.necklace.isEmpty && !l.leaving && !isHidden(l) {
            let back: Float = l.facingX >= 0 ? -1 : 1
            for (n, c) in l.necklace.enumerated() {
                let i = Float(n)
                let p = l.pos + [back * (l.size * 0.66 + i * 10.5), -l.size * 0.18 - i * i * 0.35 + sinf(now * 1.7 - i * 0.55) * 2.2]
                out.append(Sprite(pos: p, dir: [1, 0], size: 6.5, kind: 12, glow: n == l.necklace.count - 1 ? max(0.25, l.glow) : 0.2,
                                  phase: i, color: SIMD4(c, 1), extra: [1, 0, 0, 0]))
            }
        }
        return out
    }
}
