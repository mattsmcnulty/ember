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
    private(set) var busy = false
    /// Self-ticking countdown anchor for the heat timer (nil = no timer running).
    private(set) var timerDeadline: Date?

    private var pollTask: Task<Void, Never>?
    private var controlEpoch = 0   // bumped by every control; a poll started before a control is discarded
    private var targetSendTask: Task<Void, Never>?   // debounces rapid temp-stepper taps into one write
    // busy is a *count* of in-flight controls: overlapping controls must not clear each
    // other's flag early, or a poll slips in and clobbers a still-pending optimistic write.
    private var busyCount = 0 { didSet { busy = busyCount > 0 } }
    private var nudgeHoldsBusy = false   // the stepper holds ONE busy increment across its debounce
    private var pollFailures = 0
    private var lastSuccessfulPollAt: Date?

    init(settings: AppSettings) { self.settings = settings }

    private var client: EmberClient? {
        guard let url = settings.url else { return nil }
        return EmberClient(base: url, apiKey: settings.apiKey)
    }

    private func beginBusy() { busyCount += 1 }
    private func endBusy() { busyCount = max(0, busyCount - 1) }

    // Keyed off the *client* clock (last poll that succeeded), not the server's
    // updatedAt — the Pi has no RTC, so its wall clock can't be trusted.
    var stale: Bool { reachable && Date().timeIntervalSince(lastSuccessfulPollAt ?? .distantPast) > 20 }

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
            reconcileTimerDeadline(with: s)
            pollFailures = 0
            reachable = true
            lastSuccessfulPollAt = Date()
            lastError = nil
            await SaunaActivityController.shared.updateHeater(s.heater, state: s)
        } catch {
            guard epoch == controlEpoch else { return }
            // one slow/failed poll shouldn't flash "Offline" — require consecutive failures
            pollFailures += 1
            if pollFailures >= 2 { reachable = false }
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Anchor a Date-based countdown to the polled whole-minute remaining, re-anchoring
    /// only on real drift (DP105 has 1-min resolution — re-anchoring every poll would
    /// wobble the displayed countdown by up to 59s).
    private func reconcileTimerDeadline(with s: SaunaState) {
        guard s.heater, let rem = s.timerRemainingMin, rem > 0 else { timerDeadline = nil; return }
        let implied = timerDeadline.map { Int(($0.timeIntervalSinceNow / 60).rounded(.up)) }
        if implied == nil || abs(implied! - rem) > 1 {
            timerDeadline = Date().addingTimeInterval(TimeInterval(rem) * 60)
        }
    }

    // MARK: control
    private func control(_ req: ControlRequest, _ optimistic: (inout SaunaState) -> Void) async {
        guard let client else { return }
        controlEpoch += 1
        let epoch = controlEpoch                   // this control's generation
        var s = state; optimistic(&s); state = s
        beginBusy(); defer { endBusy() }
        do {
            let result = try await client.control(req)
            guard epoch == controlEpoch else { return }   // a newer control/nudge superseded this — don't clobber
            state = result
            reconcileTimerDeadline(with: result)
            lastError = nil
        } catch {
            guard epoch == controlEpoch else { return }
            lastError = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            await refresh()
        }
    }

    /// "Start" powers on + heats; "Stop" turns the heater off.
    func start() async {
        Haptics.success()
        // power on + heat, with white interior during preheat (color applied last so it sticks)
        await control(.init(power: true, heater: true, chromoColor: "mode", footwell: true)) {
            $0.power = true; $0.heater = true; $0.chromoColor = "mode"; $0.footwell = true
        }
        await SaunaActivityController.shared.updateHeater(state.heater, state: state)  // preheat dial on the Lock Screen
    }
    func stop() async {
        Haptics.toggle()
        await control(.init(power: false, heater: false)) { $0.power = false; $0.heater = false }  // Stop = full off; Power toggle is the independent override
        await SaunaActivityController.shared.updateHeater(state.heater, state: state)  // ends unless mid-session
    }
    func setPower(_ on: Bool) async {
        Haptics.toggle()
        if on { await control(.init(power: true)) { $0.power = true } }
        else { await control(.init(power: false, heater: false)) { $0.power = false; $0.heater = false } }  // power off also stops heat
        await SaunaActivityController.shared.updateHeater(state.heater, state: state)
    }
    func setHeater(_ on: Bool) async { Haptics.toggle(); await control(.init(heater: on)) { $0.heater = on } }
    func setTarget(_ f: Int) async { await control(.init(targetTempF: f)) { $0.targetTempF = f } }
    func setTimer(_ m: Int) async {
        Haptics.tap()
        if m > 0, state.heater { timerDeadline = Date().addingTimeInterval(TimeInterval(m) * 60) }  // optimistic countdown
        await control(.init(timerMin: m)) { $0.timerSetMin = m; $0.timerRemainingMin = m }
    }
    func setChromo(_ v: String) async { Haptics.tap(); await control(.init(chromoColor: v)) { $0.chromoColor = v } }
    func setChromoCycle(_ on: Bool) async { Haptics.tap(); await control(.init(chromoCycle: on)) { $0.chromoCycle = on } }
    func setFootwell(_ on: Bool) async { Haptics.toggle(); await control(.init(footwell: on)) { $0.footwell = on } }

    /// Rapid +/- taps update the UI instantly but coalesce into one write, so they don't race
    /// each other (out-of-order responses used to make the value "not stick").
    func nudgeTarget(_ delta: Int) async {
        let v = max(60, min(175, (state.targetTempF ?? 150) + delta))
        state.targetTempF = v          // optimistic, instant
        controlEpoch += 1               // invalidate any in-flight poll so it can't clobber this
        if !nudgeHoldsBusy {            // hold ONE busy increment across the whole adjust burst
            nudgeHoldsBusy = true
            beginBusy()
        }
        Haptics.tap()
        targetSendTask?.cancel()
        targetSendTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard let self, !Task.isCancelled else { return }
            await self.setTarget(self.state.targetTempF ?? v)   // single write to emberd
            self.nudgeHoldsBusy = false
            self.endBusy()
        }
    }

    /// The "Get In" scene: interior lights on, chromotherapy red (mode3), 25-minute timer.
    func getInScene() async {
        await control(.init(timerMin: 25, chromoColor: "mode3", footwell: true)) {
            $0.timerSetMin = 25; $0.chromoColor = "mode3"; $0.footwell = true
        }
    }

    // MARK: audio + session
    func audio(_ action: String, volume: Int? = nil) async {
        guard let client else { return }
        Haptics.tap(); try? await client.audio(action: action, volume: volume)
    }
    /// Current speaker volume, for seeding the slider (nil if Sonos is unreachable).
    func audioVolume() async -> Int? {
        guard let client else { return nil }
        return (try? await client.audioState())?.volume
    }
    func beginSession() async { try? await client?.sessionStart() }
    func endSession() async -> SessionResult? { try? await client?.sessionEnd() }
}
