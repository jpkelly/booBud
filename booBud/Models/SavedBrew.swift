import Foundation

/// A saved brew session — persisted graph data, metadata, and user-editable name/note.
struct SavedBrew: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    var name: String
    var note: String
    let weightPoints: [GraphPoint]
    let flowPoints: [GraphPoint]
    let displayUnitRaw: String

    // MARK: - Computed stats

    /// Total brew duration in seconds (from the last data point).
    var duration: Double {
        let weightEnd = weightPoints.last?.elapsed ?? 0
        let flowEnd = flowPoints.last?.elapsed ?? 0
        return max(weightEnd, flowEnd)
    }

    /// Final weight in grams at the end of the brew.
    var finalWeight: Double {
        weightPoints.last?.value ?? 0
    }

    /// Highest weight recorded during the brew.
    var peakWeight: Double {
        weightPoints.map(\.value).max() ?? 0
    }

    /// Highest flow rate recorded during the brew.
    var peakFlow: Double {
        flowPoints.map(\.value).max() ?? 0
    }

    /// The display unit this brew was recorded in.
    var displayUnit: WeightUnit {
        WeightUnit(rawValue: displayUnitRaw) ?? .grams
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        name: String,
        note: String = "",
        weightPoints: [GraphPoint],
        flowPoints: [GraphPoint],
        displayUnit: WeightUnit
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.note = note
        self.weightPoints = weightPoints
        self.flowPoints = flowPoints
        self.displayUnitRaw = displayUnit.rawValue
    }
}
