import AppKit

if let code = PackPreview.runIfAsked() { exit(code) }   // `--preview` / `--check` a pack, without the aquarium
Migration.run()   // before anything reads the settings
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
