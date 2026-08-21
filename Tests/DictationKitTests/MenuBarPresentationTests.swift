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

    // MARK: - Presenter (tracks transitions across a full dictation cycle)

    func testPresenterPairsTransitionsAcrossAWholeCycle() {
        var presenter = MenuBarPresenter()

        let record = presenter.advance(to: .recording)
        XCTAssertEqual(record.symbol, "mic.fill")
        XCTAssertEqual(record.sound, .start)

        let transcribe = presenter.advance(to: .transcribing)
        XCTAssertEqual(transcribe.symbol, "waveform")
        XCTAssertEqual(transcribe.sound, .stop)

        let inject = presenter.advance(to: .injecting)
        XCTAssertEqual(inject.symbol, "waveform")
        XCTAssertNil(inject.sound, "no cue between the post-recording steps")

        let done = presenter.advance(to: .idle)
        XCTAssertEqual(done.symbol, "mic")
        XCTAssertNil(done.sound)
    }

    func testPresenterEmitsStartOnlyOnceForRepeatedRecordingRenders() {
        var presenter = MenuBarPresenter()
        XCTAssertEqual(presenter.advance(to: .recording).sound, .start)
        XCTAssertNil(presenter.advance(to: .recording).sound, "already recording: no repeat cue")
    }
}
