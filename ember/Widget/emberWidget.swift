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
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 6)
                Circle().trim(from: 0, to: preheat(state))
                    .stroke(LinearGradient(colors: [amber, ember], startPoint: .top, endPoint: .bottom),
                            style: .init(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: state.heater ? "flame.fill" : "thermometer.medium")
                    .font(.title3).foregroundStyle(state.heater ? ember : .secondary)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.currentTempF)°")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(state.heater ? "Heating to \(state.targetTempF)°" : "Target \(state.targetTempF)°")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let start = state.sessionStart {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.white).monospacedDigit()
                    Text("in session").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
