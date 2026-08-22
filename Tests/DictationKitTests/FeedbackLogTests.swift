import XCTest
@testable import DictationKit

/// Exercises the entry formatting and the append/create behavior against a temp file, so no
/// real Application Support path is touched.
final class FeedbackLogTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("feedback-\(UUID().uuidString).md")
    }

    private let epoch = Date(timeIntervalSince1970: 0)

    func testEntryTimestampsAndPrefixesTheNote() {
        let entry = FeedbackLog.entry("icon is too dim", at: epoch)
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.hasPrefix("- **"))
        XCTAssertTrue(entry!.contains("icon is too dim"))
        XCTAssertTrue(entry!.hasSuffix("\n"))
    }

    func testEntryFoldsMultipleLinesIntoOneBullet() {
        let entry = FeedbackLog.entry("line one\n  line two\n", at: epoch)
        XCTAssertTrue(entry!.contains("line one line two"))
        XCTAssertEqual(entry!.filter { $0 == "\n" }.count, 1)
    }

    func testBlankNoteYieldsNoEntry() {
        XCTAssertNil(FeedbackLog.entry("   \n\t", at: epoch))
    }

    func testAppendCreatesFileWithHeadingThenAppends() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = FeedbackLog(fileURL: url)

        XCTAssertTrue(try log.append("first note", at: epoch))
        XCTAssertTrue(try log.append("second note", at: epoch))

        let contents = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(contents.hasPrefix("# whisper feedback"))
        XCTAssertTrue(contents.contains("first note"))
        XCTAssertTrue(contents.contains("second note"))
        // Header appears once; the second append doesn't re-write it.
        XCTAssertEqual(contents.components(separatedBy: "# whisper feedback").count - 1, 1)
    }

    func testAppendOfBlankNoteWritesNothing() throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let log = FeedbackLog(fileURL: url)

        XCTAssertFalse(try log.append("  ", at: epoch))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
