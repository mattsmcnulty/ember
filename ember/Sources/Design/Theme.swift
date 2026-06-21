import SwiftUI
import UIKit

/// ember design system — warm, dark-first, premium. Charcoal surfaces, glowing
/// amber→orange→red heat, SF Rounded numerals, system materials.
enum Theme {
    // Surfaces (warm near-black)
    static let bg0 = Color(hex: 0x0C0A09)
    static let bg1 = Color(hex: 0x16110E)
    static let stroke = Color.white.opacity(0.08)

    // Heat palette
    static let amber = Color(hex: 0xFFB23E)
    static let ember = Color(hex: 0xFF6A2C)
    static let emberHot = Color(hex: 0xFF3B2E)
    static let cool = Color(hex: 0x6FA8FF)   // idle / cold accent

    // Text
    static let textPrimary = Color(hex: 0xF7F0EA)
    static let textSecondary = Color(hex: 0xA39891)
    static let textTertiary = Color(hex: 0x6E635D)

    static let emberGradient = LinearGradient(
        colors: [amber, ember, emberHot], startPoint: .topLeading, endPoint: .bottomTrailing)

    static var background: some View {
        RadialGradient(colors: [Color(hex: 0x1C1410), bg0],
                       center: .top, startRadius: 8, endRadius: 720)
            .overlay(LinearGradient(colors: [.clear, bg0], startPoint: .center, endPoint: .bottom))
            .ignoresSafeArea()
    }

    /// Interpolate cool → amber → ember → hot by how warm the sauna is (0…1).
    static func heatColor(_ t: Double) -> Color {
        let x = max(0, min(1, t))
        let stops: [(Double, Color)] = [(0, cool), (0.18, Color(hex: 0xC9A66B)),
                                        (0.45, amber), (0.75, ember), (1, emberHot)]
        for i in 1..<stops.count where x <= stops[i].0 {
            let (a, b) = (stops[i - 1], stops[i])
            let f = (x - a.0) / (b.0 - a.0)
            return a.1.mix(b.1, f)
        }
        return emberHot
    }
}

// MARK: - Reusable modifiers / components

extension View {
    /// Frosted card on the dark background.
    func glassCard(_ padding: CGFloat = 18, radius: CGFloat = 26) -> some View {
        self.padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1))
    }

    func emberGlow(_ color: Color = Theme.ember, radius: CGFloat = 24, active: Bool = true) -> some View {
        self.shadow(color: active ? color.opacity(0.55) : .clear, radius: radius)
            .shadow(color: active ? color.opacity(0.30) : .clear, radius: radius * 2)
    }
}

/// Small uppercase status pill (e.g. PREHEATING / READY).
struct Pill: View {
    let text: String
    var color: Color = Theme.textSecondary
    var filled: Bool = false
    var body: some View {
        Text(text.uppercased())
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(filled ? Theme.bg0 : color)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background {
                Capsule().fill(filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(0.14)))
            }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// Linear blend in sRGB (good enough for UI gradients).
    func mix(_ other: Color, _ f: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let g = CGFloat(f)
        return Color(.sRGB, red: ar + (br - ar) * g, green: ag + (bg - ag) * g,
                     blue: ab + (bb - ab) * g, opacity: aa + (ba - aa) * g)
    }
}

/// Light haptics for control actions.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func toggle() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
