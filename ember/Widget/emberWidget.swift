import ActivityKit
import SwiftUI
import WidgetKit

@main
struct emberWidgetBundle: WidgetBundle {
    var body: some Widget { SaunaLiveActivity() }
}

private let ember = Color(red: 1.0, green: 0.42, blue: 0.17)
private let amber = Color(red: 1.0, green: 0.70, blue: 0.24)

private typealias State = SaunaActivityAttributes.ContentState

/// Accent = the sauna's current LED color (shared ChromaPalette), or ember if none.
private func accent(_ s: State) -> Color { ChromaPalette.color(for: s.chromoColor) ?? ember }

private func preheat(_ s: State) -> Double {
    guard s.targetTempF > 75 else { return 0 }
    return max(0, min(1, Double(s.currentTempF - 75) / Double(s.targetTempF - 75)))
}

/// Mirrors the in-app status (heater is the authoritative on-signal; power = idle "On").
private func statusText(_ s: State) -> String {
    if s.heater {
        if s.targetTempF > 0 { return s.currentTempF >= s.targetTempF - 2 ? "READY" : "PREHEATING" }
        return "HEATING"
    }
    return s.power ? "ON" : "SAUNA"
}

@ViewBuilder private func chromoDot(_ s: State) -> some View {
    if let c = ChromaPalette.color(for: s.chromoColor) {
        Circle().fill(c).frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }
}

struct SaunaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SaunaActivityAttributes.self) { ctx in
            LockScreen(state: ctx.state)
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(accent(ctx.state))
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 9) {
                        MiniDial(state: ctx.state).frame(width: 42, height: 42)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(statusText(ctx.state)).font(.system(size: 10, weight: .bold)).tracking(1)
                                .foregroundStyle(ctx.state.heater ? amber : .secondary)
                            Text("\(ctx.state.currentTempF)°").font(.system(.title, design: .rounded, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TARGET").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text("\(ctx.state.targetTempF)°").font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                        chromoDot(ctx.state)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let start = ctx.state.sessionStart {
                        HStack {
                            Image(systemName: "timer").foregroundStyle(amber)
                            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                                .font(.system(.title3, design: .rounded, weight: .semibold)).foregroundStyle(.white)
                            Spacer()
                            Text("in session").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView(value: preheat(ctx.state)).tint(accent(ctx.state))
                    }
                }
            } compactLeading: {
                Image(systemName: ctx.state.heater ? "flame.fill" : "thermometer.medium")
                    .foregroundStyle(ctx.state.heater ? ember : accent(ctx.state))
            } compactTrailing: {
                Text("\(ctx.state.currentTempF)°")
                    .font(.system(.body, design: .rounded, weight: .semibold)).foregroundStyle(.white)
            } minimal: {
                Image(systemName: ctx.state.heater ? "flame.fill" : "thermometer.medium")
                    .foregroundStyle(accent(ctx.state))
            }
            .keylineTint(accent(ctx.state))
        }
    }
}

private struct LockScreen: View {
    let state: State
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Image("EmberIcon")
                    .resizable().scaledToFit()
                    .frame(width: 34, height: 34)
                Text("Ember")
                    .offset(y: -2)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 52)
            .padding(.trailing, 6)
            Dial(state: state).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(statusText(state)).font(.system(size: 11, weight: .bold)).tracking(1.4)
                        .foregroundStyle(state.heater ? amber : .secondary)
                    chromoDot(state)
                }
                Text("Target \(state.targetTempF)°")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(.white)
                if let start = state.sessionStart {
                    Label {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit()
                    } icon: { Image(systemName: "timer") }
                    .font(.system(.subheadline, design: .rounded, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct Dial: View {
    let state: State
    private let sweep = 0.75   // 270°
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: sweep)
                .stroke(.white.opacity(0.12), style: .init(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: sweep * preheat(state))
                .stroke(LinearGradient(colors: [amber, ember], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: .init(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(135))
            VStack(spacing: -1) {
                Image(systemName: state.heater ? "flame.fill" : "thermometer.medium")
                    .font(.system(size: 9)).foregroundStyle(state.heater ? ember : .secondary)
                Text("\(state.currentTempF)°")
                    .font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
        }
    }
}

private struct MiniDial: View {
    let state: State
    private let sweep = 0.75
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: sweep)
                .stroke(.white.opacity(0.12), style: .init(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: sweep * preheat(state))
                .stroke(LinearGradient(colors: [amber, ember], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: .init(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(135))
            Image(systemName: state.heater ? "flame.fill" : "thermometer.medium")
                .font(.system(size: 11)).foregroundStyle(state.heater ? ember : .secondary)
        }
    }
}
