import Foundation

/// Orchestrates the dictation loop: hold → record → transcribe → inject. It owns the
/// state machine and runs against the four seam protocols, so all of its logic is
/// testable with fakes and it never touches the OS directly.
///
/// Isolated to the main actor: it coordinates UI feedback (menu-bar icon, sounds in
/// #7) and the pasteboard, which belong on the main thread.
@MainActor
public final class DictationController {
    public enum State: Sendable, Equatable {
        case idle
        case recording
        case transcribing
        case injecting
    }

    /// The result of the most recent activation cycle.
    public enum Outcome: Sendable, Equatable {
        case idle
        case injected(String)
        case noAudio
        case failed(String)
    }

    public private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    public private(set) var lastOutcome: Outcome = .idle

    /// Fires on every state transition. #7 uses this to drive the menu-bar icon and
    /// start/stop sounds.
    public var onStateChange: ((State) -> Void)?

    /// Fires once at the end of each activation cycle with its result. The app uses it to
    /// surface a clear message — e.g. a failure from a missing mic permission at use time.
    public var onOutcome: ((Outcome) -> Void)?

    private let audio: AudioSource
    private let engine: TranscriptionEngine
    private let injector: TextInjector
    public var settings: Settings

    public init(
        audio: AudioSource,
        engine: TranscriptionEngine,
        injector: TextInjector,
        settings: Settings = Settings()
    ) {
        self.audio = audio
        self.engine = engine
        self.injector = injector
        self.settings = settings
    }

    /// Warm up the engine once at launch so the first real dictation isn't slow.
    public func warmUp() async {
        await engine.warmUp()
    }

    /// The activation key went down (push-to-talk) or was tapped (toggle).
    public func activationBegan() async {
        switch settings.mode {
        case .pushToTalk:
            await beginRecording()
        case .toggle:
            switch state {
            case .idle: await beginRecording()
            case .recording: await finishRecording()
            case .transcribing, .injecting: break // busy; ignore
            }
        }
    }

    /// The activation key went up. Only meaningful for push-to-talk; a toggle tap
    /// acts entirely on `activationBegan`.
    public func activationEnded() async {
        guard settings.mode == .pushToTalk, state == .recording else { return }
        await finishRecording()
    }

    // MARK: - Loop

    private func beginRecording() async {
        guard state == .idle else { return }
        do {
            try audio.startCapture()
        } catch {
            finish(.failed(String(describing: error)))
            return
        }
        lastOutcome = .idle
        state = .recording
    }

    private func finishRecording() async {
        guard state == .recording else { return }

        let captured = await audio.stopCapture()
        guard !captured.isEmpty else {
            finish(.noAudio)
            return
        }

        state = .transcribing
        let text: String
        do {
            text = try await engine.transcribe(captured)
        } catch {
            finish(.failed(String(describing: error)))
            return
        }

        // An empty transcript (silence that produced no words) is a no-audio result,
        // not something to paste.
        guard !text.isEmpty else {
            finish(.noAudio)
            return
        }

        state = .injecting
        do {
            try injector.inject(text, restoringPreviousClipboard: settings.restoreClipboard)
        } catch {
            finish(.failed(String(describing: error)))
            return
        }

        finish(.injected(text))
    }

    /// Record the cycle's result and return to idle. Every terminal path goes through
    /// here so the outcome and the idle reset can never drift apart.
    private func finish(_ outcome: Outcome) {
        lastOutcome = outcome
        onOutcome?(outcome)
        state = .idle
    }
}
