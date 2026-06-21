import ActivityKit
import Foundation

/// Shared between the app (start/update) and the widget extension (render).
struct SaunaActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        var currentTempF: Int
        var targetTempF: Int
        var heater: Bool
        var power: Bool
        /// When set, the lock-screen shows a self-updating in-session counter.
        var sessionStart: Date?
    }

    var label: String = "Sauna"
}
