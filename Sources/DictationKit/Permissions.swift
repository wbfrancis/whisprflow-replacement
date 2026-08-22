/// The grant state of a permission the app needs.
public enum AuthStatus: Sendable, Equatable {
    case granted
    case denied
    /// Not yet asked — the system can still show its prompt.
    case notDetermined
}

/// A permission dictation depends on.
public enum Permission: Sendable, Equatable, CaseIterable {
    /// Microphone — to hear the dictation.
    case microphone
    /// Accessibility — to synthesize the paste keystroke and watch the hold-to-talk key.
    case accessibility
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
            return "Microphone access lets whisprflow hear your dictation."
        case .accessibility:
            return "Accessibility access lets whisprflow paste at the cursor and use the hold-to-talk key."
        }
    }

    /// Short status-line summary of what's still missing, or nil when everything's granted.
    public static func summary(_ state: PermissionsState) -> String? {
        let missing = missing(state)
        guard !missing.isEmpty else { return nil }
        let names = missing.map { $0 == .microphone ? "Microphone" : "Accessibility" }
        return "waiting on \(names.joined(separator: " + "))"
    }
}
