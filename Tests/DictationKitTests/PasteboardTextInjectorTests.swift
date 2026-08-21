import XCTest
@testable import DictationKit

@MainActor
final class PasteboardTextInjectorTests: XCTestCase {

    // MARK: - Fakes

    /// Records the ordered sequence of clipboard/keystroke events so tests can assert
    /// that snapshot → write → paste → restore happens in the right order.
    final class EventLog {
        private(set) var events: [String] = []
        func record(_ e: String) { events.append(e) }
    }

    final class FakeClipboard: Clipboard {
        let log: EventLog
        /// The single string standing in for the clipboard's contents.
        var contents: String?
        init(log: EventLog, contents: String? = nil) {
            self.log = log
            self.contents = contents
        }

        func snapshot() -> ClipboardSnapshot {
            log.record("snapshot")
            guard let contents else { return ClipboardSnapshot(items: []) }
            return ClipboardSnapshot(items: [["str": Data(contents.utf8)]])
        }

        func writeString(_ text: String) {
            log.record("write:\(text)")
            contents = text
        }

        func restore(_ snapshot: ClipboardSnapshot) {
            log.record("restore")
            if let data = snapshot.items.first?["str"] {
                contents = String(decoding: data, as: UTF8.self)
            } else {
                contents = nil
            }
        }
    }

    final class FakePasteKeystroke: PasteKeystroke {
        let log: EventLog
        var accessibilityGranted: Bool
        var pasteError: Error?
        init(log: EventLog, granted: Bool = true) {
            self.log = log
            self.accessibilityGranted = granted
        }

        func paste() throws {
            log.record("paste")
            if let pasteError { throw pasteError }
        }
    }

    private func makeInjector(
        granted: Bool = true,
        clipboardContents: String? = nil
    ) -> (PasteboardTextInjector, FakeClipboard, FakePasteKeystroke, EventLog) {
        let log = EventLog()
        let clipboard = FakeClipboard(log: log, contents: clipboardContents)
        let keystroke = FakePasteKeystroke(log: log, granted: granted)
        let injector = PasteboardTextInjector(
            clipboard: clipboard,
            keystroke: keystroke,
            settle: 0,
            sleep: { _ in }
        )
        return (injector, clipboard, keystroke, log)
    }

    // MARK: - Tests

    func testInjectPastesTheText() throws {
        let (injector, _, _, log) = makeInjector()
        try injector.inject("hello", restoringPreviousClipboard: false)
        XCTAssertTrue(log.events.contains("write:hello"))
        XCTAssertTrue(log.events.contains("paste"))
    }

    func testRestoreOnPutsPriorClipboardBack() throws {
        let (injector, clipboard, _, _) = makeInjector(clipboardContents: "original")
        try injector.inject("dictated", restoringPreviousClipboard: true)
        XCTAssertEqual(clipboard.contents, "original")
    }

    func testRestoreOffLeavesDictatedTextOnClipboard() throws {
        let (injector, clipboard, _, _) = makeInjector(clipboardContents: "original")
        try injector.inject("dictated", restoringPreviousClipboard: false)
        XCTAssertEqual(clipboard.contents, "dictated")
    }

    func testRestoreOffDoesNotSnapshotOrRestore() throws {
        let (injector, _, _, log) = makeInjector(clipboardContents: "original")
        try injector.inject("dictated", restoringPreviousClipboard: false)
        XCTAssertFalse(log.events.contains("snapshot"))
        XCTAssertFalse(log.events.contains("restore"))
    }

    func testEventOrderIsSnapshotWritePasteRestore() throws {
        let (injector, _, _, log) = makeInjector(clipboardContents: "original")
        try injector.inject("dictated", restoringPreviousClipboard: true)
        XCTAssertEqual(log.events, ["snapshot", "write:dictated", "paste", "restore"])
    }

    func testMissingAccessibilityThrowsAndTouchesNothing() throws {
        let (injector, clipboard, _, log) = makeInjector(granted: false, clipboardContents: "original")
        XCTAssertThrowsError(try injector.inject("dictated", restoringPreviousClipboard: true)) { error in
            XCTAssertEqual(error as? InjectionError, .accessibilityNotGranted)
        }
        XCTAssertEqual(clipboard.contents, "original", "clipboard must be untouched when permission is missing")
        XCTAssertTrue(log.events.isEmpty, "no clipboard or keystroke work before the permission check")
    }

    func testIsAccessibilityGrantedReflectsTheKeystroke() {
        let (grantedInjector, _, _, _) = makeInjector(granted: true)
        let (deniedInjector, _, _, _) = makeInjector(granted: false)
        XCTAssertTrue(grantedInjector.isAccessibilityGranted)
        XCTAssertFalse(deniedInjector.isAccessibilityGranted)
    }

    func testPasteFailureRestoresClipboard() throws {
        let (injector, clipboard, keystroke, _) = makeInjector(clipboardContents: "original")
        keystroke.pasteError = TestError()
        XCTAssertThrowsError(try injector.inject("dictated", restoringPreviousClipboard: true))
        XCTAssertEqual(clipboard.contents, "original", "a failed paste must not lose the prior clipboard")
    }
}
