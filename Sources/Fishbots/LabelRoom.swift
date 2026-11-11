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
}
