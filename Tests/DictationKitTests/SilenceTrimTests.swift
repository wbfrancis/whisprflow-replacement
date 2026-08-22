import XCTest
@testable import DictationKit

final class SilenceTrimTests: XCTestCase {

    /// A block of "speech": a tone loud enough to clear the RMS threshold.
    private func tone(_ count: Int, amplitude: Float = 0.3) -> [Float] {
        (0..<count).map { amplitude * sinf(2 * .pi * 300 * Float($0) / 16_000) }
    }

    private func silence(_ count: Int) -> [Float] { [Float](repeating: 0, count: count) }

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
        // Speech (8000) plus the 200ms pad (3200) — well under the full 40000.
        XCTAssertLessThanOrEqual(out.count, 8_000 + 3_200 + 320)
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
}
