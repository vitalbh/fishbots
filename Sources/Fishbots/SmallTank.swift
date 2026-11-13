import Foundation
import simd

/// The small tank (widget mode: in a corner, or hanging under the notch, 190–340 points tall). The fish swim as in the
/// big tank (Steering.swift), but its numbers were made for a window of a thousand points and more: here the
/// distances shrink with the tank, the speeds with the sprites (drawn at 75%), the free fish keep to the open water
/// (the sand and the weeds take the bottom quarter), every body stays inside the glass, the fish that are hidden don't
/// push or lead the ones shown, and only a few sessions show at once. In the big tank all of this is a no-op.
extension Tank {
    /// The share of the big tank's distances that fits: 1 in the window; in the widget, by its height (~0.35–0.6).
    var reach: Float { compact ? max(0.34, min(1, size.y / 560)) : 1 }
    /// Speeds: the sprites are drawn at 75% in the widget, so the same body lengths per second as in the window.
    var pace: Float { compact ? 0.75 : 1 }
    /// A fish's size as drawn (its `size` is the big tank's).
    func drawn(_ f: Fish) -> Float { f.size * pace }

    /// A free fish's heights (fractions of the tank) in the widget: squeezed into the open water above the weeds.
    func openWater(_ lo: Float, _ hi: Float) -> (Float, Float) {
        guard compact else { return (lo, hi) }
        let floor: Float = 0.3, top: Float = 0.84
        return (floor + lo * (top - floor), floor + hi * (top - floor))
    }

    /// Where a fish heads, kept far enough from the side glass and the surface that all of it shows.
    func keptInside(_ f: Fish, _ target: SIMD2<Float>) -> SIMD2<Float> {
        guard compact else { return target }
        let m = drawn(f) * 0.8 + 6
        return [max(m, min(size.x - m, target.x)), min(size.y - drawn(f) * 0.55 - 8, target.y)]
    }

    /// How many fish (sessions, a plugin's fish) the widget shows at once: by its area, 3 under a small notch, 4 in
    /// the corner, 6 under a medium notch, 8 at most.
    var widgetCap: Int { max(3, min(8, Int(size.x * size.y / 22_000))) }

    /// Who of those who could show does, recomputed once a frame (`isHidden` asks it): who needs you first (the one
    /// waiting longest first, as in the queue), then the session you're on, then one that came in less than 30 s ago
    /// keeps its place (so a busy tank doesn't swap fish at every tool), then the most recently heard from.
    func widgetShown(_ candidates: [Fish], latest: String?) -> Set<String> {
        let needs = candidates.filter { [.waiting, .error, .alert].contains($0.state) }.sorted { $0.since < $1.since }
        let rest = candidates.filter { ![.waiting, .error, .alert].contains($0.state) }
        let held = rest.filter { f in widgetSince[f.id].map { time - $0 < 30 } ?? false }
        let ranked = needs + rest.filter { $0.id == latest } + held.sorted { $0.seen > $1.seen } + rest.sorted { $0.seen > $1.seen }
        var shown: [String] = []
        for f in ranked where !shown.contains(f.id) && shown.count < widgetCap { shown.append(f.id) }
        let set = Set(shown)
        // when each one came in (kept while it stays)
        widgetSince = widgetSince.filter { set.contains($0.key) }
        for id in shown where widgetSince[id] == nil { widgetSince[id] = time }
        return set
    }
}
