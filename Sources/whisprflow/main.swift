import AppKit
import DictationKit

// The menu-bar agent. Assembles the real adapters (mic capture, local whisper, pasteboard
// injection, Right-Option hotkey) into the DictationController, so holding Right Option,
// speaking, and releasing pastes text at the cursor in any app. The icon reflects state
// and subtle start/stop sounds play on the transitions.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A push-to-talk key event, funnelled through one ordered stream (below) so a fast
    /// tap can never deliver `ended` before `began`.
    private enum Activation { case began, ended }

    private let brand = "whisprflow"
    private var statusItem: NSStatusItem?
    private var statusLineItem: NSMenuItem?

    // Kept alive for the process lifetime: the controller drives the loop, the hotkey feeds
    // it activations, the continuation carries key events, and the sounds are reused.
    private var controller: DictationController?
    private var hotkey: CGEventTapHotkeySource?
    private var activations: AsyncStream<Activation>.Continuation?
    private var presenter = MenuBarPresenter()
    private let startSound = NSSound(named: "Tink")
    private let stopSound = NSSound(named: "Pop")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(MenuBarPresentation.symbolName(for: .idle))

        let menu = NSMenu()
        let statusLine = NSMenuItem(title: "\(brand) — starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit whisprflow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu

        statusItem = item
        statusLineItem = statusLine

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

        // Serialize key events: the hotkey callbacks only `yield` (synchronous, ordered),
        // and this single consumer applies them one at a time, so began always precedes its
        // ended even for a fast tap.
        let (stream, continuation) = AsyncStream<Activation>.makeStream()
        self.activations = continuation
        Task {
            for await event in stream {
                switch event {
                case .began: await controller.activationBegan()
                case .ended: await controller.activationEnded()
                }
            }
        }

        let hotkey = CGEventTapHotkeySource()
        hotkey.onActivationBegan = { [weak self] in self?.activations?.yield(.began) }
        hotkey.onActivationEnded = { [weak self] in self?.activations?.yield(.ended) }
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
        let (symbol, sound) = presenter.advance(to: state)
        setIcon(symbol)
        switch sound {
        case .start: startSound?.play()
        case .stop: stopSound?.play()
        case nil: break
        }
    }

    private func setIcon(_ symbolName: String) {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Dictation")
        button.image?.isTemplate = true
    }

    private func setStatus(_ text: String) {
        statusLineItem?.title = "\(brand) — \(text)"
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
