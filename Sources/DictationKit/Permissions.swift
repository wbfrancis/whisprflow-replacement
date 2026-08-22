/// The grant state of a permission the app needs.
public enum AuthStatus: Sendable, Equatable {
    /// Granted — the app can use it.
    case granted
    /// Refused, or restricted by policy — the user must re-enable it in System Settings.
    case denied
    /// Not yet asked — the system can still show its prompt.
    case notDetermined
}

/// A permission dictation depends on.
public enum Permission: Sendable, Equatable {
    /// Microphone — to hear the dictation.
    case microphone
    /// Accessibility — to synthesize the paste keystroke and watch the hold-to-talk key.
    case accessibility

    /// Human-readable name, used in status lines and the settings deep-link buttons.
    public var displayName: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        }
    }
}

/// A snapshot of the two permissions dictation needs.
public struct PermissionsState: Sendable, Equatable {
    public var microphone: AuthStatus
    public var accessibilityGranted: Bool

    public init(microphone: AuthStatus, accessibilityGranted: Bool) {
        self.microphone = microphone
        self.accessibilityGranted = accessibilityGranted
    }
}

/// Pure decisions about permissions — what's missing, what to tell the user — kept out of
/// the app layer so the first-run logic is testable without prompting the real system.
public enum PermissionsPresentation {
    /// Dictation can run only with both permissions granted.
    public static func isReady(_ state: PermissionsState) -> Bool {
        state.microphone == .granted && state.accessibilityGranted
    }

    /// Whether to fire the one-time system microphone prompt: only when the user hasn't
    /// decided yet (a denied mic can't be re-prompted; it needs System Settings).
    public static func shouldRequestMicrophone(_ state: PermissionsState) -> Bool {
        state.microphone == .notDetermined
    }

    /// The permissions still needed, microphone first: it has a one-tap system prompt,
    /// while Accessibility needs a manual grant the user must be walked to.
    public static func missing(_ state: PermissionsState) -> [Permission] {
        var result: [Permission] = []
        if state.microphone != .granted { result.append(.microphone) }
        if !state.accessibilityGranted { result.append(.accessibility) }
        return result
    }

    /// One-line explanation of why a permission is needed, for the first-run window.
    public static func instruction(for permission: Permission) -> String {
        switch permission {
        case .microphone:
            return "Microphone access lets whisper hear your dictation."
        case .accessibility:
            return "Accessibility access lets whisper paste at the cursor and use the hold-to-talk key."
        }
    }

    /// Short status-line summary of what's still missing, or nil when everything's granted.
    public static func summary(_ state: PermissionsState) -> String? {
        let missing = missing(state)
        guard !missing.isEmpty else { return nil }
        return "waiting on \(missing.map(\.displayName).joined(separator: " + "))"
    }
}
