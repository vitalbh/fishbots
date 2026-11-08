import Foundation

/// What a fish does when its agent uses a tool: the animation, the text on its label and the note's timbre.
/// Providers can register their own (first match wins; registered ones come before the built-ins). See docs/extensions.md.
struct ToolBehavior {
    enum Animation { case none, nibble, bubbles, forage, peek }

    /// Tool names; "*" at the end matches a prefix ("mcp__*").
    let tools: [String]
    var animation: Animation = .none
    /// The text shown on the label for a few seconds.
    var label: (String) -> String
    var timbre: Timbre = .pluck

    func matches(_ tool: String) -> Bool {
        tools.contains { $0.hasSuffix("*") ? tool.hasPrefix($0.dropLast()) : $0 == tool }
    }
}

enum ToolBehaviors {
    private static var registered: [ToolBehavior] = []

    private static let builtIns: [ToolBehavior] = [
        ToolBehavior(tools: ["mcp__*"], label: { "✉︎ mcp · " + ($0.components(separatedBy: "__").dropFirst().first ?? "") }),
        // Edit/Write: nibbles the seaweed
        ToolBehavior(tools: ["Edit", "Write", "MultiEdit", "NotebookEdit"], animation: .nibble, label: { "✏️ " + $0 }, timbre: .bell),
        // Bash: a puff of bubbles
        ToolBehavior(tools: ["Bash"], animation: .bubbles, label: { _ in "⌨︎ Bash" }),
        // Read/Grep/Glob: forages in the sand
        ToolBehavior(tools: ["Read", "Grep", "Glob", "LS"], animation: .forage, label: { "🔍 " + $0 }, timbre: .bubble),
        // WebFetch/WebSearch: peeks at the surface
        ToolBehavior(tools: ["WebFetch", "WebSearch"], animation: .peek, label: { "🌐 " + $0 }, timbre: .bell),
        ToolBehavior(tools: ["Task", "Agent"], label: { _ in tr("🐟 subagente") }, timbre: .bass),
        ToolBehavior(tools: ["TodoWrite"], label: { _ in tr("☑︎ lista") }),
        ToolBehavior(tools: ["Skill"], label: { _ in "✨ skill" }),
    ]

    private static let fallback = ToolBehavior(tools: ["*"], label: { "🔧 " + $0 })

    static func register(_ b: ToolBehavior) { registered.insert(b, at: 0) }

    static func of(_ tool: String) -> ToolBehavior {
        registered.first { $0.matches(tool) } ?? builtIns.first { $0.matches(tool) } ?? fallback
    }
}
