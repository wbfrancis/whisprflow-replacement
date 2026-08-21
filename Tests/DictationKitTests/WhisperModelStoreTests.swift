import XCTest
@testable import DictationKit

final class WhisperModelStoreTests: XCTestCase {

    func testDefaultDirectoryIsUnderApplicationSupport() {
        let store = WhisperModelStore()
        XCTAssertTrue(store.directory.path.contains("Application Support"))
        XCTAssertTrue(store.directory.path.hasSuffix("whisprflow/models"))
    }

    func testModelURLUsesTheTurboFileName() {
        let store = WhisperModelStore()
        XCTAssertEqual(store.modelURL.lastPathComponent, "ggml-large-v3-turbo-q5_0.bin")
    }

    func testCustomDirectoryIsHonoured() {
        let dir = URL(fileURLWithPath: "/tmp/whisprflow-test-models")
        let store = WhisperModelStore(directory: dir)
        XCTAssertEqual(store.directory, dir)
        XCTAssertEqual(store.modelURL, dir.appendingPathComponent("ggml-large-v3-turbo-q5_0.bin"))
    }

    func testIsDownloadedFalseForEmptyDirectory() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = WhisperModelStore(directory: dir)
        XCTAssertFalse(store.isDownloaded)
    }
}
