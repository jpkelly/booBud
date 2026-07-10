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

    /// Bean dose weight in grams entered by the user. Defaults to 18.0 for legacy brews.
    var beanWeight: Double

    /// Grinder setting entered by the user. Defaults to 2.0 for legacy brews.
    var grindSetting: Double

    /// Brew-elapsed time when flow was detected as stopped. Nil for brews saved
    /// before this feature existed; can be computed post-hoc from flowPoints.
    let flowStoppedAt: Double?

    /// Persisted X-axis (time) maximum as computed at save time. Nil for legacy
    /// brews saved before axis-bounds persistence; consumers should fall back
    /// to `BrewAxisBounds.compute(...)` in that case.
    let axisMaxTime: Double?

    /// Persisted weight Y-axis maximum as computed at save time.
    let axisMaxWeight: Double?

    /// Persisted flow Y-axis maximum as computed at save time. Reflects the
    /// user's `flowAutoRange`/`flowMax` settings that were in effect when the
    /// brew was recorded.
    let axisMaxFlow: Double?

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
        displayUnit: WeightUnit,
        beanWeight: Double = 18.0,
        grindSetting: Double = 2.0,
        flowStoppedAt: Double? = nil,
        axisMaxTime: Double? = nil,
        axisMaxWeight: Double? = nil,
        axisMaxFlow: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.name = name
        self.note = note
        self.weightPoints = weightPoints
        self.flowPoints = flowPoints
        self.displayUnitRaw = displayUnit.rawValue
        self.beanWeight = beanWeight
        self.grindSetting = grindSetting
        self.flowStoppedAt = flowStoppedAt
        self.axisMaxTime = axisMaxTime
        self.axisMaxWeight = axisMaxWeight
        self.axisMaxFlow = axisMaxFlow
    }

    // MARK: - Codable (backward-compatible)

    private enum CodingKeys: String, CodingKey {
        case id, date, name, note, weightPoints, flowPoints, displayUnitRaw
        case beanWeight, grindSetting, flowStoppedAt
        case axisMaxTime, axisMaxWeight, axisMaxFlow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        name = try c.decode(String.self, forKey: .name)
        note = try c.decode(String.self, forKey: .note)
        weightPoints = try c.decode([GraphPoint].self, forKey: .weightPoints)
        flowPoints = try c.decode([GraphPoint].self, forKey: .flowPoints)
        displayUnitRaw = try c.decode(String.self, forKey: .displayUnitRaw)
        beanWeight = try c.decodeIfPresent(Double.self, forKey: .beanWeight) ?? 18.0
        grindSetting = try c.decodeIfPresent(Double.self, forKey: .grindSetting) ?? 2.0
        flowStoppedAt = try c.decodeIfPresent(Double.self, forKey: .flowStoppedAt)
        axisMaxTime = try c.decodeIfPresent(Double.self, forKey: .axisMaxTime)
        axisMaxWeight = try c.decodeIfPresent(Double.self, forKey: .axisMaxWeight)
        axisMaxFlow = try c.decodeIfPresent(Double.self, forKey: .axisMaxFlow)
    }
}
