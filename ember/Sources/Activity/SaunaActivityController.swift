import ActivityKit
import Foundation

/// Manages the sauna Live Activity. Starts on Get In, updates from foreground
/// polling, ends on Get Out. (Background/closed updates arrive once APNs is wired.)
@MainActor
final class SaunaActivityController {
    static let shared = SaunaActivityController()
    // ActivityKit is thread-safe and all access here is main-serialized; opt out of
    // Swift 6 region isolation so the Activity handle can cross to update/end.
    nonisolated(unsafe) private var activity: Activity<SaunaActivityAttributes>?
    private var sessionStart: Date?

    private func makeState(_ s: SaunaState) -> SaunaActivityAttributes.ContentState {
        .init(currentTempF: s.currentTempF ?? 0, targetTempF: s.targetTempF ?? 0,
              heater: s.heater, power: s.power, sessionStart: sessionStart)
    }

    func start(state: SaunaState, sessionStart: Date?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        self.sessionStart = sessionStart
        let content = ActivityContent(state: makeState(state),
                                      staleDate: Date().addingTimeInterval(120))
        if activity != nil {              // already running — just update
            await activity?.update(content)
            return
        }
        activity = try? Activity.request(
            attributes: SaunaActivityAttributes(),
            content: content,
            pushType: nil)                // .token later, once emberd has an APNs key
    }

    /// Called from polling — updates the live value if an activity is running.
    func sync(_ state: SaunaState) async {
        guard activity != nil else { return }
        await activity?.update(ActivityContent(state: makeState(state),
                                               staleDate: Date().addingTimeInterval(120)))
    }

    func end() async {
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        sessionStart = nil
    }
}
