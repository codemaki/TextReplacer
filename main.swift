import Cocoa

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Make it an accessory app that shows in menu bar
app.setActivationPolicy(.accessory)

app.run()
