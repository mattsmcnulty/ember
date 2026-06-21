import ActivityKit
import Foundation

/// Owns the sauna Live Activity lifecycle. The activity is shown whenever the sauna is
/// heating OR a session is in progress, and removed otherwise — so turning the heater on
/// (from the app OR the physical panel) shows it, and turning it off removes it. It
/// registers APNs push tokens with emberd so temperature keeps updating when the app is closed.
@MainActor
final class SaunaActivityController {
    static let shared = SaunaActivityController()
    // ActivityKit is thread-safe and access here is main-serialized; opt out of Swift 6
    // region isolation so the Activity handle can cross to update/end.
    nonisolated(unsafe) private var activity: Activity<SaunaActivityAttributes>?
    private var settings: AppSettings?
    private var heaterOn = false
    private var sessionStart: Date?
    private var latest = SaunaState()
    private var startObserver: Task<Void, Never>?
    private var tokenObserver: Task<Void, Never>?

    /// Call once at launch. Wires the push-to-start token so emberd can begin a Live
    /// Activity for a preheat even if the app is closed (once emberd's APNs key is set).
    func configure(_ settings: AppSettings) {
        self.settings = settings
        guard startObserver == nil else { return }
        let updates = Activity<SaunaActivityAttributes>.pushToStartTokenUpdates
        startObserver = Task { [weak self] in
            for await data in updates {
                try? await self?.client?.registerPushToStartToken(Self.hex(data))
            }
        }
    }

    private var client: EmberClient? {
        guard let s = settings, let url = s.url else { return nil }
        return EmberClient(base: url, apiKey: s.apiKey)
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    private func makeState(_ s: SaunaState) -> SaunaActivityAttributes.ContentState {
        .init(currentTempF: s.currentTempF ?? 0, targetTempF: s.targetTempF ?? 0,
              heater: s.heater, power: s.power, sessionStart: sessionStart)
    }

    // MARK: inputs

    /// Called every poll with the real device state — drives the activity from the actual
    /// heater state, so panel-initiated on/off is reflected, and refreshes the live temp.
    func updateHeater(_ on: Bool, state: SaunaState) async {
        heaterOn = on
        latest = state
        await reconcile()
    }

    func beginSession(_ start: Date, state: SaunaState) async {
        sessionStart = start
        latest = state
        await reconcile()
    }

    func endSession(state: SaunaState) async {
        sessionStart = nil
        latest = state
        await reconcile()
    }

    // MARK: lifecycle

    private func reconcile() async {
        let shouldShow = heaterOn || sessionStart != nil
        let content = ActivityContent(state: makeState(latest),
                                      staleDate: Date().addingTimeInterval(120))
        if shouldShow {
            if activity == nil {
                guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
                activity = try? Activity.request(
                    attributes: SaunaActivityAttributes(), content: content, pushType: .token)
                observeToken()
            } else {
                await activity?.update(content)
            }
        } else if activity != nil {
            tokenObserver?.cancel(); tokenObserver = nil
            await activity?.end(nil, dismissalPolicy: .immediate)
            activity = nil
        }
    }

    private func observeToken() {
        tokenObserver?.cancel()
        guard let updates = activity?.pushTokenUpdates else { return }
        tokenObserver = Task { [weak self] in
            for await data in updates {
                try? await self?.client?.registerActivityToken(Self.hex(data))
            }
        }
    }
}
