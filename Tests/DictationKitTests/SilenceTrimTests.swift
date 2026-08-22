import XCTest
@testable import DictationKit

final class SilenceTrimTests: XCTestCase {

    /// A block of "speech": a tone at a given amplitude.
    private func tone(_ count: Int, amplitude: Float = 0.3) -> [Float] {
        (0..<count).map { amplitude * sinf(2 * .pi * 300 * Float($0) / 16_000) }
    }

    private func silence(_ count: Int) -> [Float] { [Float](repeating: 0, count: count) }

    private let pad = 4_800  // must match SilenceTrim's default

    func testEmptyStaysEmpty() {
        XCTAssertEqual(SilenceTrim.trimmingTrailingSilence([]), [])
    }

    func testAllSilenceTrimsToEmpty() {
        XCTAssertEqual(SilenceTrim.trimmingTrailingSilence(silence(16_000)), [])
    }

    func testTrailingSilenceIsRemoved() {
        // 0.5s tone + 2s silence. The result should drop most of the silence.
        let input = tone(8_000) + silence(32_000)
        let out = SilenceTrim.trimmingTrailingSilence(input)
        XCTAssertLessThan(out.count, input.count)
        XCTAssertLessThanOrEqual(out.count, 8_000 + pad + 320)
        XCTAssertGreaterThanOrEqual(out.count, 8_000, "the speech itself must survive")
    }

    func testSpeechWithoutTrailingSilenceIsKeptWhole() {
        let input = tone(16_000)
        let out = SilenceTrim.trimmingTrailingSilence(input)
        XCTAssertEqual(out.count, input.count)
    }

    func testLeadingSilenceIsPreserved() {
        // Leading silence is NOT trimmed — only the tail — so the first word can't be clipped.
        let input = silence(8_000) + tone(8_000)
        let out = SilenceTrim.trimmingTrailingSilence(input)
        XCTAssertEqual(out.count, input.count)
    }

    func testQuietSpeechSurvivesInsteadOfTrimmingToEmpty() {
        // A whisper-level utterance (low amplitude) then silence. The adaptive threshold
        // must judge silence relative to this clip's own peak, so the quiet speech is kept
        // rather than mistaken for silence and discarded.
        let input = tone(8_000, amplitude: 0.02) + silence(16_000)
        let out = SilenceTrim.trimmingTrailingSilence(input)
        XCTAssertFalse(out.isEmpty, "quiet speech must not be trimmed away entirely")
        XCTAssertGreaterThanOrEqual(out.count, 8_000)
        XCTAssertLessThan(out.count, input.count, "its trailing silence should still be cut")
    }
}
