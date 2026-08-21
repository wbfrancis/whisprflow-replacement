import XCTest
@testable import DictationKit

final class SettingsStoreTests: XCTestCase {

    /// A throwaway defaults domain so tests don't touch the real app preferences.
    private func scratchDefaults() -> UserDefaults {
        let suite = "SettingsStoreTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testLoadReturnsDefaultsWhenNothingStored() {
        let store = SettingsStore(defaults: scratchDefaults())
        XCTAssertEqual(store.load(), Settings())
    }

    func testSavedSettingsRoundTrip() {
        let store = SettingsStore(defaults: scratchDefaults())
        let custom = Settings(activationKey: .leftCommand, mode: .toggle, restoreClipboard: false)
        store.save(custom)
        XCTAssertEqual(store.load(), custom)
    }

    func testSettingsSurviveANewStoreOnTheSameDefaults() {
        let defaults = scratchDefaults()
        let custom = Settings(activationKey: .rightControl, mode: .toggle, restoreClipboard: false)
        SettingsStore(defaults: defaults).save(custom)

        // A fresh store over the same domain models an app restart.
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), custom)
    }

    func testEachFieldPersistsIndependently() {
        let store = SettingsStore(defaults: scratchDefaults())
        store.save(Settings(activationKey: .leftOption, mode: .pushToTalk, restoreClipboard: false))
        let loaded = store.load()
        XCTAssertEqual(loaded.activationKey, .leftOption)
        XCTAssertEqual(loaded.mode, .pushToTalk)
        XCTAssertFalse(loaded.restoreClipboard)
    }

    func testCorruptDataFallsBackToDefaults() {
        let defaults = scratchDefaults()
        defaults.set(Data("not json".utf8), forKey: "settings.v1")
        XCTAssertEqual(SettingsStore(defaults: defaults).load(), Settings(),
                       "undecodable stored data must not brick the app")
    }
}
