import Foundation

/// Environment settings: FISHBOTS_<NAME>, or AQUARIO_<NAME> (the app's old name).
enum Env {
    static func value(_ name: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        return env["FISHBOTS_" + name] ?? env["AQUARIO_" + name]
    }
}

extension UserDefaults {
    /// A switch that's on until it's turned off. Read with `bool(forKey:)`, not `as? Bool`: a launch argument
    /// (`-nowPlaying NO`) arrives as the string "NO", which `as? Bool` misses, and the switch would stay on.
    func flag(_ key: String, default on: Bool = true) -> Bool { object(forKey: key) == nil ? on : bool(forKey: key) }
}
