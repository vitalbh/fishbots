import Foundation
import simd

/// A finished task, left on the sand for the day.
struct Pearl: Codable {
    var u: Float
    var color: [Float]
    var title: String
    var project: String
    var hour: Double
}

/// Pearls of the day: each finished task leaves one on the bottom (they vanish when the day changes).
/// They're a timeline on the sand: from the left (the first one, or 8:00) to the right (now), sliding left
/// slowly as the day goes on. Pearls close in time pile up a little.
final class Pearls {
    private(set) var all: [Pearl] = []
    /// Saved between runs (the screen saver doesn't save).
    var keep = true
    private var day = ""
    /// When each one last lit up: the new-pearl glow (this run only).
    private var litAt: [Double] = []
    /// Where each one sits on the sand, from the last `layout`.
    private var places: [SIMD2<Float>] = []

    private static let key = "pearls"
    private static func today() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }

    init() {
        day = Self.today()
        guard let d = UserDefaults.standard.data(forKey: Self.key),
              let saved = try? JSONDecoder().decode([String: [Pearl]].self, from: d) else { return }
        all = saved[day] ?? []
        litAt = all.map { _ in 0 }
    }

    private func save() {
        guard keep, let d = try? JSONEncoder().encode([day: all]) else { return }
        UserDefaults.standard.set(d, forKey: Self.key)
    }

    /// A new day starts with clean sand.
    func rollDay() {
        guard Self.today() != day else { return }
        all = []; litAt = []; places = []; day = Self.today()
    }

    func add(color: SIMD3<Float>, title: String, project: String, in t: Tank) {
        rollDay()
        guard all.count < 80 else { return }
        // scattered over the sand, away from the battery and the bubbler
        var u = Float.random(in: 0.16...0.74)
        for _ in 0..<8 where all.contains(where: { abs($0.u - u) < 0.012 }) { u = Float.random(in: 0.16...0.74) }
        all.append(Pearl(u: u, color: [color.x, color.y, color.z], title: title, project: project, hour: Date().timeIntervalSince1970))
        litAt.append(t.time)
        save()
        layout(t)
    }

    /// The ones of a period, by index (to light them up one after another).
    func indices(since: Date, until: Date) -> [Int] {
        all.indices.filter { all[$0].hour >= since.timeIntervalSince1970 && all[$0].hour <= until.timeIntervalSince1970 }
    }

    /// Lights one up again; nil if it's gone meanwhile.
    func light(_ i: Int, now: Double) -> SIMD2<Float>? {
        guard i < litAt.count, i < places.count else { return nil }
        litAt[i] = now
        return places[i]
    }

    /// How new it looks (1 just lit … 0).
    func glow(_ i: Int, now: Double) -> Float {
        i < litAt.count && litAt[i] > 0 ? max(0, 1 - Float(now - litAt[i]) / 3) : 0
    }

    func pos(_ i: Int) -> SIMD2<Float> { i < places.count ? places[i] : .zero }

    func pos(_ p: Pearl) -> SIMD2<Float> {
        all.firstIndex { $0.hour == p.hour && $0.title == p.title }.map(pos) ?? .zero
    }

    /// The pearl under the point (to show its title).
    func at(_ q: SIMD2<Float>) -> Pearl? {
        places.indices.min { simd_distance(places[$0], q) < simd_distance(places[$1], q) }
            .flatMap { simd_distance(places[$0], q) < 12 && $0 < all.count ? all[$0] : nil }
    }

    func layout(_ t: Tank) {
        let now = Date().timeIntervalSince1970
        let eight = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())?.timeIntervalSince1970 ?? now - 4 * 3600
        let t0 = min(all.map(\.hour).min() ?? eight, eight)
        let t1 = max(now, t0 + 4 * 3600)
        var out = [SIMD2<Float>](repeating: .zero, count: all.count)
        // pearls close in time gather in a little heap (the first ones at the bottom), clear of the rocks and the chest
        var heaps: [(x: Float, members: [Int])] = []
        var lastX: Float = -100
        for i in all.indices.sorted(by: { all[$0].hour < all[$1].hour }) {
            let x = t.size.x * (0.06 + 0.88 * Float((all[i].hour - t0) / (t1 - t0)))
            if x - lastX < 9, !heaps.isEmpty { heaps[heaps.count - 1].members.append(i) } else { heaps.append((x, [i])) }
            lastX = x
        }
        let gap: Float = 8
        for h in heaps {
            var b = 1
            while b * (b + 1) / 2 < h.members.count { b += 1 }      // the bottom row of a heap that holds them all
            let x0 = t.clearOfScenery(h.x + Float(b - 1) * gap / 2) - Float(b - 1) * gap / 2
            var k = 0
            for row in 0..<b {
                for col in 0..<(b - row) where k < h.members.count {
                    let x = x0 + (Float(col) + Float(row) * 0.5) * gap
                    out[h.members[k]] = [x, t.size.y * t.sand(x / max(1, t.size.x)) + 4 + Float(row) * gap * 0.8]
                    k += 1
                }
            }
        }
        places = out
    }
}
