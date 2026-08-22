import XCTest
@testable import DictationKit

final class TranscriptionScoreTests: XCTestCase {

    func testIdenticalIsZero() {
        XCTAssertEqual(TranscriptionScore.wer(expected: "the quick brown fox",
                                              got: "the quick brown fox"), 0, accuracy: 1e-9)
    }

    func testCaseAndPunctuationIgnored() {
        XCTAssertEqual(TranscriptionScore.wer(expected: "one two three four five six",
                                              got: "One, two, three, four, five, six."),
                       0, accuracy: 1e-9)
    }

    func testOneSubstitutionIsOneOverWordCount() {
        // "brown" -> "black": 1 edit over 4 expected words.
        XCTAssertEqual(TranscriptionScore.wer(expected: "the quick brown fox",
                                              got: "the quick black fox"), 0.25, accuracy: 1e-9)
    }

    func testHallucinatedContinuationScoresPastOne() {
        // "1 2 3 4 5 6" -> "...10": four spurious insertions over six expected words.
        let wer = TranscriptionScore.wer(expected: "one two three four five six",
                                         got: "one two three four five six seven eight nine ten")
        XCTAssertEqual(wer, 4.0 / 6.0, accuracy: 1e-9)
    }

    func testEmptyExpected() {
        XCTAssertEqual(TranscriptionScore.wer(expected: "", got: ""), 0, accuracy: 1e-9)
        XCTAssertEqual(TranscriptionScore.wer(expected: "", got: "unexpected words"), 1, accuracy: 1e-9)
    }

    func testDroppedTailCountsAsDeletions() {
        // Expected six words, got only four: two deletions over six.
        let wer = TranscriptionScore.wer(expected: "one two three four five six",
                                         got: "one two three four")
        XCTAssertEqual(wer, 2.0 / 6.0, accuracy: 1e-9)
    }
}
