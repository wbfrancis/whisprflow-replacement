import AppKit
import CoreGraphics
import ApplicationServices

public enum HotkeyError: Error, Equatable {
    /// The Accessibility permission an event tap needs isn't granted. Detectable up front
    /// via `CGEventTapHotkeySource.isAccessibilityGranted`; feeds the permissions flow (#9).
    case accessibilityNotGranted
    /// The event tap couldn't be created even though permission looked granted.
    case eventTapCreationFailed
}

/// A modifier key usable as the push-to-talk trigger. Carries both the virtual keycode
/// and the device-dependent flag bit that identifies *this* key (not just its modifier
/// class), so left and right sides of the same modifier are told apart — the generic
/// `.maskAlternate`/`.maskShift`/… flags can't distinguish sides. Bit values are the
/// `NX_DEVICE{L,R}*KEYMASK` constants from IOKit.
public struct ModifierKey: Equatable, Sendable {
    public let keyCode: CGKeyCode
    let deviceMask: UInt64

    public static let rightOption  = ModifierKey(keyCode: 61, deviceMask: 0x40)
    public static let leftOption   = ModifierKey(keyCode: 58, deviceMask: 0x20)
    public static let rightCommand = ModifierKey(keyCode: 54, deviceMask: 0x10)
    public static let leftCommand  = ModifierKey(keyCode: 55, deviceMask: 0x08)
    public static let rightShift   = ModifierKey(keyCode: 60, deviceMask: 0x04)
    public static let leftShift    = ModifierKey(keyCode: 56, deviceMask: 0x02)
    public static let rightControl = ModifierKey(keyCode: 62, deviceMask: 0x2000)
    public static let leftControl  = ModifierKey(keyCode: 59, deviceMask: 0x01)
}

/// Pure decision for the push-to-talk hotkey, separated from the `CGEventTap` plumbing so
/// it can be tested without a live tap. It watches modifier-flag changes and decides when
/// the configured key (Right Option by default) begins and ends activation.
///
/// "Held alone": activation begins only when the key goes down with no other modifier
/// class (⌘/⌃/⇧) also held, so the hotkey doesn't fire as part of a shortcut chord.
struct HotkeyEvaluator {
    enum Transition: Equatable { case began, ended, none }

    let key: ModifierKey
    private(set) var isActive = false

    private static let otherModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift]

    init(key: ModifierKey) { self.key = key }

    /// Feed one `.flagsChanged` event. Returns the resulting transition, if any.
    mutating func handle(keyCode: Int64, flags: CGEventFlags) -> Transition {
        guard keyCode == Int64(key.keyCode) else { return .none }

        // Whether *this specific* key is down, from its device bit — not the shared
        // modifier flag, which would still read "down" when the other side is held.
        let keyDown = (flags.rawValue & key.deviceMask) != 0
        let hasOtherModifiers = !flags.intersection(Self.otherModifiers).isEmpty

        if keyDown, !hasOtherModifiers, !isActive {
            isActive = true
            return .began
        }
        if !keyDown, isActive {
            isActive = false
            return .ended
        }
        // Key down alongside another modifier, or a repeat of the current state: no change.
        return .none
    }
}

/// `HotkeySource` backed by a `CGEventTap` watching modifier-flag changes. Reports
/// activation when Right Option (configurable) is held alone. The tap only listens — it
/// doesn't swallow the key — so the keyboard keeps working normally while dictating.
@MainActor
public final class CGEventTapHotkeySource: HotkeySource {
    public var onActivationBegan: (() -> Void)?
    public var onActivationEnded: (() -> Void)?

    private var evaluator: HotkeyEvaluator
    private let permission: () -> Bool
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// - Parameters:
    ///   - key: the activation key. Default Right Option.
    ///   - permission: the Accessibility check, injectable so the permission gate is
    ///     testable without touching the real system state.
    public init(
        key: ModifierKey = .rightOption,
        permission: @escaping () -> Bool = { AXIsProcessTrusted() }
    ) {
        self.evaluator = HotkeyEvaluator(key: key)
        self.permission = permission
    }

    public var isAccessibilityGranted: Bool { permission() }

    public func start() throws {
        guard permission() else { throw HotkeyError.accessibilityNotGranted }
        guard tap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: hotkeyTapCallback,
            userInfo: refcon
        ) else {
            throw HotkeyError.eventTapCreationFailed
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.runLoopSource = source
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// Route one flag-change through the evaluator and fire the matching callback. Called
    /// from the tap callback (on the main run loop) and driven directly by tests.
    func handleFlagsChanged(keyCode: Int64, flags: CGEventFlags) {
        switch evaluator.handle(keyCode: keyCode, flags: flags) {
        case .began: onActivationBegan?()
        case .ended: onActivationEnded?()
        case .none: break
        }
    }

    /// Re-enable the tap after the system disables it (e.g. a slow callback times it out).
    func reenableTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }
}

/// C-compatible tap callback: it can't capture context, so `self` arrives via `refcon`.
/// The tap is attached to the main run loop, so this runs on the main actor.
private func hotkeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let source = Unmanaged<CGEventTapHotkeySource>.fromOpaque(refcon).takeUnretainedValue()

    // Read the primitive (Sendable) fields out here, before hopping to the main actor, so
    // the non-Sendable CGEvent itself never crosses the isolation boundary.
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags

    MainActor.assumeIsolated {
        switch type {
        case .flagsChanged:
            source.handleFlagsChanged(keyCode: keyCode, flags: flags)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            source.reenableTap()
        default:
            break
        }
    }
    return Unmanaged.passUnretained(event)
}
