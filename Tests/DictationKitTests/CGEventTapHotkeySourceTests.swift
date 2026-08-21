import XCTest
import CoreGraphics
@testable import DictationKit

@MainActor
final class CGEventTapHotkeySourceTests: XCTestCase {

    private let rightOptionCode: Int64 = 61
    private let leftOptionCode: Int64 = 58
    private let commandCode: Int64 = 55

    // Device-dependent flag bits identifying a specific key is down (NX_DEVICE*KEYMASK).
    private let rightOptionBit: UInt64 = 0x40
    private let leftOptionBit: UInt64 = 0x20

    private func flags(_ raw: UInt64, alternate: Bool = false, command: Bool = false) -> CGEventFlags {
        var value = raw
        if alternate { value |= CGEventFlags.maskAlternate.rawValue }
        if command { value |= CGEventFlags.maskCommand.rawValue }
        return CGEventFlags(rawValue: value)
    }

    /// Build a source (permission granted by default) plus a recorder for the callbacks.
    private func makeSource(
        key: ModifierKey = .rightOption,
        granted: Bool = true
    ) -> (CGEventTapHotkeySource, () -> [String]) {
        var events: [String] = []
        let source = CGEventTapHotkeySource(key: key, permission: { granted })
        source.onActivationBegan = { events.append("began") }
        source.onActivationEnded = { events.append("ended") }
        return (source, { events })
    }

    // MARK: - Activation

    func testHoldingRightOptionAloneBeginsThenEnds() {
        let (source, events) = makeSource()
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(rightOptionBit, alternate: true))  // down
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(0))                                 // up
        XCTAssertEqual(events(), ["began", "ended"])
    }

    func testEndsOnlyOnceAndBeginsOnlyOnce() {
        let (source, events) = makeSource()
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(rightOptionBit, alternate: true))  // down
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(rightOptionBit, alternate: true))  // repeat down
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(0))                                 // up
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(0))                                 // repeat up
        XCTAssertEqual(events(), ["began", "ended"])
    }

    // MARK: - Held alone

    func testDoesNotBeginWhenAnotherModifierIsAlsoHeld() {
        let (source, events) = makeSource()
        // Right Option down together with Command — a chord, not a solo hold.
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(rightOptionBit, alternate: true, command: true))
        XCTAssertEqual(events(), [])
    }

    func testAnotherModifierChangingDoesNotToggleActivation() {
        let (source, events) = makeSource()
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(rightOptionBit, alternate: true))  // began
        // Command pressed while option is held: a different keyCode, so no transition.
        source.handleFlagsChanged(keyCode: commandCode, flags: flags(rightOptionBit, alternate: true, command: true))
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(0))                                 // ended
        XCTAssertEqual(events(), ["began", "ended"])
    }

    /// Regression: with Left Option already held, releasing Right Option must still end
    /// activation. The shared `.maskAlternate` flag stays set (Left is still down), so
    /// only the device-specific Right Option bit clearing tells us the key came up.
    func testReleasingRightOptionEndsEvenWhileLeftOptionHeld() {
        let (source, events) = makeSource()
        // Left Option already down (ignored — wrong keyCode for a Right-Option hotkey).
        source.handleFlagsChanged(keyCode: leftOptionCode, flags: flags(leftOptionBit, alternate: true))
        // Right Option pressed: both device bits + shared alternate flag set.
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(leftOptionBit | rightOptionBit, alternate: true))
        // Right Option released: alternate flag STILL set (Left holds it), only 0x40 clears.
        source.handleFlagsChanged(keyCode: rightOptionCode, flags: flags(leftOptionBit, alternate: true))
        XCTAssertEqual(events(), ["began", "ended"])
    }

    // MARK: - Configured key

    func testIgnoresTheWrongKey() {
        let (source, events) = makeSource()  // configured to Right Option
        source.handleFlagsChanged(keyCode: leftOptionCode, flags: flags(leftOptionBit, alternate: true))
        source.handleFlagsChanged(keyCode: leftOptionCode, flags: flags(0))
        XCTAssertEqual(events(), [], "Left Option must not activate a Right-Option hotkey")
    }

    func testKeyIsConfigurable() {
        let (source, events) = makeSource(key: .leftOption)
        source.handleFlagsChanged(keyCode: leftOptionCode, flags: flags(leftOptionBit, alternate: true))
        source.handleFlagsChanged(keyCode: leftOptionCode, flags: flags(0))
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
