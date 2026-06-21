import Foundation
import HealthKit

/// Logs each sauna session to Apple Health as an `.other` workout (+ Mindful
/// Minutes). Best-effort: silently no-ops if HealthKit is unavailable or denied.
final class HealthKitManager: @unchecked Sendable {
    static let shared = HealthKitManager()
    private let store = HKHealthStore()

    func requestAuth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var share: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) { share.insert(mindful) }
        try? await store.requestAuthorization(toShare: share, read: [])
    }

    func log(start: Date, end: Date, peakTempF: Int?) async {
        guard HKHealthStore.isHealthDataAvailable(), end > start else { return }
        await requestAuth()

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            var meta: [String: Any] = ["EmberSession": true, "SessionType": "Infrared Sauna"]
            if let p = peakTempF { meta["PeakTemperatureF"] = p }
            try await builder.addMetadata(meta)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch { /* denied / unavailable — fine */ }

        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            let sample = HKCategorySample(type: mindful,
                                          value: HKCategoryValue.notApplicable.rawValue,
                                          start: start, end: end)
            try? await store.save(sample)
        }
    }
}
