import Foundation

/// A single reading from the scale, used for display and history.
struct ScaleReading: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let weightGrams: Double
    let flowRate: Double
    let elapsedSeconds: Double
    let batteryPercent: Int
    let isStable: Bool

    init(from weightData: BookooProtocol.WeightData) {
        timestamp = Date()
        weightGrams = weightData.weightGrams
        flowRate = weightData.flowRate
        elapsedSeconds = weightData.elapsedSeconds
        batteryPercent = weightData.batteryPercent
        isStable = weightData.isStable
    }

    /// Weight displayed in the user's chosen unit.
    func displayWeight(unit: WeightUnit) -> String {
        unit.format(weightGrams)
    }
}
