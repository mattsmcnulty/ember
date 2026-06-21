import ActivityKit
import SwiftUI
import WidgetKit

@main
struct emberWidgetBundle: WidgetBundle {
    var body: some Widget { SaunaLiveActivity() }
}

private let ember = Color(red: 1.0, green: 0.42, blue: 0.17)
private let amber = Color(red: 1.0, green: 0.70, blue: 0.24)

struct SaunaLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SaunaActivityAttributes.self) { ctx in
            LockScreen(state: ctx.state)
                .activityBackgroundTint(.black.opacity(0.55))
                .activitySystemActionForegroundColor(ember)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("\(ctx.state.currentTempF)°")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                    } icon: {
                        Image(systemName: ctx.state.heater ? "flame.fill" : "thermometer.medium")
                            .foregroundStyle(ember)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("TARGET").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                        Text("\(ctx.state.targetTempF)°").font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let start = ctx.state.sessionStart {
                        HStack {
                            Image(systemName: "timer").foregroundStyle(amber)
                            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer()
                            Text("in session").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView(value: preheat(ctx.state))
                            .tint(ember)
                    }
                }
            } compactLeading: {
                Image(systemName: ctx.state.heater ? "flame.fill" : "thermometer.medium")
                    .foregroundStyle(ember)
            } compactTrailing: {
                Text("\(ctx.state.currentTempF)°")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "flame.fill").foregroundStyle(ember)
            }
            .keylineTint(ember)
        }
    }
}

private func preheat(_ s: SaunaActivityAttributes.ContentState) -> Double {
    guard s.targetTempF > 75 else { return 0 }
    return max(0, min(1, Double(s.currentTempF - 75) / Double(s.targetTempF - 75)))
}

private struct LockScreen: View {
    let state: SaunaActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 16) {
            Dial(state: state).frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 6) {
                Text(state.heater ? "HEATING" : "SAUNA")
                    .font(.system(size: 11, weight: .bold)).tracking(1.6)
                    .foregroundStyle(state.heater ? amber : .secondary)
                Text("Target \(state.targetTempF)°")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                if let start = state.sessionStart {
                    Label {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit()
                    } icon: { Image(systemName: "timer") }
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct Dial: View {
    let state: SaunaActivityAttributes.ContentState
    private let sweep = 0.75   // 270°
    var body: some View {
        ZStack {
            Circle().trim(from: 0, to: sweep)
                .stroke(.white.opacity(0.12), style: .init(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: sweep * preheat(state))
                .stroke(LinearGradient(colors: [amber, ember], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: .init(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
            VStack(spacing: -1) {
                Image(systemName: state.heater ? "flame.fill" : "thermometer.medium")
                    .font(.caption2).foregroundStyle(state.heater ? ember : .secondary)
                Text("\(state.currentTempF)°")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }
}
