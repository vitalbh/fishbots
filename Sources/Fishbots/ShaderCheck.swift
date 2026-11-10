import Foundation
import Metal

/// `Fishbots --check-shaders [--offline]`: compiles the app's own shader (no packs) without opening the aquarium,
/// and points each error at the section it's in. `swift build` can't tell: the shader is text until the app opens.
enum ShaderCheck {
    static func run(offline: Bool) -> Int32 {
        let full = FishKinds.shaderSource()
        let device = offline ? nil : MTLCreateSystemDefaultDevice()
        if device == nil && !offline { print("  (no Metal device here: compiling with xcrun metal)") }
        do {
            if let device { _ = try device.makeLibrary(source: full, options: nil) } else { try PackPreview.compileOffline(full) }
            print("✓ the shader compiles (\(shaderSections.count) sections, \(full.components(separatedBy: "\n").count) lines)")
            return 0
        } catch {
            print("✗ the shader doesn't compile:")
            let lines = full.components(separatedBy: "\n")
            var seen = Set<String>()
            for line in "\(error)".components(separatedBy: "\n") where line.contains("error:") {
                // …program_source:LINE:COL: error: …
                var msg = line
                if let r = line.range(of: "program_source:") {
                    let parts = line[r.upperBound...].components(separatedBy: ":")
                    if parts.count > 2, let n = Int(parts[0]) {
                        let code = n >= 1 && n <= lines.count ? lines[n - 1].trimmingCharacters(in: .whitespaces) : ""
                        msg = "\(place(ofLine: n, in: full)):" + parts[2...].joined(separator: ":") + (code.isEmpty ? "" : "\n        \(code)")
                    }
                }
                if seen.insert(msg).inserted { print("    " + msg) }
            }
            return 1
        }
    }

    /// Where a line of the full shader comes from: a section and the line within its text, or the generated part
    /// (the fish kinds and the dispatches, put in at "@fish-kinds").
    static func place(ofLine n: Int, in full: String) -> String {
        let base = shaderBase.components(separatedBy: "\n")
        let total = full.components(separatedBy: "\n").count
        guard let marker = base.firstIndex(of: "// @fish-kinds") else { return "line \(n)" }
        let before = total - base.count                      // what shaderSource puts ahead, plus what the marker grew by
        let generated = before - prefixLines + 1             // lines the marker became
        var inBase = n - prefixLines                         // 1-based line of the base text
        if inBase > marker {
            if inBase <= marker + generated { return "the fish kinds (FishKinds.swift), generated line \(inBase - marker)" }
            inBase -= generated - 1
        }
        var first = 1
        for s in shaderSections {
            let count = s.text.components(separatedBy: "\n").count
            if inBase < first + count { return "\(s.file) (\(s.name)), line \(inBase - first + 1) of its text" }
            first += count
        }
        return "line \(n)"
    }

    /// The #define lines shaderSource puts ahead of the base text.
    private static let prefixLines = 2
}
