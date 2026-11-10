// Shaders as text, compiled when the app opens (so the project builds with just `swift build`).
// The fish kinds (FishKinds.swift) are inserted at "@fish-kinds"; compile `FishKinds.shaderSource()`, not this.
// The text is in sections, one file each; their order here is the order Metal reads them in (a function has to
// come before whoever calls it).
let shaderSections: [(name: String, file: String, text: String)] = [
    ("shaderCommon", "ShaderCommon.swift", shaderCommon),
    ("shaderBackground", "ShaderBackground.swift", shaderBackground),
    ("shaderSpriteVertex", "ShaderSprites.swift", shaderSpriteVertex),
    ("shaderCreatures", "ShaderCreatures.swift", shaderCreatures),
    ("shaderScenery", "ShaderScenery.swift", shaderScenery),
    ("shaderPresences", "ShaderPresences.swift", shaderPresences),
    ("shaderSpriteFragment", "ShaderSprites.swift", shaderSpriteFragment),
    ("shaderPost", "ShaderPost.swift", shaderPost),
]
let shaderBase = shaderSections.map(\.text).joined(separator: "\n")
