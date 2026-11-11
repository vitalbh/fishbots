import Foundation
import simd

/// Where a fish wants to go this frame, how fast, and how big it should look.
struct Heading {
    var target: SIMD2<Float>
    var speed: Float
    var scale: Float = 1
}

/// How the fish swim: where each one is heading (its state, what it's doing, who is around) and the motion
/// that takes it there.
extension Tank {
    /// One fish, one frame: where it is heading, around the scenery, and the motion that takes it there.
    func steer(_ f: Fish, dt: Float, food: [Int], waiting: [Fish]) {
        if let to = f.grabbedTo {
            // pulled by the mouse: follows it with a little lag, tail beating fast
            f.vel += ((to - f.pos) * 7 - f.vel) * min(1, dt * 8)
            f.pos += f.vel * dt
            f.tail += dt * 14
            return
        }
        // jump: rises to the surface and arcs through the air, splashing on the way out and back
        if f.jumpPhase > 0 && !f.leaving && !f.decor { jump(f, dt: dt); return }
        // in focus (mouse over it or card open): small circle in place
        if f.id == focused && !f.leaving && f.jumpPhase == 0 { circle(f, dt: dt); return }
        let w = size.x, h = size.y
        let go = heading(f, dt: dt, food: food, waiting: waiting)
        var target = go.target, speed = go.speed
        let scaleTarget = go.scale

        // its kind's pace and bob
        let sw = swim(f)
        speed *= sw.speed
        if sw.bob > 0 { target.y += sinf(Float(time) * 1.3 + Float(f.phase)) * sw.bob * f.size }

        // the scenery: they go around it instead of through it
        if !f.leaving && f.jumpPhase == 0 {
            for s in scenery.items where s.solid {
                let (c, sz) = scenery.place(self, s)
                let r = sz * 1.15 + f.size * 0.5
                let away = f.pos - c, la = simd_length(away)
                if la < r {
                    target = c + (la > 0.1 ? away / la : [0, 1]) * (r + 24)
                    speed = max(speed, 70)
                } else {
                    let to = target - c, lt = simd_length(to)
                    if lt < r { target = c + (lt > 0.1 ? to / lt : [0, 1]) * r }
                }
            }
        }

        let d = target - f.pos
        let l = simd_length(d)
        var desired: SIMD2<Float> = l > 1 ? d / l * min(speed, l * 2.2) : .zero
        if f.state == .waiting && l < 12 { desired = [f.vel.x > 0 ? 6 : -6, 0] } // faces forward, swimming in place
        f.vel += (desired - f.vel) * min(1, dt * (f.decor ? 3 : f.action != nil ? 3 : 1.8))
        if f.shake > 0 {
            f.vel += SIMD2(Float.random(in: -1...1), Float.random(in: -1...1)) * 220 * f.shake * dt
            f.shake = max(0, f.shake - dt * 0.6)
        }
        if f.state == .error && Float.random(in: 0...1) < dt * 0.15 { f.shake = 0.25 }
        f.pos += f.vel * dt
        f.pos.x += current * dt * (f.decor ? 0.9 : 0.5)
        if !f.leaving && f.pos.y < h + 40 {
            f.pos.y = max(40 + f.size * 0.3, min(h - 20, f.pos.y))
            f.pos.x = max(10, min(w - 10, f.pos.x))
        }
        f.scale += (scaleTarget - f.scale) * min(1, dt * 2)
        // the tail beats with speed, and harder while accelerating (a push)
        let speedNow = simd_length(f.vel)
        let push = max(0, (speedNow - f.lastSpeed) / max(dt, 0.001))
        f.lastSpeed = speedNow
        f.tail += dt * (4 + speedNow * 0.1 + min(push * 0.04, 10)) * sw.beat
        f.glow *= expf(-dt * 2.5)
    }

    /// Out of the water: rises to the surface, arcs through the air and falls back in.
    private func jump(_ f: Fish, dt: Float) {
        let h = size.y
        let surf = h * 0.965
        if f.jumpPhase == 1 {
            let goal: SIMD2<Float> = [f.pos.x + f.jumpDir * 40, surf]
            let d = goal - f.pos, l = simd_length(d)
            f.vel += ((l > 1 ? d / l * 430 : .zero) - f.vel) * min(1, dt * 6)
            f.pos += f.vel * dt
            if f.pos.y > surf - 28 { f.jumpPhase = 2; f.jumpT0 = time; f.jumpX0 = f.pos.x; splash(at: [f.pos.x, surf]) }
        } else {
            let u = Float(time - f.jumpT0) / 0.95
            if u >= 1 {
                f.jumpPhase = 0
                splash(at: [f.pos.x, surf])
                f.vel = [f.jumpDir * 60, -170]
            } else {
                let new: SIMD2<Float> = [f.jumpX0 + f.jumpDir * 120 * u, surf - 8 + 80 * sinf(.pi * u)]
                f.vel = (new - f.pos) / max(dt, 0.001)
                f.pos = new
            }
        }
        f.tail += dt * 16
        f.glow *= expf(-dt * 2.5)
    }

    /// A small circle in place, while the mouse is on it or its card is open.
    private func circle(_ f: Fish, dt: Float) {
        let ang = Float(time) * 1.6
        let goal = focusCenter + SIMD2(cosf(ang), sinf(ang) * 0.6) * 14
        let d = goal - f.pos
        f.vel += ((simd_length(d) > 0.5 ? d * 3 : .zero) - f.vel) * min(1, dt * 4)
        f.pos += f.vel * dt
        f.scale += (1.08 - f.scale) * min(1, dt * 3)
        f.tail += dt * (4 + simd_length(f.vel) * 0.1)
        f.glow = max(f.glow * expf(-dt * 2.5), 0.25)
    }

    /// What it does now: the first thing that applies, from a scare down to its own state.
    private func heading(_ f: Fish, dt: Float, food: [Int], waiting: [Fish]) -> Heading {
        let w = size.x, h = size.y
        var target: SIMD2<Float>
        var speed: Float
        var scaleTarget: Float = 1
        // scare: flees from the click
        let curious = !f.leaving && f.action == nil && !sleeping(f) && time - cursorAt < 8 && time - cursorRestingAt > 0.8
            && (f.decor ? f.parent == nil : (f.state == .idle || f.state == .ok || f.state == .done))
        if time < f.fearUntil && !f.leaving {
            let d = f.pos - f.fearFrom
            target = f.pos + (simd_length(d) > 1 ? simd_normalize(d) : [1, 0]) * 220
            speed = 280
        } else if let b = game, b.chaser == f.id || b.runner == f.id,
                  let other = fish.first(where: { $0.id == (b.chaser == f.id ? b.runner : b.chaser) }) {
            // tag
            if b.chaser == f.id { target = other.pos; speed = 115 }
            else {
                let d = f.pos - other.pos
                var escape = f.pos + (simd_length(d) > 1 ? simd_normalize(d) : [1, 0]) * 160
                escape = [max(w * 0.08, min(w * 0.92, escape.x)), max(h * 0.15, min(h * 0.85, escape.y))]
                target = escape; speed = 125
            }
        } else if let c = cursor, curious, simd_distance(c, f.pos) < 360 {
            // the curious ones come close to the mouse, around it
            let ang = Float(f.phase) * 1.7 + Float(time) * 0.4
            target = c + SIMD2(cosf(ang), sinf(ang) * 0.6) * (f.size * 2 + 20)
            speed = 60
        } else if let id = f.chattingWith, time < f.chatUntil, let o = fish.first(where: { $0.id == id }) {
            // chat: they meet snout to snout halfway
            let middle = (f.pos + o.pos) / 2
            target = middle + [f.pos.x < o.pos.x ? -f.size * 0.95 : f.size * 0.95, 0]
            speed = 50
        } else if f.id == highlighted && !f.leaving {
            // parade: comes to the middle, in front, glowing
            target = [w * 0.5, h * 0.5]
            speed = 220
            scaleTarget = 1.7
            f.glow = max(f.glow, 0.6)
        } else if f.leaving && f.party {
            // party: rises and exits through the surface
            target = [f.pos.x + sinf(Float(time) * 3) * 30, h + 200]
            speed = 120
        } else if f.leaving {
            target = [f.pos.x < w / 2 ? -200 : w + 200, f.pos.y]
            speed = 140
        } else if let parent = f.parent {
            // fry: swims behind the parent, around it
            if parent.leaving || !fish.contains(where: { $0 === parent }) { f.leaving = true }
            let ang = Float(f.phase) * 2.1 + Float(time) * 1.4
            let behind = parent.pos - (simd_length(parent.vel) > 1 ? simd_normalize(parent.vel) : [1, 0]) * parent.size * 1.2
            target = behind + SIMD2(cosf(ang), sinf(ang)) * parent.size * 0.7
            speed = 160
        } else if f.sings {
            if f.state == .busy {
                // playing: it dances up high, bobbing to a beat, and lets out notes now and then
                target = wanderPoint(f, yRange: (h * 0.58, h * 0.8), every: 3...6)
                target.y += sinf(Float(time) * 4.2) * 14
                speed = 55
                scaleTarget = 1.55                     // the special fish: bigger
                if time > f.noteAt {
                    f.noteAt = time + Double.random(in: 0.5...1.1)
                    notes(from: f, n: 1)
                }
            } else {
                // paused: it sinks slowly and rests
                target = [f.pos.x, h * 0.3]
                speed = 12
                scaleTarget = 1.3
            }
        } else if f.decor {
            return schooling(f, dt: dt)
        } else {
            return session(f, food: food, waiting: waiting)
        }
        return Heading(target: target, speed: speed, scale: scaleTarget)
    }

    /// A decorative fish: with its school, parting around whoever passes.
    private func schooling(_ f: Fish, dt: Float) -> Heading {
        let w = size.x, h = size.y
        var target: SIMD2<Float>
        var speed: Float
        // the school follows the neons' center, wandering
        let school = f.phase / 100
        let leads = f.phase % 100 == 0
        // many sessions in the tank: the schools step back (further, fainter), and come forward again when it empties
        f.depth += (min(0.92, f.restDepth + crowd * 0.3) - f.depth) * min(1, dt * 0.25)
        if leads && (time > f.wanderAt || simd_distance(f.pos, f.wander) < 30) {
            // each school keeps to its own height: neons in the middle, tetras up high, silversides low in the back
            let band: ClosedRange<Float> = school == 1 ? 0.55...0.88 : school == 2 ? 0.18...0.48 : 0.3...0.8
            f.wander = [Float.random(in: w * 0.12...w * 0.88), h * Float.random(in: band)]
            f.wanderAt = time + Double.random(in: school == 2 ? 7...14 : 4...9)
        }
        let leader = fish.first { $0.decor && $0.parent == nil && $0.phase == school * 100 } ?? f
        if leads {
            target = f.wander
        } else {
            // a school: toward the group's center, heading where the group heads, following the leader from a distance
            var center = SIMD2<Float>.zero, heading = SIMD2<Float>.zero, n: Float = 0
            for o in fish where o.decor && o.parent == nil && o !== f && o.phase / 100 == school { center += o.pos; heading += o.vel; n += 1 }
            if n > 0 { center /= n; heading /= n }
            let wobble = SIMD2(sinf(Float(time) * 0.7 + Float(f.phase) * 1.9), cosf(Float(time) * 0.5 + Float(f.phase))) * 9
            target = f.pos + (center - f.pos) * 0.35 + (leader.pos - f.pos) * 0.3 + heading * 0.8 + wobble
        }
        speed = (leads ? 45 : 75) * (school == 2 ? 0.7 : 1)
        // a real school: they part around a big fish passing through and close up again behind it,
        // and keep a little room between each other
        var away: SIMD2<Float> = .zero
        for o in fish where !o.decor && !o.leaving && o.parent == nil {
            let d = f.pos - o.pos, r = o.size * 2.4, l = simd_length(d)
            if l < r && l > 0.1 { away += d / l * (r - l) / r }
        }
        // a shark (a presence) going by: the school scatters, and comes back together after
        for p in scene.presences where p.kind.id == "shark" && !p.leaving {
            let d = f.pos - p.pos, r = p.kind.size * 3.2, l = simd_length(d)
            if l < r && l > 0.1 { away += d / l * (r - l) / r * 2.2 }
        }
        for o in fish where o.decor && o !== f && o.parent == nil {
            let d = f.pos - o.pos, l = simd_length(d)
            if l < 16 && l > 0.1 { away += d / l * (16 - l) / 16 * 0.6 }
        }
        if simd_length(away) > 0.01 {
            target = f.pos + simd_normalize(away) * 90 + (target - f.pos) * 0.3
            speed = 120
        }
        return Heading(target: target, speed: speed)
    }

    /// A session or a plain entity: by its state, then the sick sibling and the food.
    private func session(_ f: Fish, food: [Int], waiting: [Fish]) -> Heading {
        let w = size.x, h = size.y
        var target: SIMD2<Float>
        var speed: Float
        var scaleTarget: Float = 1
        switch f.state {
        case .waiting:
            // up at the glass, bigger, in the order they came (left to right, the first rows on top); whoever waits
            // longer gets bigger. Their places spread over the whole width and the middle of the water, and a queue
            // too long for one row breaks into rows (the fish come a little less close), so all of them and their
            // questions fit
            let i = waiting.firstIndex { $0 === f } ?? 0
            let n = max(1, waiting.count)
            let fits = max(1, Int(w * 0.88 / 130))
            let rows = min(3, (n + fits - 1) / fits)
            let perRow = (n + rows - 1) / rows
            let row = i / perRow, col = i % perRow
            let inRow = min(perRow, n - row * perRow)
            let gap = min(320, w * 0.9 / Float(perRow))
            let rowGap = rows > 1 ? h * 0.36 / Float(rows - 1) : 0
            let x = w * 0.5 + (Float(col) - Float(inRow - 1) / 2) * gap
            let y = h * 0.5 + (Float(rows - 1) / 2 - Float(row)) * rowGap
            // it doesn't park: each one swims a slow, lopsided figure eight around its place, out of step with its
            // neighbours, so the queue reads as fish waiting and not as a shelf. Almost half a place each way:
            // neighbours pass in front of each other now and then, but each keeps coming back to its own spot
            let t = Float(time) * 0.3 + Float(f.phase) * 2.1
            let reach = rows > 1 ? rowGap * 0.42 : h * 0.16
            let roam: SIMD2<Float> = [sinf(t) * gap * 0.4 + sinf(t * 2.3 + 0.7) * gap * 0.07,
                                      sinf(t * 1.6 + 1.3) * reach + sinf(t * 0.7 + Float(f.phase)) * reach * 0.3]
            target = [x, y] + roam
            speed = 120
            let crowded = rows > 1
            scaleTarget = (crowded ? 1.3 : 1.55) + min(crowded ? 0.2 : 0.35, Float(time - f.since) / 60 * 0.06)
        case .busy where f.action != nil:
            switch f.action! {
            case .nibble(let goal):
                // puts its snout against the seaweed and takes little nibbles
                target = goal + [f.actionSide * (f.size * 0.85 + sinf(Float(time) * 10) * 3), 0]
                speed = simd_distance(f.pos, goal) > f.size * 3 ? 200 : 90
            case .forage:
                target = [f.pos.x + sinf(Float(time) * 0.8 + Float(f.phase)) * 25, size.y * sand(f.pos.x / max(1, w)) + f.size * 0.85]
                speed = 170
            case .peek:
                target = [f.pos.x, h * 0.93]
                speed = 190
            case .bubbles:
                target = f.pos + [f.vel.x >= 0 ? 4 : -4, 0]   // stops to release the bubbles
                speed = 10
            case .mail:
                // goes to meet the seahorse
                if let c = mails.first(where: { $0.goal == f.id && $0.stage < 2 }) {
                    target = c.pos + [-c.side * f.size * 1.2, 0]
                    speed = 110
                } else {
                    target = f.pos
                    speed = 20
                }
            }
        case .busy:
            target = wanderPoint(f, yRange: band(f, 0.4, 0.85), every: 2.5...5)
            speed = 75 * (1 + min(1, Float(f.toolTimes.count) / 15)) * (1 - f.fat * 0.35)   // pace; a fat fish swims slowly
            speed *= burst(f)
        case .error:
            // sick: sinks slowly, almost still
            let background = size.y * sand(f.pos.x / max(1, w)) + f.size * 1.9   // near the bottom, with room for the label
            target = [f.pos.x + sinf(Float(time) * 0.4 + Float(f.phase)) * 10, max(background, f.pos.y - 18)]
            speed = 10
        case .alert:
            target = wanderPoint(f, yRange: band(f, 0.25, 0.8), every: 1.5...3)
            speed = 55
        case .done where time - f.since < 2.5:
            // comes a bit closer to the glass to knock: almost stops in place and grows a tiny bit
            target = f.pos + [f.vel.x >= 0 ? 6 : -6, 0]
            speed = 12
            scaleTarget = 1.25
        default: // idle, ok, born, done (after rising)
            if sleeping(f) {
                // lies on the sand
                target = [f.pos.x, size.y * sand(f.pos.x / max(1, w)) + f.size * 1.7]
                speed = 8
            } else if f.kindID == "octopus" && time - f.since > 45 * Self.scale {
                // an octopus whose PR sits still settles on the sand and blends in (camouflage, below)
                target = [f.pos.x + sinf(Float(time) * 0.2 + Float(f.phase)) * 6, size.y * sand(f.pos.x / max(1, w)) + f.size * 0.85]
                speed = 14
            } else {
                target = wanderPoint(f, yRange: band(f, 0.14, 0.36), every: 5...10)
                speed = 24 * burst(f)
                // a sibling from the same project also idle: they swim side by side (the newer one alongside the older)
                if let mate = fish.first(where: { $0 !== f && !$0.decor && !$0.leaving && $0.projectKey == f.projectKey
                                                  && ($0.state == .idle || $0.state == .ok) && $0.variant < f.variant }) {
                    let side: Float = f.variant % 2 == 0 ? 1 : -1
                    target = mate.pos + [-(mate.vel.x >= 0 ? 1 : -1) * mate.size * 1.4, side * mate.size * 1.1]
                    speed = 40
                }
            }
        }
        // those from the same project go take care of the sick one
        if f.state != .error && f.state != .waiting,
           let sick = fish.first(where: { $0 !== f && !$0.decor && !$0.leaving && $0.state == .error && $0.source == f.source && $0.label == f.label }) {
            let ang = Float(time) * 0.8 + Float(f.phase)
            target = sick.pos + SIMD2(cosf(ang), sinf(ang) * 0.6) * (sick.size * 2.2)
            speed = 60
        }
        // food attracts
        if f.state != .waiting, let idx = food.min(by: { simd_distance(particles[$0].pos, f.pos) < simd_distance(particles[$1].pos, f.pos) }),
           simd_distance(particles[idx].pos, f.pos) < 380 {
            target = particles[idx].pos
            speed = 150
        }
        return Heading(target: target, speed: speed, scale: scaleTarget)
    }

    /// Fish swim in bursts and glides: a few strong strokes, then coasting. Averages 1, so the pace stays the same.
    private func burst(_ f: Fish) -> Float {
        let s = 0.5 + 0.5 * sinf(Float(time) * (0.8 + Float(f.phase % 5) * 0.07) + Float(f.phase) * 1.7)
        return (0.55 + 0.9 * s * s * s) * 1.2
    }

    /// How this fish's kind swims (the kind it's drawn as, dressed by the theme or not).
    /// (The theme touches it: "*" for every kind, then the kind's own entry.)
    func swim(_ f: Fish) -> FishSwim {
        guard FishKinds.all.indices.contains(f.species) else { return FishSwim() }
        let k = FishKinds.all[f.species]
        var s = k.swim
        let tweaks = Themes.current.swim
        if tweaks.isEmpty { return s }
        if let t = tweaks["*"] { s = t.applied(to: s) }
        if let t = tweaks[k.id] { s = t.applied(to: s) }
        return s
    }

    /// The heights a free fish roams: its kind's band if it has one, otherwise the usual (fractions of the height).
    private func band(_ f: Fish, _ lo: Float, _ hi: Float) -> (Float, Float) {
        let d = swim(f).depth ?? lo...hi
        return (size.y * d.lowerBound, size.y * d.upperBound)
    }

    private func wanderPoint(_ f: Fish, yRange: (Float, Float), every: ClosedRange<Double>) -> SIMD2<Float> {
        let away = f.wander.y < yRange.0 - 10 || f.wander.y > yRange.1 + 10
        if time > f.wanderAt || simd_distance(f.pos, f.wander) < 25 || away {
            f.wander = [Float.random(in: size.x * 0.08...size.x * 0.92), Float.random(in: yRange.0...yRange.1)]
            f.wanderAt = time + Double.random(in: every)
        }
        return f.wander
    }
}
