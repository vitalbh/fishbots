import Foundation
import simd

/// What the tank looks like right now, as sprites for the renderer, back to front.
extension Tank {
    func sprites() -> [Sprite] {
        var out: [Sprite] = []
        out.reserveCapacity(fish.count + particles.count + 1)
        out += backdrop()
        out += onTheSand()
        // starfish, crabs, turtle and lanternfish
        out += dressFauna(fauna.middle(self))
        // what plugins put in the tank (the ones waiting for you come after the fish)
        out += scene.sprites(self, front: false)
        out += behindTheFish()
        out += threads()
        out += theFish()
        out += scene.sprites(self, front: true)
        // marine snow up close, in front of the fish
        out += motes.sprites(self, front: true)
        out += dust.sprites(self, front: true)
        // the snail on the glass
        out += dressFauna(fauna.front(self))
        out += onTheGlass()
        out += upFront()
        // quake: everything shakes together
        if scene.shakeOffset != .zero { for i in out.indices { out[i].pos += scene.shakeOffset } }
        // widget mode: a small window, so everything is drawn a little smaller
        if compact { for i in out.indices { out[i].size *= 0.75 } }
        return out
    }

    /// Far away and on the back glass: the theme's roots and wreck, the distant creatures, the jellyfish, the far
    /// snow and the shadows on the sand.
    private func backdrop() -> [Sprite] {
        var out: [Sprite] = []
        // mangrove roots coming down at the sides (a theme that lists "mangrove" in its scenery)
        if scenery.kinds?.contains("mangrove") == true {
            let d = Themes.current.uniforms.shallow
            let water = SIMD3(d.x, d.y, d.z) * (0.5 + 0.5 * light)
            let s = size.y * 0.5
            out.append(Sprite(pos: [size.y * 0.3, size.y * 0.5], dir: [1, 0], size: s, kind: 43, glow: 0, phase: Float(time),
                              color: SIMD4(water, 1), extra: [1, 0, 0, 0], aux: [0.7, 1.0, 0, 0]))
            // a smaller clump on the other side, mirrored
            out.append(Sprite(pos: [size.x - size.y * 0.24, size.y * 0.5], dir: [-1, 0], size: s * 0.85, kind: 43, glow: 0, phase: Float(time),
                              color: SIMD4(water, 1), extra: [-1, 0, 0, 0], aux: [0.7, 1.0, 0, 0]))
        }
        // a sunken ship far away (a theme that lists "wreck" in its scenery), then the whale in the distance
        if scenery.kinds?.contains("wreck") == true {
            let s = size.y * 0.14
            let d = Themes.current.uniforms.deep, sh = Themes.current.uniforms.shallow
            let c = mix(SIMD3(d.x, d.y, d.z), SIMD3(sh.x, sh.y, sh.z), t: 0.3) * (0.6 + 0.4 * light)
            out.append(Sprite(pos: [size.x * 0.74, size.y * 0.11 + s * 0.5], dir: [1, 0], size: s, kind: 42, glow: 0, phase: 0,
                              color: SIMD4(c, 0.8), extra: [1, 0, 0, 0], aux: [2.2, 1.0, 0, 0]))
        }
        out += dressFauna(fauna.background(self))
        // jellyfish (pad): the theme may leave it out or draw it its own way
        if Themes.current.jellyfish {
            out += dressFauna([Sprite(pos: jellyPos, dir: [1, 0], size: 30, kind: 5, glow: 0.25 + jellyGlow + (isNight ? 0.35 : 0),
                                      phase: jellyPhase, color: [0.85, 0.55, 1.0, 0.75], extra: [1, 0, 0, 0])])
        }

        // marine snow far away, and the shadows on the sand (under the fish and whatever swims)
        out += motes.sprites(self, front: false)
        out += dust.sprites(self, front: false)
        for f in fish where !isHidden(f) {
            if let s = shadow(under: f.pos, size: f.size * (1 - 0.35 * f.depth), strength: (f.leaving ? 0.4 : 1) * (1 - f.depth * 0.6)) { out.append(s) }
        }
        for p in scene.presences where [.swim, .drift, .hover].contains(p.kind.motion) {
            if let s = shadow(under: p.pos, size: p.kind.size, strength: p.alpha) { out.append(s) }
        }
        return out
    }

    /// The scenery, softened a little by the water, then the old battery, the pebbles, the day's pearls and the list pebbles.
    private func onTheSand() -> [Sprite] {
        var out: [Sprite] = []
        // the scenery: behind the pearls, the creatures and the fish, softened a little by the water
        let lit = 0.45 + 0.55 * light
        let water: SIMD3<Float> = SIMD3<Float>(0.12, 0.3, 0.4) * (0.5 + 0.5 * light)
        let night = max(0, min(1, (0.8 - light) / 0.6))
        for s in scenery.items {
            let (c, sz) = scenery.place(self, s)
            let color = mix(s.color * lit, water, t: 0.15)
            if let i = s.pack {
                // a pack's piece: its own drawing (kind 35, its index in extra.z), the quad from its extent. A chest
                // drawn by a pack gets how open it is in extra.y (instead of the seed) and glows while it's open.
                let isChest = s.id == "chest"
                let glow = max(s.glowAtNight ? night : 0, isChest ? min(1, scenery.chestLid) : 0)
                out.append(Sprite(pos: c, dir: [1, 0], size: sz, kind: 35, glow: glow, phase: Float(time),
                                  color: SIMD4(color, 1), extra: [1, isChest ? min(1, scenery.chestLid) : s.seed, Float(i), night],
                                  aux: [s.extent.x, s.extent.y, 0, 0]))
                continue
            }
            if s.id == "eggs" {
                // lit from inside: they dim less than the rest when the light goes
                // the theme's own clutch, a built-in variant (the deep sea's egg case, the lagoon's eggs on a root)
                let its = Themes.current.looks["eggs"].flatMap { Scene.variants[$0] }
                let variant: Float = FishKinds.dressByTheme && its?.of == "eggs" ? its!.n : 0
                let shade: SIMD3<Float> = variant == 1 ? [0.85, 0.6, 0.3] : variant == 2 ? [0.78, 0.9, 0.55] : s.color
                let own = mix(shade * (0.72 + 0.28 * light), water, t: 0.08)
                out.append(Sprite(pos: c, dir: [1, 0], size: sz * (variant == 1 ? 1.25 : 1), kind: s.kind, glow: scenery.eggsGlow, phase: Float(time),
                                  color: SIMD4(own, 1), extra: [1, 0, variant, 0], aux: [s.extent.x, s.extent.y, 0, 0]))
                continue
            }
            // the deep sea dresses the chest as a ship's safe (extra.z)
            // the theme's own chest, a built-in variant (the deep sea's safe, the lagoon's fish trap) in extra.z
            let look = Themes.current.looks["chest"].flatMap { Scene.variants[$0] }
            let safe: Float = s.id == "chest" && FishKinds.dressByTheme && look?.of == "chest" ? look!.n : 0
            out.append(Sprite(pos: c, dir: [1, 0], size: sz, kind: s.kind, glow: s.id == "chest" ? 0.8 + scenery.chestLid * 0.6 : 0,
                              phase: s.id == "chest" || s.id == "shell" ? Float(time) : s.seed, color: SIMD4(color, 1),
                              extra: [1, s.id == "chest" ? min(1, scenery.chestLid) : s.id == "shell" ? 1 : 0, safe, 0],
                              aux: s.kind > 40.5 ? [1, 1, 0, 0] : .zero))
        }
        // the old battery, in front of the scenery (at a spot it leaves free)
        if let b = battery {
            let a = batteryAngle
            out.append(Sprite(pos: batteryPos, dir: [cosf(a), sinf(a)], size: 17, kind: 6, glow: b,
                              phase: jellyPhase, color: [1, 1, 1, 1], extra: [1, pluggedIn ? 1 : 0, 0, 0]))
        }
        // pebbles and little shells on the sand (the theme may draw them its own way: "pebble", "seashell")
        let looks = FishKinds.dressByTheme ? Themes.current.looks : [:]
        for p in pebbles {
            let x = scenery.clear(self, size.x * p.u)
            if let look = looks[p.shell ? "seashell" : "pebble"], let i = SceneryKinds.index(of: look) {
                let k = SceneryKinds.all[i]
                let sz = p.size * 1.3
                out.append(Sprite(pos: [x, size.y * sand(x / max(1, size.x)) + sz * k.extent.y * 0.9], dir: [1, 0], size: sz, kind: 35,
                                  glow: 0, phase: Float(time), color: SIMD4(mix(k.color * lit, water, t: 0.2), 1),
                                  extra: [1, p.tone, Float(i), 0], aux: [k.extent.x, k.extent.y, 0, 0]))
                continue
            }
            let y = size.y * sand(x / max(1, size.x)) + p.size * 0.25
            let base: SIMD3<Float> = p.shell ? [0.95, 0.82, 0.74] : mix([0.36, 0.33, 0.3], [0.58, 0.52, 0.44], t: p.tone)
            out.append(Sprite(pos: [x, y], dir: [1, 0], size: p.size * (p.shell ? 1.1 : 1), kind: p.shell ? 22 : 21, glow: 0,
                              phase: p.seed, color: SIMD4(mix(base * lit, water, t: 0.2), 1), extra: [1, 0, 0, 0]))
        }
        // pearls of the day, on the sand
        let pearlLook = looks["pearl"].flatMap { SceneryKinds.index(of: $0) }
        for (i, p) in pearls.all.enumerated() {
            let new = pearls.glow(i, now: time)
            if let li = pearlLook {
                // the theme's pearl: col is the project's color, glow while it's new
                let k = SceneryKinds.all[li]
                out.append(Sprite(pos: pearls.pos(i), dir: [1, 0], size: 7, kind: 35, glow: new, phase: Float(time),
                                  color: [p.color[0], p.color[1], p.color[2], 1], extra: [1, (Float(i) * 0.618).truncatingRemainder(dividingBy: 1), Float(li), 0],
                                  aux: [k.extent.x, k.extent.y, 0, 0]))
                continue
            }
            out.append(Sprite(pos: pearls.pos(i), dir: [1, 0], size: 6, kind: 12, glow: new, phase: Float(i),
                              color: [p.color[0], p.color[1], p.color[2], 1], extra: [1, 0, 0, 0]))
        }
        // list pebbles (TodoWrite): the done ones glow in the fish's color
        for f in fish where !f.decor && !f.leaving {
            guard let t = f.todos, let u = f.todoU else { continue }
            let n = min(t.total, 12)
            for i in 0..<n {
                let x = scenery.clear(self, size.x * u + (Float(i) - Float(n - 1) / 2) * 11)
                let pu = x / max(1, size.x)
                let isDone = i < t.done
                out.append(Sprite(pos: [x, size.y * sand(pu) + 3], dir: [1, 0], size: isDone ? 4.5 : 4, kind: 12,
                                  glow: isDone ? 0.45 : 0, phase: Float(i) * 1.7,
                                  color: isDone ? SIMD4(f.color, 1) : [0.45, 0.42, 0.38, 1], extra: [1, 0, 0, 0]))
            }
        }
        return out
    }

    /// Ink, murky water, bubbles and food.
    private func behindTheFish() -> [Sprite] {
        var out: [Sprite] = []
        // ink and murky water (behind the fish)
        for p in particles where p.kind == 10 {
            let k = 1 - p.life / p.maxLife
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: 10, glow: min(1, p.life * 2) * k, phase: 0,
                              color: p.color, extra: [1, 0, 0, 0]))
        }

        let bubbleLook = themeLook("bubble"), foodLook = themeLook("food")
        for p in particles where p.kind == 3 || p.kind == 1 {
            let a = p.kind == 3 ? min(1, (p.maxLife - p.life) / 2) : 1
            if let (i, k) = p.kind == 1 ? bubbleLook : foodLook {
                out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size * (p.kind == 1 ? 1.2 : 1.6), kind: 35, glow: a, phase: Float(time),
                                  color: SIMD4(k.color * (0.55 + 0.45 * light), a), extra: [1, (p.pos.x * 0.013).truncatingRemainder(dividingBy: 1), Float(i), 0],
                                  aux: [k.extent.x, k.extent.y, 0, 0]))
                continue
            }
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: p.kind, glow: a, phase: 0,
                              color: p.color, extra: [1, 0, 0, 0]))
        }
        return out
    }

    /// Their reflections under the surface, then the fish themselves, far ones first.
    private func theFish() -> [Sprite] {
        var out: [Sprite] = []
        // fish near the surface show upside down on its underside, faint
        let surfY = size.y * 0.965
        for f in fish where !f.leaving && !isHidden(f) && surfY - f.pos.y < f.size * 2.2 && f.pos.y < surfY {
            let gap = surfY - f.pos.y
            let a = (1 - gap / (f.size * 2.2)) * 0.28
            let l = simd_length(f.vel)
            let dx: Float = l > 0.01 && f.vel.x < 0 ? -1 : 1
            out.append(Sprite(pos: [f.pos.x, surfY + gap * 0.6], dir: [dx, 0], size: f.size * (1 - 0.35 * f.depth), kind: 0,
                              glow: 0, phase: f.tail, color: SIMD4(mix(f.color, [0.7, 0.9, 1], t: 0.4), a),
                              extra: [-dx * max(abs(f.facingX), 0.12), Float(f.pattern + f.cut * 8), Float(f.species), 0]))
        }

        // far ones first (they stay behind)
        for f in fish.sorted(by: { $0.depth > $1.depth }) where !isHidden(f) {
            let l = simd_length(f.vel)
            var dx = l > 0.01 ? f.vel.x / l : 1
            var dy = l > 0.01 ? f.vel.y / l : 0
            // during the action, the body follows what it's doing, not just the velocity
            if let a = f.action, f.state == .busy {
                switch a {
                case .nibble(let goal) where simd_distance(f.pos, goal) < f.size * 2.2:
                    dx = -f.actionSide; dy = 0
                case .forage where f.pos.y - size.y * sand(f.pos.x / max(1, size.x)) < f.size * 1.6:
                    dx = dx >= 0 ? 0.8 : -0.8; dy = -0.6
                case .peek where f.pos.y > size.y * 0.86:
                    dx = dx >= 0 ? 0.8 : -0.8; dy = 0.6
                default: break
                }
            }
            let octopus = f.kindID == "octopus"      // the octopus doesn't tilt or mirror: always stays upright
            let asleep = sleeping(f)
            let upright = swim(f).upright
            var tilt = octopus || upright ? 0 : max(-0.5, min(0.5, atan2f(dy, abs(dx))))
            if f.state == .error && !octopus && !f.decor { tilt = -0.6 + 0.08 * sinf(Float(time) * 0.7) }   // sick: nose down
            if asleep && !octopus { tilt = 0 }
            // chatting: facing each other
            if let id = f.chattingWith, time < f.chatUntil, let o = fish.first(where: { $0.id == id }),
               simd_distance(f.pos, o.pos) < (f.size + o.size) * 1.6 {
                dx = o.pos.x > f.pos.x ? 1 : -1; tilt = 0
            }
            // natural turns: the facing glides through 0 instead of flipping, and the tilt eases in
            let wantFacing: Float = octopus ? 1 : (dx >= 0 ? 1 : -1)
            if abs(wantFacing - f.facingX) > 0.001 {
                let turnRate: Float = f.decor ? 9 : 5.5                       // about a quarter of a second
                f.facingX += (wantFacing > f.facingX ? 1 : -1) * min(abs(wantFacing - f.facingX), turnRate * frameDt)
            }
            f.lean += (tilt - f.lean) * min(1, frameDt * 5)
            // mid-turn it arcs: the nose rises a little
            tilt = f.lean + (octopus ? 0 : 0.22 * (1 - abs(f.facingX)))
            tilt += f.spin * f.spin * 2 * .pi                                                          // little spin when it recovers
            let theta = f.facingX >= 0 ? tilt : Float.pi - tilt
            var c = f.color
            var alpha: Float = 1
            switch f.state {
            case .error:
                // sick: fades, pulled toward a grayish green
                let gray = (c.x + c.y + c.z) / 3
                c = mix(SIMD3(repeating: gray), [0.55, 0.62, 0.5], t: 0.4) * 0.85
                if octopus { c = mix(f.color, [1, 0.18, 0.15], t: 0.6) }
            case .alert: c = mix(c, [1, 0.75, 0.2], t: 0.5)
            case .idle, .ok:
                if f.sings { c = mix(SIMD3(repeating: (c.x + c.y + c.z) / 3), c, t: 0.25) * 0.6 }   // paused: almost gray
                else { c *= 0.75 }
            case .done: if time - f.since > 3 { c *= 0.75 }
            default: break
            }
            if f.decor { alpha = 0.85 }
            if asleep { c *= 0.8 }
            // camouflage: an octopus resting on the sand takes the sand's color, little by little (back in color when its state changes)
            if octopus && (f.state == .idle || f.state == .ok) && !f.leaving && !f.leading {
                let camo = smoothstep(45, 80, Float((time - f.since) / Self.scale))
                c = mix(c, SIMD3<Float>(0.5, 0.44, 0.33) * (0.45 + 0.55 * light), t: camo * 0.85)
            }
            var glow = f.glow
            if f.state == .waiting { glow = max(glow, 0.35 + 0.35 * sinf(Float(time) * 4)) }
            if f.offer != nil { glow = max(glow, 0.2 + 0.2 * sinf(Float(time) * 2)) }       // softer than waiting
            // waking up: stretches (grows and shrinks back)
            var len = f.size * (1 - 0.35 * f.depth)
            let water: SIMD3<Float> = SIMD3<Float>(0.12, 0.3, 0.4) * (0.5 + 0.5 * light)
            c = mix(c, water, t: f.depth * 0.55)
            if time < f.awakeUntil { len *= 1 + 0.16 * sinf(Float(1 - (f.awakeUntil - time) / 1.8) * .pi) }
            // the octopus moves by jets: its body squeezes and stretches in pulses, more the faster it goes
            var squeeze: Float = 1
            if octopus {
                let pace = min(1, l / 80), pulse = max(0, sinf(f.tail * 0.35))
                squeeze = 1 - 0.14 * pace * pulse
                len *= 1 + 0.09 * pace * pulse
            }
            // the eye: from world to the fish's own axes (rotated by theta, mirrored when it faces left)
            var lookTo: SIMD2<Float> = .zero
            if let cur = cursor, time - cursorAt < 4, simd_distance(cur, f.pos) < 320 { lookTo = simd_normalize(cur - f.pos + [0.01, 0]) }
            else if let fd = particles.lazy.filter({ $0.kind == 3 && simd_distance($0.pos, f.pos) < 320 }).first { lookTo = simd_normalize(fd.pos - f.pos + [0.01, 0]) }
            f.look += (lookTo - f.look) * min(1, frameDt * 5)
            let ct = cosf(theta), st = sinf(theta)
            var lookLocal: SIMD2<Float> = [f.look.x * ct + f.look.y * st, -f.look.x * st + f.look.y * ct]
            if f.facingX < 0 { lookLocal.y = -lookLocal.y }
            let blur = f.decor ? min(1, f.depth * 1.2) : max(0, (f.depth - 0.15) * 2.2)
            out.append(Sprite(pos: f.pos, dir: [cosf(theta), sinf(theta)], size: len, kind: 0,
                              glow: glow, phase: f.tail, color: SIMD4(c, alpha),
                              extra: [(f.facingX >= 0 ? max(abs(f.facingX), 0.12) : -max(abs(f.facingX), 0.12)) * squeeze,
                                      // (the nautilus, a leader: how many of its school are at work, lit on its shell)
                                      f.kindID == "nautilus" ? Float(min(6, school(of: f).filter { [.busy, .born, .waiting].contains($0.state) }.count))
                                                             : Float(f.pattern + f.cut * 8),
                                      Float(f.species), min(0.99, f.fat) + (asleep ? 2 : 0)],
                              aux: [lookLocal.x, lookLocal.y, blur, aging(f)]))
        }
        return out
    }

    /// Mail seahorses, the fogged glass, music notes, rings and sparkles.
    private func onTheGlass() -> [Sprite] {
        var out: [Sprite] = []
        // mail seahorses (facing the way they're going)
        for c in mails {
            let looks: Float = c.stage == 2 ? c.side : -c.side
            out.append(Sprite(pos: c.pos, dir: [looks >= 0 ? 1 : -1, 0], size: 20, kind: 13, glow: 0.2, phase: c.phase,
                              color: SIMD4(mix(c.color, [1, 0.85, 0.5], t: 0.5), 1), extra: [looks >= 0 ? 1 : -1, c.letter ? 1 : 0, 0, 0]))
        }

        // glass fogging up in front of whoever has been waiting more than 3 min
        for f in fish where f.state == .waiting && !f.leaving && !f.decor && time - f.since > 180 * Self.scale {
            let t = Float(time - f.since - 180 * Self.scale) / Float(Self.scale)
            out.append(Sprite(pos: f.pos + [0, -4], dir: [1, 0], size: f.size * (1.4 + min(1.4, t / 120)), kind: 11,
                              glow: min(1, t / 40), phase: Float(f.phase), color: [0.85, 0.9, 0.95, 1], extra: [1, 0, 0, 0]))
        }

        for p in particles where p.kind == 24 {
            let k = min(1, p.life / 0.4) * (1 - p.life / p.maxLife)
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: 24, glow: k, phase: 0, color: p.color, extra: [1, 0, 0, 0]))
        }
        // rings on the surface (bubbles popping)
        for p in particles where p.kind == 8 {
            let k = 1 - p.life / p.maxLife
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: 8, glow: k * 0.8, phase: 0, color: p.color, extra: [1, 0, 0, 0]))
        }
        for p in particles where p.kind == 2 || p.kind == 4 {
            let k = 1 - p.life / p.maxLife
            out.append(Sprite(pos: p.pos, dir: [1, 0], size: p.size, kind: p.kind, glow: k, phase: 0,
                              color: p.color, extra: [1, 0, 0, 0]))
        }
        return out
    }

    /// The dark seaweed tufts in the corners and the theme's frost, over everything.
    private func upFront() -> [Sprite] {
        var out: [Sprite] = []
        // foreground: dark, blurred seaweed tufts in the corners, moving more with the parallax (the theme may leave them
        // out, "foreground": false, or tint them)
        if let fg = Themes.current.foreground {
            let shift = gaze * -14
            let tuft = size.y * 0.32
            out.append(Sprite(pos: [size.x * 0.03 + shift.x, tuft * 0.62 + shift.y * 0.3], dir: [1, 0], size: tuft, kind: 20, glow: 0.92,
                              phase: Float(time), color: SIMD4(fg * (0.6 + 0.4 * light), 1), extra: [1, 0, 0, 0]))
            out.append(Sprite(pos: [size.x * 0.97 + shift.x, tuft * 0.5 + shift.y * 0.3], dir: [1, 0], size: tuft * 0.85, kind: 20, glow: 0.92,
                              phase: Float(time) + 3, color: SIMD4(fg * 1.1 * (0.6 + 0.4 * light), 1), extra: [1, 0, 0, 0]))
        }

        // frost on the glass, over everything (a theme's "frost")
        let frost = Themes.current.frost
        if frost > 0.01 {
            let aspect = size.x / max(1, size.y)
            out.append(Sprite(pos: size * 0.5, dir: [1, 0], size: size.y * 0.5, kind: 38, glow: frost, phase: 0,
                              color: [1, 1, 1, 1], extra: [1, aspect, 0, 0], aux: [aspect, 1, 0, 0]))
        }
        return out
    }

    /// The built-in creatures dressed by the theme ("looks": {"starfish": "<a pack creature>", "lanternfish": "<a pack
    /// fish>", "jellyfish": "<a pack creature or presence>"}): they move as always, drawn by the pack.
    private static let creatureSprites: [Float: String] = [14: "crab", 15: "turtle", 16: "snail", 17: "starfish", 19: "whale", 5: "jellyfish"]
    func dressFauna(_ sprites: [Sprite]) -> [Sprite] {
        let looks = Themes.current.looks
        guard FishKinds.dressByTheme, !looks.isEmpty else { return sprites }
        let lantern = Float(FishKinds.index(of: "lanternfish"))
        let lit = 0.45 + 0.55 * light
        return sprites.map { s in
            var s = s
            // the lanternfish (a fish kind): another fish's drawing
            if s.kind == 0, s.extra.z == lantern, let look = looks["lanternfish"], FishKinds.all.contains(where: { $0.id == look }) {
                s.extra.z = Float(FishKinds.index(of: look))
                return s
            }
            guard let id = Self.creatureSprites[s.kind], let look = looks[id] else { return s }
            if let i = FaunaKinds.all.firstIndex(where: { $0.id == look }) {
                let k = FaunaKinds.all[i]
                var pos = s.pos
                // on the sand: its feet (c.y = -0.9) on the sand, as the pack's own creatures
                if id == "crab" || id == "starfish" { pos.y = size.y * sand(pos.x / max(1, size.x)) + s.size * k.extent.y * 0.9 }
                let face: Float = s.extra.x < 0 || s.dir.x < 0 ? -1 : 1
                return Sprite(pos: pos, dir: [face, 0], size: s.size, kind: 36, glow: 0, phase: s.phase,
                              color: SIMD4(k.color * lit, s.color.w), extra: [face, 0.5, Float(i), 1], aux: [k.extent.x, k.extent.y, 0, 0])
            }
            if let p = Scene.kinds[look], let i = p.pack, i < PackPresences.all.count {
                return Sprite(pos: s.pos, dir: [1, 0], size: p.size, kind: 37, glow: s.glow, phase: s.phase,
                              color: SIMD4(p.color * lit, s.color.w), extra: [1, 1, Float(i), 3], aux: [p.extent.x, p.extent.y, 0, 0])
            }
            return s
        }
    }

    /// A session's age (0…1 over six hours) plus 2 × its project's veteran level, for the shader (aux.w).
    private func aging(_ f: Fish) -> Float {
        guard f.isAgent && !f.decor else { return 0 }
        let age = min(0.999, Float((time - f.bornAt) / (6 * 3600 * Self.scale)))
        return age + Float(f.veteran) * 2
    }

    /// A soft shadow on the sand under something swimming: darker and smaller the closer it is to the bottom.
    private func shadow(under p: SIMD2<Float>, size s: Float, strength: Float) -> Sprite? {
        let sy = size.y * sand(p.x / max(1, size.x)) + 2
        let t = max(0, min(1, (p.y - sy) / (size.y * 0.55)))
        let a = (1 - t) * (1 - t) * 0.5 * strength * (0.45 + 0.55 * light)
        guard a > 0.01 else { return nil }
        return Sprite(pos: [p.x, sy], dir: [1, 0], size: s * (1.0 + t * 1.6), kind: 32, glow: a, phase: 0,
                      color: [0, 0, 0, 1], extra: [1, 0, 0, 0])
    }
}
