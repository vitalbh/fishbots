import CoreGraphics

/// Room for the texts over the water: when two would cover each other, the one that matters more keeps its place,
/// the other tries the other side of its fish (above instead of below) and, with no room there either, fades out
/// until it has room again or the mouse comes over it. Whoever needs you never gives way to whoever doesn't.
struct LabelRoom {
    struct Claim {
        let id: String
        /// Where it goes by default and, if it can move, the other place it may take.
        let home: CGRect
        let alt: CGRect?
        let priority: Float
    }

    enum Place: Equatable { case home, alt, hidden }

    /// What each text does this frame. `before` is what it did last frame: a text keeps the side it's on while it
    /// fits there, and one already showing wins a tie against one coming in, so two passing fish don't flicker.
    static func place(_ claims: [Claim], before: [String: Place]) -> [String: Place] {
        func weight(_ c: Claim) -> Float { c.priority + (before[c.id].map { $0 == .hidden ? 0 : 40 } ?? 0) }
        let order = claims.sorted { a, b in
            let wa = weight(a), wb = weight(b)
            return wa != wb ? wa > wb : a.id < b.id
        }
        var taken: [CGRect] = []
        var out: [String: Place] = [:]
        for c in order {
            func free(_ r: CGRect) -> Bool { !taken.contains { $0.intersects(r.insetBy(dx: -2, dy: -1)) } }
            var tries: [(Place, CGRect)] = [(.home, c.home)]
            if let a = c.alt { tries.append((.alt, a)) }
            if before[c.id] == .alt { tries.reverse() }
            if let (p, r) = tries.first(where: { free($0.1) }) {
                out[c.id] = p
                taken.append(r)
            } else {
                out[c.id] = .hidden
            }
        }
        return out
    }

    /// A text that stands over something on the floor (a presence's, above its flag or its wheel) moved off what
    /// stands around it: the scenery doesn't move, so the text does. It slides sideways or goes up a little, whichever
    /// is nearer, and never hides: with no clear place within reach it takes the one that covers the least. `before`
    /// is where it went last frame, kept while it's still good (a crab's text doesn't hop about as it walks).
    static func clear(_ home: CGRect, of things: [CGRect], within room: CGRect, before: CGSize? = nil) -> CGSize {
        func covered(_ r: CGRect) -> CGFloat {
            things.reduce(0) { sum, t in
                let i = t.insetBy(dx: -3, dy: -2).intersection(r)
                return sum + (i.isNull ? 0 : i.width * i.height)
            }
        }
        if covered(home) == 0 { return .zero }
        var best = CGSize.zero, bestCost = CGFloat.infinity
        let w = home.width
        for dy in stride(from: CGFloat(0), through: 84, by: 6) {
            for dx in [0, -0.2, 0.2, -0.38, 0.38, -0.55, 0.55].map({ $0 * w }) {
                let r = home.offsetBy(dx: dx, dy: dy)
                guard r.minX >= room.minX + 4, r.maxX <= room.maxX - 4, r.maxY <= room.maxY - 4 else { continue }
                // far from its owner costs; covering something costs much more; where it was is a little cheaper
                var cost = dy + abs(dx) * 0.9 + covered(r) * 4
                if let b = before, abs(b.width - dx) < 1, abs(b.height - dy) < 1 { cost -= 10 }
                if cost < bestCost { bestCost = cost; best = CGSize(width: dx, height: dy) }
            }
        }
        return best
    }
}
