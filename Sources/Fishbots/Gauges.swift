import Foundation
import QuartzCore

/// The numbers plugins keep sending (0…1), by "source:name": disk, battery, cpu, rain, waves…
final class Gauges {
    private(set) var values: [String: Float] = [:]
    /// When each one was last sent: one silent for over an hour goes away (a plugin that stopped).
    private var sentAt: [String: Double] = [:]
    static let lifetime: Double = 3600

    private static func key(_ source: String, _ name: String) -> String { "\(source):\(name)" }

    subscript(key: String) -> Float? { values[key] }

    func set(source: String, name: String, value: Float) {
        let key = Self.key(source, name)
        values[key] = max(0, min(1, value))
        sentAt[key] = CACurrentMediaTime()
    }

    func remove(source: String, name: String) {
        let key = Self.key(source, name)
        values[key] = nil
        sentAt[key] = nil
    }

    func expire() {
        let now = CACurrentMediaTime()
        for (k, at) in sentAt where now - at > Self.lifetime { values[k] = nil; sentAt[k] = nil }
    }

    /// The highest value among gauges with this name, from any source ("weather:rain"): a scene control
    /// (docs/scene.md), or the fullest disk.
    func highest(_ name: String) -> Float? {
        values.filter { $0.key.hasSuffix(":" + name) }.map(\.value).max()
    }
}
