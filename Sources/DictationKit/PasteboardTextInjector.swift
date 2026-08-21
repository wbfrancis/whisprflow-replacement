import AppKit
import CoreGraphics
import ApplicationServices

public enum InjectionError: Error, Equatable {
    /// The Accessibility permission needed to synthesize a keystroke isn't granted.
    /// Detectable up front via `PasteboardTextInjector.isAccessibilityGranted`.
    case accessibilityNotGranted
    /// The paste keystroke couldn't be built or posted, so nothing was inserted. Distinct
    /// from a missing permission — the caller shouldn't read it as a permissions problem.
    case keystrokeSynthesisFailed
}

/// A point-in-time copy of the clipboard, kept so a paste can put the prior contents
/// back. One entry per pasteboard item; each maps a type identifier to its raw data,
/// so non-text content (not just the string) survives the round trip.
public struct ClipboardSnapshot: Equatable, Sendable {
    public let items: [[String: Data]]
    public init(items: [[String: Data]]) { self.items = items }
    public var isEmpty: Bool { items.isEmpty }
}

/// The clipboard the injector reads and writes. Real impl: `SystemClipboard`.
@MainActor public protocol Clipboard {
    func snapshot() -> ClipboardSnapshot
    func writeString(_ text: String)
    func restore(_ snapshot: ClipboardSnapshot)
}

/// Synthesizes the paste keystroke (⌘V). Real impl: `CGEventPasteKeystroke`.
@MainActor public protocol PasteKeystroke {
    /// Whether the Accessibility permission that keystroke synthesis needs is granted.
    var accessibilityGranted: Bool { get }
    /// Post ⌘V to the frontmost app. Throws if the keystroke can't be synthesized.
    func paste() throws
}

/// `TextInjector` that puts text on the clipboard and synthesizes ⌘V to land it at the
/// cursor of the frontmost app — the prototype-validated approach. With
/// `restoringPreviousClipboard` on (default), the prior clipboard is put back after the
/// paste; with it off, the dictated text is left on the clipboard.
@MainActor
public final class PasteboardTextInjector: TextInjector {
    private let clipboard: Clipboard
    private let keystroke: PasteKeystroke
    private let settle: TimeInterval
    private let sleep: (TimeInterval) -> Void

    /// - Parameters:
    ///   - settle: how long to wait after posting ⌘V before restoring the clipboard, so
    ///     the paste is consumed first. The prototype found a short pause is needed.
    ///   - sleep: the wait itself, injectable so tests run without real delay.
    public init(
        clipboard: Clipboard = SystemClipboard(),
        keystroke: PasteKeystroke = CGEventPasteKeystroke(),
        settle: TimeInterval = 0.15,
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.clipboard = clipboard
        self.keystroke = keystroke
        self.settle = settle
        self.sleep = sleep
    }

    /// Whether keystroke synthesis is permitted right now. The app (#9) reads this to
    /// detect a missing Accessibility grant before dictation is attempted.
    public var isAccessibilityGranted: Bool { keystroke.accessibilityGranted }

    public func inject(_ text: String, restoringPreviousClipboard: Bool) throws {
        guard keystroke.accessibilityGranted else { throw InjectionError.accessibilityNotGranted }

        let saved = restoringPreviousClipboard ? clipboard.snapshot() : nil
        clipboard.writeString(text)

        do {
            try keystroke.paste()
        } catch {
            // Paste failed after we clobbered the clipboard; put the prior contents back
            // so a failed injection doesn't also lose the user's clipboard.
            if let saved { clipboard.restore(saved) }
            throw error
        }

        if let saved {
            sleep(settle)
            clipboard.restore(saved)
        }
    }
}

// MARK: - Real adapters

/// `Clipboard` over `NSPasteboard.general`, preserving every item/type on snapshot.
@MainActor
public final class SystemClipboard: Clipboard {
    private let pasteboard: NSPasteboard
    public init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    public func snapshot() -> ClipboardSnapshot {
        var items: [[String: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var map: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { map[type.rawValue] = data }
            }
            if !map.isEmpty { items.append(map) }
        }
        return ClipboardSnapshot(items: items)
    }

    public func writeString(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    public func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.items.map { map -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (raw, data) in map {
                item.setData(data, forType: NSPasteboard.PasteboardType(raw))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}

/// `PasteKeystroke` that posts a synthesized ⌘V via Core Graphics. Needs the process to
/// hold the Accessibility permission, reported by `AXIsProcessTrusted()`.
@MainActor
public final class CGEventPasteKeystroke: PasteKeystroke {
    public init() {}

    public var accessibilityGranted: Bool { AXIsProcessTrusted() }

    public func paste() throws {
        let vKey: CGKeyCode = 9  // 'v'
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            // Event creation failed; posting nothing would be a silent no-op, so surface it
            // instead of letting the caller believe the text was pasted.
            throw InjectionError.keystrokeSynthesisFailed
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
