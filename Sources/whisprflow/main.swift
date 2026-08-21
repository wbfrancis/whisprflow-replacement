import AppKit
import DictationKit

// The menu-bar agent shell. Ticket #7 wires the dictation loop into this; for now
// it establishes the background-agent behavior: no dock icon, no main window, a
// status-bar icon, and a working Quit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "Dictation")
            button.image?.isTemplate = true
        }

        let menu = NSMenu()
        let title = NSMenuItem(title: "whisprflow \(DictationKit.version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit whisprflow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
// Menu-bar agent: no dock icon, no main window. (The .app-bundle equivalent is
// LSUIElement=true in Info.plist; a later packaging step adds the bundle.)
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
