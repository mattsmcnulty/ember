import SwiftUI

struct ControlView: View {
    @Environment(SaunaStore.self) private var store
    private var s: SaunaState { store.state }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ConnectionBar()
                HeroGauge(state: s)
                    .padding(.top, 4)
                StartStopButton()
                TargetCard(state: s)
                TimerCard(state: s)
                LightsCard(state: s)
                SonosCard()
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .animation(.snappy(duration: 0.35), value: s)
    }
}

// MARK: - Connection / status

private struct ConnectionBar: View {
    @Environment(SaunaStore.self) private var store
    var body: some View {
        HStack(spacing: 8) {
            statusPill
            Spacer()
            if !store.reachable {
                Pill(text: "Offline", color: Theme.emberHot)
            } else if store.stale {
                Pill(text: "Stale", color: .yellow)
            }
        }
        .padding(.top, 4)
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = {
            switch store.state.status {
            case .off: return ("Off", Theme.textSecondary)
            case .preheating: return ("Preheating", Theme.amber)
            case .ready: return ("Ready", Theme.ember)
            case .heating: return ("Heating", Theme.ember)
            case .idleWarm: return ("Warm", Theme.amber)
            }
        }()
        return Pill(text: text, color: color, filled: store.state.status == .ready)
    }
}

// MARK: - Hero gauge

private struct HeroGauge: View {
    let state: SaunaState
    private let sweep = 0.75            // 270°
    private let floorF = 75.0, ceilF = 175.0

    private func frac(_ f: Int?) -> Double {
        guard let f else { return 0 }
        return max(0, min(1, (Double(f) - floorF) / (ceilF - floorF)))
    }

    var body: some View {
        let curFrac = frac(state.currentTempF)
        let heat = Theme.heatColor(state.heatRatio)
        ZStack {
            // track
            Circle().trim(from: 0, to: sweep)
                .stroke(Color.white.opacity(0.07), style: .init(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(135))
            // fill — hue tracks actual heat (cool when cold → ember when hot)
            Circle().trim(from: 0, to: sweep * curFrac)
                .stroke(LinearGradient(colors: [heat.mix(Theme.amber, 0.35), heat],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: .init(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(135))
                .emberGlow(heat, radius: 24, active: curFrac > 0.05)
            // target marker
            TargetTick(progress: sweep * frac(state.targetTempF))
                .rotationEffect(.degrees(135))

            VStack(spacing: 2) {
                Image(systemName: state.heater ? "flame.fill" : "thermometer.medium")
                    .font(.title2)
                    .foregroundStyle(state.heater ? AnyShapeStyle(Theme.emberGradient) : AnyShapeStyle(Theme.textTertiary))
                    .emberGlow(Theme.ember, radius: 10, active: state.heater)
                Text(state.currentTempF.map { "\($0)" } ?? "—")
                    .font(.system(size: 88, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(state.currentTempF ?? 0)))
                    .monospacedDigit()
                Text("°F").font(.system(.title3, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.textSecondary).offset(y: -8)
                Text("target \(state.targetTempF ?? 0)°")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(height: 300)
        .padding(.horizontal, 8)
    }
}

private struct TargetTick: Shape {
    let progress: Double  // 0…0.75 around the circle
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(rect.width, rect.height) / 2 - 9
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let angle = Angle.degrees(progress * 360).radians
        let a = CGPoint(x: center.x + cos(angle) * (r - 12), y: center.y + sin(angle) * (r - 12))
        let b = CGPoint(x: center.x + cos(angle) * (r + 12), y: center.y + sin(angle) * (r + 12))
        p.move(to: a); p.addLine(to: b)
        return p.strokedPath(.init(lineWidth: 3, lineCap: .round))
    }
}

// MARK: - Start / Stop

private struct StartStopButton: View {
    @Environment(SaunaStore.self) private var store
    var body: some View {
        let heating = store.state.heater
        Button {
            Task { heating ? await store.stop() : await store.start() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: heating ? "stop.fill" : "flame.fill")
                Text(heating ? "Stop" : "Start Heating")
                    .font(.system(.title3, design: .rounded, weight: .bold))
            }
            .frame(maxWidth: .infinity).frame(height: 62)
            .foregroundStyle(heating ? Theme.textPrimary : Theme.bg0)
            .background {
                if heating {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.stroke))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.emberGradient)
                }
            }
            .emberGlow(Theme.ember, radius: 18, active: !heating)
        }
        .buttonStyle(.plain)
        .disabled(store.busy)
        .opacity(store.busy ? 0.7 : 1)
    }
}

// MARK: - Target temperature

private struct TargetCard: View {
    @Environment(SaunaStore.self) private var store
    let state: SaunaState
    var body: some View {
        HStack {
            Label("Target", systemImage: "target").foregroundStyle(Theme.textSecondary)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Spacer()
            stepButton("minus") { Task { await store.nudgeTarget(-1) } }
            Text("\(state.targetTempF ?? 150)°")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary).monospacedDigit()
                .frame(minWidth: 78)
                .contentTransition(.numericText(value: Double(state.targetTempF ?? 0)))
            stepButton("plus") { Task { await store.nudgeTarget(1) } }
        }
        .glassCard()
    }
    private func stepButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3.weight(.bold)).foregroundStyle(Theme.ember)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.ember.opacity(0.14)))
        }.buttonStyle(.plain)
    }
}

// MARK: - Timer

private struct TimerCard: View {
    @Environment(SaunaStore.self) private var store
    let state: SaunaState
    private let presets = [15, 30, 45, 60]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Timer", systemImage: "timer").foregroundStyle(Theme.textSecondary)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                if let rem = state.timerRemainingMin, state.heater {
                    Text("\(rem) min left").font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.amber)
                }
            }
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { m in
                    let on = state.timerSetMin == m
                    Button { Task { await store.setTimer(m) } } label: {
                        Text("\(m)m").font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .foregroundStyle(on ? Theme.bg0 : Theme.textPrimary)
                            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(on ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Color.white.opacity(0.06))))
                    }.buttonStyle(.plain)
                }
            }
        }
        .glassCard()
    }
}

// MARK: - Lights

private struct LightsCard: View {
    @Environment(SaunaStore.self) private var store
    let state: SaunaState
    private let colors: [(String, Color)] = [
        ("mode", .white), ("mode1", Color(hex: 0xFFD23E)), ("mode2", Color(hex: 0xFF4D4D)),
        ("mode3", Color(hex: 0xB061FF)), ("mode4", Color(hex: 0x4D7CFF)), ("mode5", Color(hex: 0x49D6FF)),
        ("mode6", Color(hex: 0x49E06B)), ("mode7", Color(hex: 0xFF8A3D)), ("mode8", Color(hex: 0xFF5FA2)),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Lighting", systemImage: "lightbulb.led").foregroundStyle(Theme.textSecondary)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            HStack(spacing: 10) {
                ForEach(colors, id: \.0) { value, color in
                    let on = state.chromoColor == value && !state.chromoCycle
                    Button { Task { await store.setChromo(value) } } label: {
                        Circle().fill(color)
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white.opacity(on ? 0.9 : 0.12), lineWidth: on ? 2.5 : 1))
                            .scaleEffect(on ? 1.12 : 1)
                            .emberGlow(color, radius: 8, active: on)
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                Toggle(isOn: Binding(get: { state.chromoCycle }, set: { v in Task { await store.setChromoCycle(v) } })) {
                    Label("Rainbow", systemImage: "sparkles")
                }
                .toggleStyle(PillToggle())
                Toggle(isOn: Binding(get: { state.footwell }, set: { v in Task { await store.setFootwell(v) } })) {
                    Label("Footwell", systemImage: "light.min")
                }
                .toggleStyle(PillToggle())
            }
        }
        .glassCard()
    }
}

private struct PillToggle: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        Button { c.isOn.toggle() } label: {
            c.label.font(.system(.subheadline, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity).frame(height: 44)
                .foregroundStyle(c.isOn ? Theme.bg0 : Theme.textPrimary)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(c.isOn ? AnyShapeStyle(Theme.amber) : AnyShapeStyle(Color.white.opacity(0.06))))
        }.buttonStyle(.plain)
    }
}

// MARK: - Sonos

private struct SonosCard: View {
    @Environment(SaunaStore.self) private var store
    @State private var volume = 30.0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sauna Speaker", systemImage: "hifispeaker.fill").foregroundStyle(Theme.textSecondary)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            HStack(spacing: 22) {
                ctl("backward.fill") { Task { await store.audio("prev") } }
                ctl("playpause.fill") { Task { await store.audio("play") } }
                ctl("forward.fill") { Task { await store.audio("next") } }
                Spacer()
            }
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(Theme.textTertiary)
                Slider(value: $volume, in: 0...100, step: 1) { editing in
                    if !editing { Task { await store.audio("volume", volume: Int(volume)) } }
                }.tint(Theme.amber)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(Theme.textTertiary)
            }
        }
        .glassCard()
    }
    private func ctl(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.textPrimary)
        }.buttonStyle(.plain)
    }
}
