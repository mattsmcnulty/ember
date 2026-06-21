import ActivityKit
import Foundation

/// Manages the sauna Live Activity. Starts on heat-on / Get In, registers its APNs
/// push tokens with emberd (so emberd pushes temperature even when the app is closed),
/// updates from foreground polling, and ends on heat-off / Get Out.
@MainActor
final class SaunaActivityController {
    static let shared = SaunaActivityController()
    // ActivityKit is thread-safe and access here is main-serialized; opt out of Swift 6
    // region isolation so the Activity handle can cross to update/end.
    nonisolated(unsafe) private var activity: Activity<SaunaActivityAttributes>?
    private var sessionStart: Date?
    private var settings: AppSettings?
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

    func start(state: SaunaState, sessionStart: Date?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let sessionStart { self.sessionStart = sessionStart }  // nil = preserve existing
        let content = ActivityContent(state: makeState(state),
                                      staleDate: Date().addingTimeInterval(120))
        if activity != nil {                  // already running — just update
            await activity?.update(content)
            return
        }
        activity = try? Activity.request(
            attributes: SaunaActivityAttributes(), content: content, pushType: .token)
        observeToken()
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

    /// Called from polling — updates the live value if an activity is running.
    func sync(_ state: SaunaState) async {
        guard activity != nil else { return }
        await activity?.update(ActivityContent(state: makeState(state),
                                               staleDate: Date().addingTimeInterval(120)))
    }

    func end() async {
        tokenObserver?.cancel(); tokenObserver = nil
        await activity?.end(nil, dismissalPolicy: .immediate)
        activity = nil
        sessionStart = nil
    }

    /// Stop-heating ends the activity only when no session is in progress (so you can
    /// stop the heat mid-session and keep the Lock-Screen counter).
    func endIfNoSession() async {
        if sessionStart == nil { await end() }
    }
}
