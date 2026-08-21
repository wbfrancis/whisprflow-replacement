import XCTest
@testable import DictationKit

final class MenuBarPresentationTests: XCTestCase {

    // MARK: - Icon (AC: menu-bar icon shows idle vs recording state)

    func testIdleAndRecordingUseDistinctIcons() {
        let idle = MenuBarPresentation.symbolName(for: .idle)
        let recording = MenuBarPresentation.symbolName(for: .recording)
        XCTAssertEqual(idle, "mic")
        XCTAssertEqual(recording, "mic.fill")
        XCTAssertNotEqual(idle, recording, "idle and recording must be visually different")
    }

    func testTranscribingAndInjectingShareTheBusyIcon() {
        XCTAssertEqual(MenuBarPresentation.symbolName(for: .transcribing), "waveform")
        XCTAssertEqual(MenuBarPresentation.symbolName(for: .injecting), "waveform")
    }

    // MARK: - Sounds (AC: start and stop sounds play on the transitions)

    func testStartSoundWhenRecordingBegins() {
        XCTAssertEqual(MenuBarPresentation.sound(from: .idle, to: .recording), .start)
    }

    func testStopSoundWhenRecordingEnds() {
        XCTAssertEqual(MenuBarPresentation.sound(from: .recording, to: .transcribing), .stop)
    }

    func testNoSoundOnNonRecordingTransitions() {
        XCTAssertNil(MenuBarPresentation.sound(from: .transcribing, to: .injecting))
        XCTAssertNil(MenuBarPresentation.sound(from: .injecting, to: .idle))
        XCTAssertNil(MenuBarPresentation.sound(from: .idle, to: .idle))
    }

    func testStopSoundEvenIfRecordingGoesStraightToIdle() {
        // A no-audio release ends recording without transcribing; the stop cue still plays.
        XCTAssertEqual(MenuBarPresentation.sound(from: .recording, to: .idle), .stop)
    }
}
