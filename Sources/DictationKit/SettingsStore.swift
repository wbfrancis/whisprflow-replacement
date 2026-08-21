import Foundation

/// Persists `Settings` across restarts as JSON in `UserDefaults`. Loading always yields a
/// usable value — defaults when nothing is stored or the stored data can't be decoded (a
/// format change shouldn't brick the app), so callers never handle a load error.
public struct SettingsStore {
    private let defaults: UserDefaults
    private let storageKey = "settings.v1"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Settings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return settings
    }

    public func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
