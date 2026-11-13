import Foundation
import simd

/// A crowded tank: from six sessions on (and until it's down to four again, so it doesn't flap), the quiet sessions
/// of one project swim as a tight ball (a shoal) under one label, each project keeps mostly to its own stretch of
/// the tank, and the visitors come by less often. Whoever needs you leaves its shoal on its own (to the glass, down
/// sick), and that leaving is the signal. The mouse near a shoal fans it out for a few seconds, each with its text.
///
/// A shoal is the project's; the V of a session that launched others (Schools.swift) is something else and wins:
/// a leader and its school are never in a shoal.
final class Crowding {
    /// Shoals and homes on from this many agent sessions; off again at `offAt` or fewer.
    static let onAt = 6, offAt = 4

    private(set) var on = false
    /// Per project (`projectKey`): its quiet sessions, oldest first; the first one leads. Only projects with two or more.
    private(set) var shoals: [String: [Fish]] = [:]
    /// Per project: its home stretch along the tank, as fractions of the width (in the order the projects came,
    /// as wide as their share of the sessions).
    private(set) var homes: [String: ClosedRange<Float>] = [:]
    private var fannedUntil: [String: Double] = [:]

    func update(_ t: Tank) {
        // (in the small tank, only the ones shown: it holds a few, and the hidden ones mustn't lead a shoal)
        let agents = t.fish.filter { $0.isAgent && !$0.decor && !$0.leaving && !t.isHidden($0) }
        if agents.count >= Self.onAt { on = true } else if agents.count <= Self.offAt { on = false }
        shoals = [:]
        homes = [:]
        guard on else { fannedUntil = [:]; return }
        let byProject = Dictionary(grouping: agents, by: \.projectKey)
        let first = byProject.mapValues { $0.map(\.bornAt).min() ?? 0 }
        let order = byProject.keys.sorted { (first[$0]!, $0) < (first[$1]!, $1) }
        var x: Float = 0.06
        for k in order {
            let share = 0.88 * Float(byProject[k]!.count) / Float(agents.count)
            homes[k] = x...(x + share)
            x += share
        }
        for (k, fs) in byProject {
            let calm = fs.filter { isQuiet($0, t) }.sorted { $0.bornAt < $1.bornAt }
            if calm.count >= 2 { shoals[k] = calm }
        }
        if let c = t.cursor, t.time - t.cursorAt < 2 {
            for (k, mates) in shoals where mates.contains(where: { simd_distance($0.pos, c) < $0.size * 2.5 + 30 }) {
                fannedUntil[k] = t.time + 3
            }
        }
        fannedUntil = fannedUntil.filter { $0.value > t.time }
    }

    /// Quiet: at work or resting, not needing you, awake, and in no launch school.
    private func isQuiet(_ f: Fish, _ t: Tank) -> Bool {
        f.leaderID == nil && !f.leading && [.busy, .idle, .ok, .done, .born].contains(f.state) && !t.sleeping(f)
    }

    /// Spread out because the mouse came near it.
    func fanned(_ projectKey: String) -> Bool { fannedUntil[projectKey] != nil }

    enum Role { case lead(count: Int, working: Int), member }

    /// What this fish is in its shoal, for its label; nil: in none, or its shoal is fanned out (everyone speaks).
    func role(_ f: Fish) -> Role? {
        guard let mates = shoals[f.projectKey], !fanned(f.projectKey), let i = mates.firstIndex(where: { $0 === f }) else { return nil }
        guard i == 0 else { return .member }
        return .lead(count: mates.count, working: mates.filter { $0.state == .busy || $0.state == .born }.count)
    }
}

extension Tank {
    /// A quiet session in its project's shoal: the oldest leads and the others keep a place in a loose ball around
    /// it (a sunflower spiral, turning slowly); fanned out, the ball opens wide. The leader goes where it would along
    /// the tank, but up in the open water (a resting fish keeps low, and a ball down there gets squashed on the
    /// sand). nil: it's in no shoal, or it's off doing something (nibbling, foraging) and comes back after.
    func shoaled(_ f: Fish, target: SIMD2<Float>, speed: Float, scale: Float) -> Heading? {
        guard let mates = crowding.shoals[f.projectKey], let i = mates.firstIndex(where: { $0 === f }),
              f.action == nil else { return nil }
        if i == 0 {
            // a long winding round over its home stretch and a little into the neighbours', up and down most of
            // the water: brisk while any of them works, easy when they all rest
            let working = mates.contains { $0.state == .busy || $0.state == .born }
            let home = crowding.homes[f.projectKey] ?? 0.1...0.9
            let cx = (home.lowerBound + home.upperBound) / 2
            let ax = max((home.upperBound - home.lowerBound) * 0.8, 0.2)
            let t = Float(time) * (working ? 0.13 : 0.08) + Float(f.phase) * 1.7
            let x = cx + ax * (0.8 * sinf(t) + 0.2 * sinf(t * 2.3 + 1))
            let y = 0.55 + 0.22 * sinf(t * 1.37 + 0.8) + 0.05 * cosf(t * 3.1)
            // (off the side glass by more than the ball's width, so the ones around it don't press against it)
            return Heading(target: [size.x * max(0.12, min(0.88, x)), size.y * y], speed: working ? 95 : 60, scale: scale)
        }
        let lead = mates[0]
        let open: Float = crowding.fanned(f.projectKey) ? 2.6 : 1
        let a = Float(i) * 2.39996 + Float(time) * 0.28
        let r = (drawn(lead) * 0.95 + 10 * pace) * sqrtf(Float(i)) * open * (1 + 0.25 * sinf(Float(time) * 0.6 + Float(i)))
        let sway = SIMD2(cosf(Float(time) * 0.9 + Float(f.phase)), sinf(Float(time) * 1.2 + Float(f.phase))) * 14 * pace
        var place = lead.pos + SIMD2(cosf(a), sinf(a) * 0.7) * r + sway
        place.y = max(size.y * 0.25, min(size.y * 0.9, place.y))
        place.x = max(size.x * 0.06, min(size.x * 0.94, place.x))
        let away = simd_distance(f.pos, place)
        return Heading(target: place, speed: min(170, 25 + away * 1.3), scale: min(scale, 0.9))
    }

    /// Where a fish picks its next wandering spot along the tank: while the tank is crowded, mostly in its project's
    /// home stretch (three times in four), so each project is found where it usually is; otherwise anywhere.
    func wanderX(_ f: Fish) -> Float {
        if let home = crowding.homes[f.projectKey], Float.random(in: 0...1) < 0.75 {
            return Float.random(in: size.x * home.lowerBound...size.x * home.upperBound)
        }
        return Float.random(in: size.x * 0.08...size.x * 0.92)
    }

    /// How much longer the visitors (turtle, whale, grouper…) wait before coming back: 1 in a calm tank, up to 2.5
    /// with ten sessions or more, so the scenery doesn't add to the crowd.
    var visitGap: Double { 1 + 1.5 * Double(crowd) }
}
