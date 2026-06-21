import Foundation
import Observation

/// Owns live sauna state: polls emberd, exposes control actions with optimistic
/// updates that reconcile against the server response.
@MainActor
@Observable
final class SaunaStore {
    private let settings: AppSettings
    var state = SaunaState()
    var reachable = false
    var lastError: String?
    var busy = false

    private var pollTask: Task<Void, Never>?
    private var controlEpoch = 0   // bumped by every control; a poll started before a control is discarded

    init(settings: AppSettings) { self.settings = settings }

    private var client: EmberClient? {
        guard let url = settings.url else { return nil }
        return EmberClient(base: url, apiKey: settings.apiKey)
    }

    var stale: Bool { reachable && Date().timeIntervalSince1970 - state.updatedAt > 20 }

    // MARK: polling
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                if self?.busy == false { await self?.refresh() }  // don't fight an in-flight control
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
    func stopPolling() { pollTask?.cancel(); pollTask = nil }

    func refresh() async {
        guard let client else { reachable = false; lastError = "Set the emberd address in Settings"; return }
        let epoch = controlEpoch
        do {
            let s = try await client.state()
            guard epoch == controlEpoch else { return }   // a control superseded this fetch — drop it
            state = s
            reachable = true
            lastError = nil
            await SaunaActivityController.shared.updateHeater(s.heater, state: s)
        } catch {
            guard epoch == controlEpoch else { return }
            reachable = false
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    // MARK: control
    private func control(_ req: ControlRequest, _ optimistic: (inout SaunaState) -> Void) async {
        guard let client else { return }
        controlEpoch += 1                         // invalidate any poll already in flight
        var s = state; optimistic(&s); state = s
        busy = true; defer { busy = false }
        do {
            let result = try await client.control(req)
            controlEpoch += 1                      // and any poll that raced during the call
            state = result
            lastError = nil
        } catch {
            controlEpoch += 1
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            await refresh()
        }
    }

    /// "Start" powers on + heats; "Stop" turns the heater off.
    func start() async {
        Haptics.success()
        await control(.init(power: true, heater: true)) { $0.power = true; $0.heater = true }
        await SaunaActivityController.shared.updateHeater(state.heater, state: state)  // preheat dial on the Lock Screen
    }
    func stop() async {
        Haptics.toggle()
        await control(.init(power: false, heater: false)) { $0.power = false; $0.heater = false }
        await SaunaActivityController.shared.updateHeater(state.heater, state: state)  // ends unless mid-session
    }
    func setPower(_ on: Bool) async { Haptics.toggle(); await control(.init(power: on)) { $0.power = on } }
    func setHeater(_ on: Bool) async { Haptics.toggle(); await control(.init(heater: on)) { $0.heater = on } }
    func setTarget(_ f: Int) async { await control(.init(targetTempF: f)) { $0.targetTempF = f } }
    func setTimer(_ m: Int) async { Haptics.tap(); await control(.init(timerMin: m)) { $0.timerSetMin = m } }
    func setChromo(_ v: String) async { Haptics.tap(); await control(.init(chromoColor: v)) { $0.chromoColor = v } }
    func setChromoCycle(_ on: Bool) async { Haptics.tap(); await control(.init(chromoCycle: on)) { $0.chromoCycle = on } }
    func setFootwell(_ on: Bool) async { Haptics.toggle(); await control(.init(footwell: on)) { $0.footwell = on } }

    func nudgeTarget(_ delta: Int) async {
        let v = max(60, min(175, (state.targetTempF ?? 150) + delta))
        Haptics.tap(); await setTarget(v)
    }

    /// The "Get In" scene: footwell light off, chromotherapy red, 25-minute timer.
    func getInScene() async {
        await control(.init(timerMin: 25, chromoColor: "mode2", footwell: false)) {
            $0.timerSetMin = 25; $0.chromoColor = "mode2"; $0.footwell = false
        }
    }

    // MARK: audio + session
    func audio(_ action: String, volume: Int? = nil) async {
        guard let client else { return }
        Haptics.tap(); try? await client.audio(action: action, volume: volume)
    }
    func beginSession() async { try? await client?.sessionStart() }
    func endSession() async -> SessionResult? { try? await client?.sessionEnd() }
}
