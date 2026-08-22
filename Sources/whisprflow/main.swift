import AppKit
import AVFoundation
import ApplicationServices
import DictationKit

/// Real permission probes for the menu-bar agent. The decisions about what's missing and
/// what to say live in the tested `PermissionsPresentation`; this just reads system state.
@MainActor
final class SystemPermissions {
    var microphone: AuthStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    var accessibilityGranted: Bool { AXIsProcessTrusted() }

    func state() -> PermissionsState {
        PermissionsState(microphone: microphone, accessibilityGranted: accessibilityGranted)
    }

    /// Show the one-time system microphone prompt (no-op if already decided).
    func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }
}

// The menu-bar agent. Assembles the real adapters (mic capture, local whisper, pasteboard
// injection, the activation hotkey) into the DictationController, so holding the activation
// key, speaking, and releasing pastes text at the cursor in any app. The icon reflects
// state, subtle start/stop sounds play on the transitions, and the menu configures the
// activation key, mode, and clipboard-restore — all persisted across restarts.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A push-to-talk key event, funnelled through one ordered stream (below) so a fast
    /// tap can never deliver `ended` before `began`.
    private enum Activation { case began, ended }

    private let brand = "whisprflow"
    private var statusItem: NSStatusItem?
    private var statusLineItem: NSMenuItem?

    // Config menu items, kept so their checkmarks can be refreshed after a change.
    private var keyItems: [NSMenuItem] = []
    private var modeItems: [NSMenuItem] = []
    private var restoreItem: NSMenuItem?

    // Kept alive for the process lifetime: the controller drives the loop, the hotkey feeds
    // it activations, the continuation carries key events, and the sounds are reused.
    private var controller: DictationController?
    private var hotkey: CGEventTapHotkeySource?
    private var activations: AsyncStream<Activation>.Continuation?
    private var presenter = MenuBarPresenter()
    private let startSound = NSSound(named: "Tink")
    private let stopSound = NSSound(named: "Pop")

    private let settingsStore = SettingsStore()
    private var settings = Settings()
    private let permissions = SystemPermissions()

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = settingsStore.load()  // sync + fast; ready before assembly builds anything

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(MenuBarPresentation.symbolName(for: .idle))

        let menu = NSMenu()
        let statusLine = NSMenuItem(title: "\(brand) — starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        buildConfigItems(into: menu)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit whisprflow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu

        statusItem = item
        statusLineItem = statusLine
        refreshChecks()

        // Off the launch path: run the first-run permission flow, then assemble (which
        // downloads the ~547MB model on first run).
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        // Show the system mic prompt once if the user hasn't decided yet.
        if PermissionsPresentation.shouldRequestMicrophone(permissions.state()) {
            _ = await permissions.requestMicrophone()
        }
        let state = permissions.state()
        if !PermissionsPresentation.isReady(state) {
            if let summary = PermissionsPresentation.summary(state) { setStatus(summary) }
            presentFirstRun(state)
        }
        await assemble()
    }

    /// A minimal first-run window explaining the missing permissions, with a deep-link
    /// button per one straight to its System Settings pane.
    private func presentFirstRun(_ state: PermissionsState) {
        let missing = PermissionsPresentation.missing(state)
        let alert = NSAlert()
        alert.messageText = "Enable whisprflow"
        alert.informativeText = missing
            .map { PermissionsPresentation.instruction(for: $0) }
            .joined(separator: "\n\n")
        for permission in missing {
            alert.addButton(withTitle: "Open \(permission.displayName) Settings")
        }
        alert.addButton(withTitle: "Continue")

        NSApp.activate(ignoringOtherApps: true)
        // Buttons are added in `missing` order, then Continue; map the response back.
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if missing.indices.contains(index) {
            openSettings(for: missing[index])
        }
    }

    private func openSettings(for permission: Permission) {
        let pane = permission == .microphone ? "Privacy_Microphone" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func assemble() async {
        let engine: LocalWhisperEngine
        do {
            engine = try await LocalWhisperEngine.resident()
        } catch {
            setStatus("model unavailable — \(error)")
            return
        }

        let audio = AVAudioEngineAudioSource()
        try? audio.prewarm()  // hold the mic hot so the first key-down doesn't clip the first word
        let controller = DictationController(
            audio: audio,
            engine: engine,
            injector: PasteboardTextInjector(),
            settings: settings
        )
        controller.onStateChange = { [weak self] state in self?.render(state) }
        controller.onOutcome = { [weak self] outcome in self?.report(outcome) }
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

        armHotkey()
    }

    /// Start (or restart) the hotkey for the current activation key, rewiring it to the
    /// activation stream. Called at assembly and whenever the key setting changes.
    private func armHotkey() {
        hotkey?.stop()
        let hotkey = CGEventTapHotkeySource(key: settings.activationKey)
        hotkey.onActivationBegan = { [weak self] in self?.activations?.yield(.began) }
        hotkey.onActivationEnded = { [weak self] in self?.activations?.yield(.ended) }
        do {
            try hotkey.start()
        } catch {
            self.hotkey = nil
            setStatus("hold-to-talk off — grant Accessibility, then relaunch")
            return
        }
        self.hotkey = hotkey
        setStatus("ready — hold \(settings.activationKey.displayName) to dictate")
    }

    // MARK: - Config menu

    private func buildConfigItems(into menu: NSMenu) {
        let keyMenu = NSMenu()
        for choice in ModifierKey.choices {
            let item = NSMenuItem(title: choice.name, action: #selector(selectActivationKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.key  // the value itself, not an index into choices
            keyMenu.addItem(item)
            keyItems.append(item)
        }
        let keyParent = NSMenuItem(title: "Activation Key", action: nil, keyEquivalent: "")
        keyParent.submenu = keyMenu
        menu.addItem(keyParent)

        let modeMenu = NSMenu()
        let modes: [(String, Settings.Mode)] = [("Push-to-Talk (hold)", .pushToTalk), ("Toggle (tap)", .toggle)]
        for (title, mode) in modes {
            let item = NSMenuItem(title: title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode
            modeMenu.addItem(item)
            modeItems.append(item)
        }
        let modeParent = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        modeParent.submenu = modeMenu
        menu.addItem(modeParent)

        let restore = NSMenuItem(title: "Restore clipboard after paste", action: #selector(toggleRestore), keyEquivalent: "")
        restore.target = self
        menu.addItem(restore)
        restoreItem = restore
    }

    private func refreshChecks() {
        for item in keyItems {
            item.state = (item.representedObject as? ModifierKey == settings.activationKey) ? .on : .off
        }
        for item in modeItems {
            item.state = (item.representedObject as? Settings.Mode == settings.mode) ? .on : .off
        }
        restoreItem?.state = settings.restoreClipboard ? .on : .off
    }

    @objc private func selectActivationKey(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? ModifierKey else { return }
        settings.activationKey = key
        persist()
        armHotkey()  // re-tap on the newly chosen key
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? Settings.Mode else { return }
        settings.mode = mode
        persist()
    }

    @objc private func toggleRestore() {
        settings.restoreClipboard.toggle()
        persist()
    }

    /// Save the change and keep every consumer of `settings` in sync: the controller reads
    /// mode and restore-clipboard live, so it must never hold a stale copy.
    private func persist() {
        settingsStore.save(settings)
        controller?.settings = settings
        refreshChecks()
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

    /// Turn each dictation result into a status-line message. A failure most often means a
    /// permission went missing at use time (e.g. mic denied), so name what's still needed.
    private func report(_ outcome: DictationController.Outcome) {
        switch outcome {
        case .injected:
            setStatus("ready — hold \(settings.activationKey.displayName) to dictate")
        case .noAudio:
            setStatus("no speech detected — try again")
        case .failed(let reason):
            // A missing permission is the usual cause; name it. Otherwise keep the reason.
            setStatus(PermissionsPresentation.summary(permissions.state()) ?? "dictation failed — \(reason)")
        case .idle:
            break
        }
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
