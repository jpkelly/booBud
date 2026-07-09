import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: .alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }

    /// Warm tan — used throughout the app for secondary text on dark backgrounds.
    static let warmSecondary = Color(hex: "B8A898")
}

// MARK: - Shared Formatters

/// Format a grind setting value: always shows 1 decimal place,
/// shows 2 decimal places only when the hundredths digit is non-zero.
func grindString(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.minimumFractionDigits = 1
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
}
