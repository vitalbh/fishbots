# Working in this repository

New behavior goes through the existing extension points (docs/extensions.md, docs/scene.md): providers, themes,
fauna, visualizers, tool behaviors, packs. Don't add it inline to Tank, AppDelegate or the shader files.

If a feature doesn't fit an extension point and building it cleanly needs a refactor bigger than the feature
itself, stop before writing it and say so: what you'd refactor, why, and the bolt-on alternative.

The shaders are text until the app opens, so `swift build` passing says nothing about them: after touching a
`Shader*.swift` file, run `.build/release/Fishbots --check-shaders`.

The screen saver and the iPhone app build the engine from the list in scripts/engine-files.txt: a new file the engine needs goes there too.
