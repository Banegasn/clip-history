import AppKit

// Programmatic entry point (no storyboard). `.accessory` makes this a menu-bar
// agent: no Dock icon, no app menu, lives in the status bar only.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
