import Foundation
import Observation

/// User-editable connection config. emberd's `/state` is open (reads), but
/// control calls need the API key. No address or key is baked in — set the
/// emberd address and API key once in Settings (both persist in UserDefaults).
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
        baseURL = UserDefaults.standard.string(forKey: Self.kURL) ?? ""
        apiKey = UserDefaults.standard.string(forKey: Self.kKey) ?? ""
    }

    var url: URL? { baseURL.isEmpty ? nil : URL(string: baseURL) }
    var hasKey: Bool { !apiKey.isEmpty }
}
