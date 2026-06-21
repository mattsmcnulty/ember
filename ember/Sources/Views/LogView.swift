import SwiftData
import SwiftUI

struct LogView: View {
    @Environment(SaunaStore.self) private var store
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SaunaSession.start, order: .reverse) private var sessions: [SaunaSession]
    @AppStorage("activeSessionStart") private var activeStart: Double = 0

    private var inSession: Bool { activeStart > 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                sessionCard
                statsRow
                history
            }
            .padding(.horizontal, 18).padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: in/out

    private var sessionCard: some View {
        VStack(spacing: 18) {
            if inSession {
                let start = Date(timeIntervalSince1970: activeStart)
                VStack(spacing: 4) {
                    Text("IN SESSION").font(.system(.caption, design: .rounded, weight: .bold))
                        .tracking(2).foregroundStyle(Theme.amber)
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary).monospacedDigit()
                    if let t = store.state.currentTempF {
                        Text("\(t)°F  ·  \(store.state.heater ? "heating" : "idle")")
                            .font(.system(.subheadline, design: .rounded)).foregroundStyle(Theme.textSecondary)
                    }
                }
                bigButton(title: "Get Out", icon: "figure.walk.departure", filled: false) { getOut() }
            } else {
                Image(systemName: "figure.sauna")
                    .font(.system(size: 46)).foregroundStyle(Theme.textTertiary)
                    .padding(.top, 6)
                Text("Ready when you are")
                    .font(.system(.headline, design: .rounded)).foregroundStyle(Theme.textSecondary)
                bigButton(title: "Get In", icon: "figure.walk.arrival", filled: true) { getIn() }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24).padding(.horizontal, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Theme.stroke))
    }

    private func bigButton(title: String, icon: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity).frame(height: 60)
                .foregroundStyle(filled ? Theme.bg0 : Theme.textPrimary)
                .background {
                    if filled { RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Theme.emberGradient) }
                    else { RoundedRectangle(cornerRadius: 19, style: .continuous).fill(Color.white.opacity(0.07))
                        .overlay(RoundedRectangle(cornerRadius: 19, style: .continuous).strokeBorder(Theme.stroke)) }
                }
                .emberGlow(Theme.ember, radius: 16, active: filled)
        }.buttonStyle(.plain)
    }

    private func getIn() {
        Haptics.success()
        activeStart = Date().timeIntervalSince1970
        Task {
            await store.beginSession()
            await SaunaActivityController.shared.start(state: store.state, sessionStart: Date(timeIntervalSince1970: activeStart))
        }
    }

    private func getOut() {
        Haptics.success()
        let start = Date(timeIntervalSince1970: activeStart)
        let end = Date()
        activeStart = 0
        Task {
            let result = await store.endSession()
            let session = SaunaSession(start: start, end: end,
                                       peakTempF: result?.peakTempF ?? store.state.currentTempF,
                                       targetTempF: store.state.targetTempF)
            ctx.insert(session)
            try? ctx.save()
            await HealthKitManager.shared.log(start: start, end: end, peakTempF: session.peakTempF)
            await SaunaActivityController.shared.end()
        }
    }

    // MARK: stats

    private var statsRow: some View {
        HStack(spacing: 12) {
            stat("\(sessions.count)", "sessions")
            stat("\(sessions.reduce(0) { $0 + $1.durationSec } / 60)", "minutes")
            stat(streakText, "day streak")
        }
    }
    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(.caption, design: .rounded)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
    }
    private var streakText: String {
        let days = Set(sessions.map { Calendar.current.startOfDay(for: $0.start) })
        var streak = 0
        var day = Calendar.current.startOfDay(for: Date())
        while days.contains(day) {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return "\(streak)"
    }

    // MARK: history

    @ViewBuilder private var history: some View {
        if sessions.isEmpty {
            Text("Your sessions will appear here.")
                .font(.system(.subheadline, design: .rounded)).foregroundStyle(Theme.textTertiary)
                .padding(.top, 24)
        } else {
            VStack(spacing: 0) {
                ForEach(sessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.start, format: .dateTime.weekday().month().day())
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(session.start, format: .dateTime.hour().minute())
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        if let p = session.peakTempF {
                            Label("\(p)°", systemImage: "flame.fill")
                                .font(.system(.caption, design: .rounded)).foregroundStyle(Theme.ember)
                        }
                        Text(session.durationText)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary).frame(minWidth: 64, alignment: .trailing)
                    }
                    .padding(.vertical, 14)
                    if session.id != sessions.last?.id { Divider().overlay(Theme.stroke) }
                }
            }
            .padding(.horizontal, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke))
        }
    }
}
