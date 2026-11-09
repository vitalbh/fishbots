# Working in this repository

New behavior goes through the existing extension points (docs/extensions.md, docs/scene.md): providers, themes,
fauna, visualizers, tool behaviors, packs. Don't add it inline to Tank, AppDelegate or Shaders.

If a feature doesn't fit an extension point and building it cleanly needs a refactor bigger than the feature
itself, stop before writing it and say so: what you'd refactor, why, and the bolt-on alternative.

The screen saver lists its source files by name in scripts/saver.sh: a new file the engine needs goes there too.
