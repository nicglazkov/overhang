import AppKit

// Top-level code is only legal in main.swift, so the entry point lives here rather than
// using @main, which would collide with NSApplication's own startup path.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar of its own
app.run()
