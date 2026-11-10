// Shaders as text, compiled when the app opens (so the project builds with just `swift build`).
// The fish kinds (FishKinds.swift) are inserted at "@fish-kinds"; compile `FishKinds.shaderSource()`, not this.
// The text is in sections, one file each; their order here is the order Metal reads them in (a function has to
// come before whoever calls it).
let shaderBase = [
    shaderCommon,
    shaderBackground,
    shaderSpriteVertex,
    shaderCreatures,
    shaderScenery,
    shaderPresences,
    shaderSpriteFragment,
    shaderPost,
].joined(separator: "\n")
