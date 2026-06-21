import SwiftUI

/// The Eclipse 2's real chromotherapy palette (DP21), mapped at the sauna 2026-06-21
/// via the debug screen. Only these 7 values produce a solid color; `mode1` is a no-op
/// and `mode8`/`mode9` read back as white. The slow morphing rainbow is a separate
/// toggle (DP101). Shared so the app (LightsCard) and the Live Activity accent agree.
enum ChromaPalette {
    static let solids: [(value: String, name: String, color: Color)] = [
        ("mode",  "White",  Color(red: 1.00, green: 0.97, blue: 0.92)),
        ("mode3", "Red",    Color(red: 1.00, green: 0.23, blue: 0.19)),
        ("mode2", "Yellow", Color(red: 1.00, green: 0.83, blue: 0.10)),
        ("mode7", "Green",  Color(red: 0.20, green: 0.82, blue: 0.34)),
        ("mode6", "Teal",   Color(red: 0.22, green: 0.85, blue: 0.82)),
        ("mode5", "Blue",   Color(red: 0.10, green: 0.52, blue: 1.00)),
        ("mode4", "Pink",   Color(red: 1.00, green: 0.30, blue: 0.62)),
    ]

    /// Swatch color for a stored DP21 value (for the Live Activity accent); nil if not a solid.
    static func color(for value: String?) -> Color? {
        solids.first { $0.value == value }?.color
    }
}
