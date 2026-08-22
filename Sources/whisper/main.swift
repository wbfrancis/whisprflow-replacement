import AppKit
import AVFoundation
import ApplicationServices
import DictationKit

/// Echo a lifecycle line to the terminal so behavior is visible when run via `swift run`
/// (the menu status line isn't). Prefixed for easy grepping.
func log(_ message: String) {
    FileHandle.standardError.write(Data("[whisper] \(message)\n".utf8))
}

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

    /// Ask the system to add this app to the Accessibility list. Non-blocking: it shows
    /// the standard "…would like to control this computer" dialog (with an Open System
    /// Settings button) and returns right away, so it never stalls launch the way a modal
    /// on the boot path does. No-op once granted.
    func promptAccessibility() {
        // The literal value of `kAXTrustedCheckOptionPrompt`; used directly because that
        // imported global isn't concurrency-safe to reference under Swift 6.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
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

    private let brand = "whisper"
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
    private var accessibilityRetry: Task<Void, Never>?
    private var activations: AsyncStream<Activation>.Continuation?
    private var presenter = MenuBarPresenter()
    private let startSound = NSSound(named: "Tink")
    private let stopSound = NSSound(named: "Pop")

    private let settingsStore = SettingsStore()
    private var settings = Settings()
    private let permissions = SystemPermissions()
    private let feedbackLog = FeedbackLog()

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings = settingsStore.load()  // sync + fast; ready before assembly builds anything

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item  // set before setIcon: it reads statusItem?.button, so the idle icon shows at launch
        setIcon(MenuBarPresentation.symbolName(for: .idle))

        let menu = NSMenu()
        let statusLine = NSMenuItem(title: "\(brand) — starting…", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        buildConfigItems(into: menu)
        menu.addItem(.separator())
        let addFeedback = NSMenuItem(title: "Add Feedback…", action: #selector(addFeedback), keyEquivalent: "")
        addFeedback.target = self
        menu.addItem(addFeedback)
        let openFeedback = NSMenuItem(title: "Open Feedback Log", action: #selector(openFeedbackLog), keyEquivalent: "")
        openFeedback.target = self
        menu.addItem(openFeedback)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit whisper", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu

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
        log("permissions: microphone=\(state.microphone), accessibility=\(state.accessibilityGranted)")
        // Prompt for Accessibility if it's missing — but never block boot on it. The old
        // code ran a modal here, which on a menu-bar (.accessory) app can fail to surface
        // and leave launch hung at "starting…". Instead we fire the non-blocking system
        // prompt and always assemble; armHotkey then polls until the grant lands, so the
        // hotkey starts working the moment Accessibility is enabled — no relaunch needed.
        if !state.accessibilityGranted {
            permissions.promptAccessibility()
        }
        if let summary = PermissionsPresentation.summary(state) { setStatus(summary) }
        await assemble()
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
                log("hotkey \(event)")
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
            setStatus("hold-to-talk off — enable whisper under Accessibility (starts automatically once you do)")
            scheduleAccessibilityRetry()
            return
        }
        self.hotkey = hotkey
        accessibilityRetry?.cancel()
        accessibilityRetry = nil
        setStatus("ready — hold \(settings.activationKey.displayName) to dictate")
    }

    /// Poll for the Accessibility grant, then arm the hotkey — so enabling whisper in
    /// System Settings takes effect immediately instead of needing a relaunch. Idle cost
    /// is one boolean check a second, only while the grant is still missing.
    private func scheduleAccessibilityRetry() {
        guard accessibilityRetry == nil else { return }
        accessibilityRetry = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                if self.permissions.accessibilityGranted {
                    self.armHotkey()  // arms and clears this retry
                    return
                }
            }
        }
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
        log(text)
    }

    // MARK: - Feedback log

    /// Prompt for a note and append it to the feedback log. A multi-line text view is the
    /// accessory so a longer thought fits; Enter inserts a newline, the Save button commits.
    @objc private func addFeedback() {
        let alert = NSAlert()
        alert.messageText = "Add feedback"
        alert.informativeText = "Jot a note for the next round of improvements. Saved to the feedback log."

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 96))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.autoresizingMask = [.width, .height]
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        scroll.documentView = textView
        alert.accessoryView = scroll

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = textView
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let saved = try feedbackLog.append(textView.string)
            setStatus(saved ? "feedback saved" : "ready — hold \(settings.activationKey.displayName) to dictate")
        } catch {
            setStatus("couldn't save feedback — \(error.localizedDescription)")
        }
    }

    /// Open the feedback log in the default handler, revealing it in Finder if it's empty
    /// (nothing jotted yet), so the user always lands somewhere sensible.
    @objc private func openFeedbackLog() {
        let url = feedbackLog.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
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
