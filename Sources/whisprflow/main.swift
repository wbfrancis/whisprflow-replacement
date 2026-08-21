import AppKit
import DictationKit

// The menu-bar agent. Assembles the real adapters (mic capture, local whisper, pasteboard
// injection, Right-Option hotkey) into the DictationController, so holding Right Option,
// speaking, and releasing pastes text at the cursor in any app. The icon reflects state
// and subtle start/stop sounds play on the transitions.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusTitle: NSMenuItem?

    // Kept alive for the process lifetime: the controller drives the loop, the hotkey feeds
    // it activations, and the sounds are reused instances.
    private var controller: DictationController?
    private var hotkey: CGEventTapHotkeySource?
    private var lastState: DictationController.State = .idle
    private let startSound = NSSound(named: "Tink")
    private let stopSound = NSSound(named: "Pop")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(MenuBarPresentation.symbolName(for: .idle))

        let menu = NSMenu()
        let title = NSMenuItem(title: "whisprflow — starting…", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit whisprflow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu

        statusItem = item
        statusTitle = title

        // Assembling the engine is async (it downloads the ~547MB model on first run), so
        // build everything off the launch path and wire the hotkey once it's ready.
        Task { await assemble() }
    }

    private func assemble() async {
        let engine: LocalWhisperEngine
        do {
            engine = try await LocalWhisperEngine.resident()
        } catch {
            setStatus("model unavailable — \(error)")
            return
        }

        let controller = DictationController(
            audio: AVAudioEngineAudioSource(),
            engine: engine,
            injector: PasteboardTextInjector()
        )
        controller.onStateChange = { [weak self] state in self?.render(state) }
        self.controller = controller

        // Pay the one-time model/Metal warm-up now so the first real dictation isn't slow.
        await controller.warmUp()

        let hotkey = CGEventTapHotkeySource()
        hotkey.onActivationBegan = { [weak controller] in
            Task { await controller?.activationBegan() }
        }
        hotkey.onActivationEnded = { [weak controller] in
            Task { await controller?.activationEnded() }
        }
        do {
            try hotkey.start()
        } catch {
            setStatus("hold-to-talk off — grant Accessibility, then relaunch")
            return
        }
        self.hotkey = hotkey
        setStatus("ready — hold Right Option to dictate")
    }

    // MARK: - Presentation

    private func render(_ state: DictationController.State) {
        setIcon(MenuBarPresentation.symbolName(for: state))
        switch MenuBarPresentation.sound(from: lastState, to: state) {
        case .start: startSound?.play()
        case .stop: stopSound?.play()
        case nil: break
        }
        lastState = state
    }

    private func setIcon(_ symbolName: String) {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Dictation")
        button.image?.isTemplate = true
    }

    private func setStatus(_ text: String) {
        statusTitle?.title = "whisprflow — \(text)"
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
