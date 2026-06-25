import Foundation

/// Supported weight units for the scale display.
enum WeightUnit: String, CaseIterable, Identifiable {
    case grams
    case ounces

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .grams:  return "g"
        case .ounces: return "oz"
        }
    }

    /// Conversion factor *from* grams.
    var fromGrams: Double {
        switch self {
        case .grams:  return 1.0
        case .ounces: return 1.0 / 28.349523125
        }
    }

    /// Convert a value in grams to this unit.
    func convert(grams: Double) -> Double {
        grams * fromGrams
    }

    /// Format a weight value for display.
    func format(_ value: Double) -> String {
        switch self {
        case .grams:
            return String(format: "%.1f", value)
        case .ounces:
            return String(format: "%.2f", value)
        }
    }
}
