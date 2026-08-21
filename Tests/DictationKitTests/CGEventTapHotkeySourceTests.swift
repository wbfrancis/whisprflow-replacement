import XCTest
import CoreGraphics
@testable import DictationKit

@MainActor
final class CGEventTapHotkeySourceTests: XCTestCase {

    private let rightOption: Int64 = 61
    private let leftOption: Int64 = 58

    /// Build a source (permission granted by default) plus recorders for the two callbacks.
    private func makeSource(
        keyCode: CGKeyCode = 61,
        granted: Bool = true
    ) -> (CGEventTapHotkeySource, () -> [String]) {
        var events: [String] = []
        let source = CGEventTapHotkeySource(keyCode: keyCode, permission: { granted })
        source.onActivationBegan = { events.append("began") }
        source.onActivationEnded = { events.append("ended") }
        return (source, { events })
    }

    // MARK: - Activation

    func testHoldingRightOptionAloneBeginsThenEnds() {
        let (source, events) = makeSource()
        source.handleFlagsChanged(keyCode: rightOption, flags: .maskAlternate)  // down
        source.handleFlagsChanged(keyCode: rightOption, flags: [])              // up
        XCTAssertEqual(events(), ["began", "ended"])
    }

    func testEndsOnlyOnceAndBeginsOnlyOnce() {
        let (source, events) = makeSource()
        source.handleFlagsChanged(keyCode: rightOption, flags: .maskAlternate)  // down
        source.handleFlagsChanged(keyCode: rightOption, flags: .maskAlternate)  // repeat down
        source.handleFlagsChanged(keyCode: rightOption, flags: [])              // up
        source.handleFlagsChanged(keyCode: rightOption, flags: [])              // repeat up
        XCTAssertEqual(events(), ["began", "ended"])
    }

    // MARK: - Held alone

    func testDoesNotBeginWhenAnotherModifierIsAlsoHeld() {
        let (source, events) = makeSource()
        // Right Option down together with Command — a chord, not a solo hold.
        source.handleFlagsChanged(keyCode: rightOption, flags: [.maskAlternate, .maskCommand])
        XCTAssertEqual(events(), [])
    }

    func testAnotherModifierChangingDoesNotToggleActivation() {
        let (source, events) = makeSource()
        source.handleFlagsChanged(keyCode: rightOption, flags: .maskAlternate)  // began
        // Command pressed while option is held: a different keyCode, so no transition.
        source.handleFlagsChanged(keyCode: 55, flags: [.maskAlternate, .maskCommand])
        source.handleFlagsChanged(keyCode: rightOption, flags: [])              // ended
        XCTAssertEqual(events(), ["began", "ended"])
    }

    // MARK: - Configured key

    func testIgnoresTheWrongKey() {
        let (source, events) = makeSource()  // configured to Right Option
        source.handleFlagsChanged(keyCode: leftOption, flags: .maskAlternate)
        source.handleFlagsChanged(keyCode: leftOption, flags: [])
        XCTAssertEqual(events(), [], "Left Option must not activate a Right-Option hotkey")
    }

    func testKeyIsConfigurable() {
        let (source, events) = makeSource(keyCode: 58)  // Left Option
        source.handleFlagsChanged(keyCode: leftOption, flags: .maskAlternate)
        source.handleFlagsChanged(keyCode: leftOption, flags: [])
        XCTAssertEqual(events(), ["began", "ended"])
    }

    // MARK: - Permission

    func testStartThrowsWhenAccessibilityMissing() {
        let (source, _) = makeSource(granted: false)
        XCTAssertThrowsError(try source.start()) { error in
            XCTAssertEqual(error as? HotkeyError, .accessibilityNotGranted)
        }
    }

    func testIsAccessibilityGrantedReflectsPermission() {
        let (granted, _) = makeSource(granted: true)
        let (denied, _) = makeSource(granted: false)
        XCTAssertTrue(granted.isAccessibilityGranted)
        XCTAssertFalse(denied.isAccessibilityGranted)
    }
}
