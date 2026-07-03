import ActivityKit
import Foundation

/// Shared between the app (start/update) and the widget extension (render).
struct SaunaActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        var currentTempF: Int
        var targetTempF: Int
        var heater: Bool
        var power: Bool
        /// Current LED color (DP21 value) for the chroma accent; nil = no solid color.
        var chromoColor: String?
        /// When set, the lock-screen shows a self-updating in-session counter.
        /// Unix epoch seconds, not a Date: ActivityKit decodes APNs content-state with a
        /// default JSONDecoder (reference-date seconds), so a raw Date from the server
        /// would silently decode 31 years off. A plain epoch Double is the same on both
        /// sides and greppable in emberd's payload.
        var sessionStartEpoch: Double?
        var sessionStart: Date? { sessionStartEpoch.map(Date.init(timeIntervalSince1970:)) }
    }

    var label: String = "Sauna"
}
