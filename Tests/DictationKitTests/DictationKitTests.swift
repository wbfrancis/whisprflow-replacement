import XCTest
@testable import DictationKit

// Establishes the test target for the tested core. Ticket #2 adds the real
// DictationController tests here, driven by fakes.
final class DictationKitTests: XCTestCase {
    func testVersionIsPresent() {
        XCTAssertFalse(DictationKit.version.isEmpty)
    }
}
