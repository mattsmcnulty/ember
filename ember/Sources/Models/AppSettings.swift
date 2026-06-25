import Foundation
import Observation

/// User-editable connection config. A value entered in Settings persists in
/// UserDefaults and wins; otherwise the app falls back to the build-time default
/// injected from the gitignored Local.xcconfig (empty in a clean checkout — set it
/// in Settings instead). emberd's `/state` is open; control calls need the API key.
@MainActor
@Observable
final class AppSettings {
    var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Self.kURL) }
    }
    var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Self.kKey) }
    }

    private static let kURL = "emberd.baseURL"
    private static let kKey = "emberd.apiKey"

    init() {
        baseURL = UserDefaults.standard.string(forKey: Self.kURL) ?? Self.buildDefault("EMBERDDefaultURL")
        apiKey = UserDefaults.standard.string(forKey: Self.kKey) ?? Self.buildDefault("EMBERDDefaultAPIKey")
    }

    /// Default injected at build time from the gitignored Local.xcconfig (via Info.plist).
    /// Empty in a clean checkout; used only until a value is saved in Settings.
    private static func buildDefault(_ key: String) -> String {
        ((Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? "")
            .trimmingCharacters(in: .whitespaces)
    }

    var url: URL? { baseURL.isEmpty ? nil : URL(string: baseURL) }
    var hasKey: Bool { !apiKey.isEmpty }
}
