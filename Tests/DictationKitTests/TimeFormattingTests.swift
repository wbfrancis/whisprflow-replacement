import XCTest
@testable import DictationKit

final class TimeFormattingTests: XCTestCase {

    private func f(_ s: String) -> String { TimeFormatting.format(s) }

    // MARK: - o'clock (the Levels fixtures)

    func testWordHourOClock() {
        XCTAssertEqual(f("the meeting is at three o'clock tomorrow"),
                       "the meeting is at 3:00 tomorrow")
    }

    func testDigitHourOClock() {
        XCTAssertEqual(f("The meeting is at 3 o'clock tomorrow."),
                       "The meeting is at 3:00 tomorrow.")
    }

    // MARK: - bare hour + minutes

    func testHourTwenty() {
        XCTAssertEqual(f("call me at three twenty"), "call me at 3:20")
    }

    func testHourFifteen() {
        XCTAssertEqual(f("start at four fifteen please"), "start at 4:15 please")
    }

    func testHourOhFive() {
        XCTAssertEqual(f("it's three oh five"), "it's 3:05")
    }

    func testHourTwentyFiveHyphenated() {
        XCTAssertEqual(f("meet at nine twenty-five"), "meet at 9:25")
    }

    // MARK: - past / to

    func testHalfPast() {
        XCTAssertEqual(f("half past four"), "4:30")
    }

    func testQuarterPast() {
        XCTAssertEqual(f("quarter past four"), "4:15")
    }

    func testQuarterTo() {
        XCTAssertEqual(f("quarter to five"), "4:45")
    }

    func testMinutesPast() {
        XCTAssertEqual(f("ten past six"), "6:10")
    }

    func testMinutesTo() {
        XCTAssertEqual(f("ten to six"), "5:50")
    }

    func testQuarterToOneWrapsToTwelve() {
        XCTAssertEqual(f("quarter to one"), "12:45")
    }

    // MARK: - must NOT convert (times only)

    func testBareErrorCodeUntouched() {
        XCTAssertEqual(f("the API returns a 404 when the token expires"),
                       "the API returns a 404 when the token expires")
    }

    func testCountingUntouched() {
        // Six separate numbers, not a time.
        XCTAssertEqual(f("one two three four five six"), "one two three four five six")
    }

    func testHundredsUntouched() {
        XCTAssertEqual(f("about four hundred people"), "about four hundred people")
    }

    func testBareAdjacentSingleDigitsNotAClock() {
        // "three four" must not become 3:04 — only time-shaped minutes convert.
        XCTAssertEqual(f("section three four is next"), "section three four is next")
    }

    func testNoTimeIsUnchanged() {
        XCTAssertEqual(f("please send me the report by tomorrow morning"),
                       "please send me the report by tomorrow morning")
    }
}
