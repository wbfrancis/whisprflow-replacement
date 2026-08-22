import XCTest
@testable import DictationKit

@MainActor
final class DictationControllerTests: XCTestCase {

    private func makeController(
        settings: Settings = Settings()
    ) -> (DictationController, FakeAudioSource, FakeTranscriptionEngine, FakeTextInjector) {
        let audio = FakeAudioSource()
        let engine = FakeTranscriptionEngine()
        let injector = FakeTextInjector()
        let controller = DictationController(
            audio: audio, engine: engine, injector: injector, settings: settings
        )
        return (controller, audio, engine, injector)
    }

    // MARK: - Push-to-talk

    func testPushToTalk_recordsThenTranscribesAndInjects() async {
        let (c, audio, engine, injector) = makeController()
        engine.result = "the quick brown fox"

        await c.activationBegan()
        XCTAssertEqual(c.state, .recording)
        XCTAssertEqual(audio.startCount, 1)

        await c.activationEnded()

        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(engine.transcribeCount, 1)
        XCTAssertEqual(injector.injected, ["the quick brown fox"])
        XCTAssertEqual(c.lastOutcome, .injected("the quick brown fox"))
    }

    func testPushToTalk_stateSequenceIsIdleRecordingTranscribingInjectingIdle() async {
        let (c, _, _, _) = makeController()
        var log: [DictationController.State] = []
        c.onStateChange = { log.append($0) }

        await c.activationBegan()
        await c.activationEnded()

        XCTAssertEqual(log, [.recording, .transcribing, .injecting, .idle])
    }

    func testPushToTalk_transcribeReceivesCapturedAudio() async {
        let (c, audio, engine, _) = makeController()
        audio.toReturn = CapturedAudio(samples: [1, 2, 3, 4])

        await c.activationBegan()
        await c.activationEnded()

        XCTAssertEqual(engine.lastAudio, CapturedAudio(samples: [1, 2, 3, 4]))
    }

    // MARK: - Outcome callback

    func testOnOutcomeFiresWithInjectedText() async {
        let (c, _, engine, _) = makeController()
        engine.result = "hello world"
        var outcomes: [DictationController.Outcome] = []
        c.onOutcome = { outcomes.append($0) }

        await c.activationBegan()
        await c.activationEnded()

        XCTAssertEqual(outcomes, [.injected("hello world")])
    }

    func testOnOutcomeReportsCaptureFailure() async {
        let (c, audio, _, _) = makeController()
        audio.startError = TestError()  // e.g. the mic can't be opened (no permission)
        var outcomes: [DictationController.Outcome] = []
        c.onOutcome = { outcomes.append($0) }

        await c.activationBegan()

        XCTAssertEqual(outcomes.count, 1)
        if case .failed = outcomes.first { } else { XCTFail("expected a .failed outcome, got \(outcomes)") }
    }

    // MARK: - Toggle

    func testToggle_firstTapStartsSecondTapStops() async {
        let (c, audio, engine, injector) = makeController(settings: Settings(mode: .toggle))
        engine.result = "toggle text"

        await c.activationBegan()          // first tap
        XCTAssertEqual(c.state, .recording)

        // A key-up in toggle mode does nothing.
        await c.activationEnded()
        XCTAssertEqual(c.state, .recording)

        await c.activationBegan()          // second tap
        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertEqual(injector.injected, ["toggle text"])
    }

    // MARK: - Clipboard restore

    func testRestoreOn_previousClipboardIsRestored() async {
        let (c, _, engine, injector) = makeController(settings: Settings(restoreClipboard: true))
        injector.clipboard = "my earlier copy"
        engine.result = "dictated words"

        await c.activationBegan()
        await c.activationEnded()

        XCTAssertEqual(injector.injected, ["dictated words"])
        XCTAssertEqual(injector.clipboard, "my earlier copy")
    }

    func testRestoreOff_dictatedTextIsLeftOnClipboard() async {
        let (c, _, engine, injector) = makeController(settings: Settings(restoreClipboard: false))
        injector.clipboard = "my earlier copy"
        engine.result = "dictated words"

        await c.activationBegan()
        await c.activationEnded()

        XCTAssertEqual(injector.clipboard, "dictated words")
    }

    // MARK: - No audio

    func testEmptyCapture_yieldsNoAudioAndDoesNotInject() async {
        let (c, audio, engine, injector) = makeController()
        audio.toReturn = CapturedAudio(samples: [])

        await c.activationBegan()
        await c.activationEnded()

        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.lastOutcome, .noAudio)
        XCTAssertEqual(engine.transcribeCount, 0)
        XCTAssertTrue(injector.injected.isEmpty)
    }

    func testEmptyTranscript_yieldsNoAudioAndDoesNotInject() async {
        let (c, _, engine, injector) = makeController()
        engine.result = ""

        await c.activationBegan()
        await c.activationEnded()

        XCTAssertEqual(c.lastOutcome, .noAudio)
        XCTAssertTrue(injector.injected.isEmpty)
    }

    // MARK: - Errors

    func testTranscriptionError_yieldsFailedAndDoesNotInject() async {
        let (c, _, engine, injector) = makeController()
        engine.error = TestError()

        await c.activationBegan()
        await c.activationEnded()

        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.lastOutcome, .failed(String(describing: TestError())))
        XCTAssertTrue(injector.injected.isEmpty)
    }

    func testMicStartError_yieldsFailedAndDoesNotRecord() async {
        let (c, audio, _, _) = makeController()
        audio.startError = TestError()

        await c.activationBegan()

        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.lastOutcome, .failed(String(describing: TestError())))
    }

    func testInjectionError_yieldsFailed() async {
        let (c, _, engine, injector) = makeController()
        engine.result = "will fail to paste"
        injector.injectError = TestError()

        await c.activationBegan()
        await c.activationEnded()

        XCTAssertEqual(c.state, .idle)
        XCTAssertEqual(c.lastOutcome, .failed(String(describing: TestError())))
    }

    // MARK: - Hotkey seam

    func testHotkeySource_startStopAndDispatchesActivationCallbacks() throws {
        let hotkey = FakeHotkeySource()
        var began = 0
        var ended = 0
        hotkey.onActivationBegan = { began += 1 }
        hotkey.onActivationEnded = { ended += 1 }

        try hotkey.start()
        XCTAssertTrue(hotkey.started)

        hotkey.pressDown()
        hotkey.releaseUp()
        XCTAssertEqual(began, 1)
        XCTAssertEqual(ended, 1)

        hotkey.stop()
        XCTAssertFalse(hotkey.started)
    }

    // MARK: - Warm-up

    func testWarmUp_runsOneEngineWarmUp() async {
        let (c, _, engine, _) = makeController()

        await c.warmUp()

        XCTAssertEqual(engine.warmUpCount, 1)
    }
}
