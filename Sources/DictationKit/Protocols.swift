import Foundation

// The four OS boundaries the dictation loop runs against. Each is faked in tests;
// the real adapters land in later tickets (#3 whisper, #4 audio, #5 hotkey, #6 inject).

/// 16kHz mono PCM captured from the mic. `isEmpty` drives the "no audio" path — the
/// prototype found an unfinalized recording yields zero frames.
public struct CapturedAudio: Equatable, Sendable {
    public let samples: [Float]
    public init(samples: [Float]) { self.samples = samples }
    public var isEmpty: Bool { samples.isEmpty }
}

/// Captures microphone audio. Real impl: `AVAudioEngine` (#4).
@MainActor public protocol AudioSource {
    /// Begin capturing. Throws if the mic can't be opened (e.g. no permission).
    func startCapture() throws
    /// Stop capturing and hand back what was captured (possibly empty).
    func stopCapture() async -> CapturedAudio
}

/// Turns captured audio into text. Real impl: local whisper.cpp (#3); the protocol
/// is also the seam a cloud engine drops into later.
@MainActor public protocol TranscriptionEngine {
    func transcribe(_ audio: CapturedAudio) async throws -> String
    /// Run once at launch to hide first-use cost (e.g. Metal shader compile).
    func warmUp() async
}

/// Inserts text at the cursor. Real impl: pasteboard + synthesized ⌘V (#6).
@MainActor public protocol TextInjector {
    /// Insert `text` at the cursor. When `restoringPreviousClipboard` is true, the
    /// prior clipboard contents are put back after the paste; when false, the
    /// dictated text is left on the clipboard.
    func inject(_ text: String, restoringPreviousClipboard: Bool) throws
}

/// Reports activation of the hotkey. Real impl: `CGEventTap` on Right Option (#5).
/// The app layer (#7) connects these to the controller's `activationBegan/Ended`.
@MainActor public protocol HotkeySource: AnyObject {
    var onActivationBegan: (() -> Void)? { get set }
    var onActivationEnded: (() -> Void)? { get set }
    func start() throws
    func stop()
}

/// User-configurable behavior. Persisted in #8.
public struct Settings: Equatable, Sendable {
    public enum Mode: Sendable, Equatable {
        /// Hold to talk, release to transcribe+insert.
        case pushToTalk
        /// Tap to start, tap again to stop.
        case toggle
    }

    public var mode: Mode
    public var restoreClipboard: Bool

    public init(mode: Mode = .pushToTalk, restoreClipboard: Bool = true) {
        self.mode = mode
        self.restoreClipboard = restoreClipboard
    }
}
