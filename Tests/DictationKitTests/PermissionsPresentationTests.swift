import XCTest
@testable import DictationKit

final class PermissionsPresentationTests: XCTestCase {

    private func state(_ mic: AuthStatus, _ accessibility: Bool) -> PermissionsState {
        PermissionsState(microphone: mic, accessibilityGranted: accessibility)
    }

    // MARK: - Readiness

    func testReadyOnlyWhenBothGranted() {
        XCTAssertTrue(PermissionsPresentation.isReady(state(.granted, true)))
        XCTAssertFalse(PermissionsPresentation.isReady(state(.granted, false)))
        XCTAssertFalse(PermissionsPresentation.isReady(state(.denied, true)))
        XCTAssertFalse(PermissionsPresentation.isReady(state(.notDetermined, true)))
    }

    // MARK: - What's missing

    func testMissingIsEmptyWhenReady() {
        XCTAssertEqual(PermissionsPresentation.missing(state(.granted, true)), [])
    }

    func testMissingListsMicrophoneFirst() {
        XCTAssertEqual(PermissionsPresentation.missing(state(.notDetermined, false)),
                       [.microphone, .accessibility])
    }

    func testMissingReflectsEachPermissionIndependently() {
        XCTAssertEqual(PermissionsPresentation.missing(state(.granted, false)), [.accessibility])
        XCTAssertEqual(PermissionsPresentation.missing(state(.denied, true)), [.microphone])
    }

    // MARK: - Messaging

    func testSummaryIsNilWhenReady() {
        XCTAssertNil(PermissionsPresentation.summary(state(.granted, true)))
    }

    func testSummaryNamesWhatIsMissing() {
        XCTAssertEqual(PermissionsPresentation.summary(state(.denied, true)), "waiting on Microphone")
        XCTAssertEqual(PermissionsPresentation.summary(state(.granted, false)), "waiting on Accessibility")
        XCTAssertEqual(PermissionsPresentation.summary(state(.notDetermined, false)),
                       "waiting on Microphone + Accessibility")
    }

    func testInstructionsAreDistinctAndNonEmpty() {
        let mic = PermissionsPresentation.instruction(for: .microphone)
        let ax = PermissionsPresentation.instruction(for: .accessibility)
        XCTAssertFalse(mic.isEmpty)
        XCTAssertFalse(ax.isEmpty)
        XCTAssertNotEqual(mic, ax)
    }
}
