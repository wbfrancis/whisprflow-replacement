/// A subtle audio cue for a dictation transition.
public enum DictationSound: Sendable, Equatable {
    /// Recording started — played when the key goes down.
    case start
    /// Recording ended — played when the key is released.
    case stop
}

/// Pure mapping from dictation state to menu-bar presentation, kept out of the app layer
/// so the icon and sound choices are testable without AppKit. The executable turns these
/// into an `NSImage` and `NSSound`; the decisions live here.
public enum MenuBarPresentation {
    /// SF Symbol name for the status-bar icon in a given state. Idle shows an outline mic;
    /// recording fills it; the post-recording work shows a waveform so the user can tell
    /// "listening" from "thinking".
    public static func symbolName(for state: DictationController.State) -> String {
        switch state {
        case .idle: return "mic"
        case .recording: return "mic.fill"
        case .transcribing, .injecting: return "waveform"
        }
    }

    /// The sound (if any) to play on a state transition: a start cue when recording begins,
    /// a stop cue when it ends. Other transitions are silent.
    public static func sound(
        from old: DictationController.State,
        to new: DictationController.State
    ) -> DictationSound? {
        if old != .recording, new == .recording { return .start }
        if old == .recording, new != .recording { return .stop }
        return nil
    }
}

/// Tracks the previous state so the app doesn't have to pair transitions itself. Each
/// `advance(to:)` returns the icon for the new state and the sound for the step taken to
/// reach it — keeping the whole state→presentation mapping, transitions included, testable.
public struct MenuBarPresenter {
    private var lastState: DictationController.State

    public init(initial: DictationController.State = .idle) {
        self.lastState = initial
    }

    public mutating func advance(
        to state: DictationController.State
    ) -> (symbol: String, sound: DictationSound?) {
        let result = (
            symbol: MenuBarPresentation.symbolName(for: state),
            sound: MenuBarPresentation.sound(from: lastState, to: state)
        )
        lastState = state
        return result
    }
}
