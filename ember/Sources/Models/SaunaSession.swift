import Foundation
import SwiftData

@Model
final class SaunaSession {
    var start: Date
    var end: Date
    var peakTempF: Int?
    var targetTempF: Int?
    var notes: String

    init(start: Date, end: Date, peakTempF: Int? = nil, targetTempF: Int? = nil, notes: String = "") {
        self.start = start
        self.end = end
        self.peakTempF = peakTempF
        self.targetTempF = targetTempF
        self.notes = notes
    }

    var durationSec: Int { max(0, Int(end.timeIntervalSince(start))) }
    var durationText: String {
        let m = durationSec / 60, s = durationSec % 60
        return m > 0 ? "\(m) min" : "\(s)s"
    }
}
