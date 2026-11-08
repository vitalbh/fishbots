import Foundation

/// Environment settings: FISHBOTS_<NAME>, or AQUARIO_<NAME> (the app's old name).
enum Env {
    static func value(_ name: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        return env["FISHBOTS_" + name] ?? env["AQUARIO_" + name]
    }
}
