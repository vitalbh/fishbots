import AppKit

if let code = PackPreview.runIfAsked() { exit(code) }   // `--preview` / `--check` a pack, without the aquarium
Migration.run()   // before anything reads the settings
// Opened from a shell inside Rex, the app would take that pane for its own place: every `rex` it runs would look
// only in that session, and the panes of the others wouldn't be found. The aquarium is nobody's pane.
unsetenv("REX_SESSION"); unsetenv("REX_BLOCK")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
