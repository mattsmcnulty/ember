import Foundation
import Observation

/// User-editable connection config. emberd's `/state` is open (reads), but
/// control calls need the API key. Defaults point at the deployed Pi; the key
/// is left blank so it isn't committed — enter it once in Settings.
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
        baseURL = UserDefaults.standard.string(forKey: Self.kURL) ?? "http://192.168.1.50:8765"
        apiKey = UserDefaults.standard.string(forKey: Self.kKey) ?? ""
    }

    var url: URL? { URL(string: baseURL) }
    var hasKey: Bool { !apiKey.isEmpty }
}
