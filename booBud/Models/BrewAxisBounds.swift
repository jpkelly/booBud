import Foundation

/// Shared axis-bounds computation used by both the live/recall graph and the
/// saved-brew thumbnail. Single source of truth so all three surfaces (live,
/// recall, thumbnail) render identical axes for identical data + settings.
enum BrewAxisBounds {

    /// Compute the axis maxes (time, weight, flow) for a set of points and
    /// user flow-axis settings. Matches the historical logic in
    /// `WeightGraphView.effectiveMax*` (30s time floor, 50g weight floor with
    /// tier bucketing, flow auto-range tiers or fixed max).
    ///
    /// - Parameters:
    ///   - weightPoints: (elapsed, weight) tuples
    ///   - flowPoints: (elapsed, flow) tuples
    ///   - flowAutoRange: When false, `flowMax` is used as the fixed flow ceiling
    ///   - flowMax: Fixed flow ceiling when `flowAutoRange` is false
    static func compute(
        weightPoints: [(elapsed: Double, value: Double)],
        flowPoints: [(elapsed: Double, value: Double)],
        flowAutoRange: Bool,
        flowMax: Double
    ) -> (maxTime: Double, maxWeight: Double, maxFlow: Double) {
        let wEnd = weightPoints.last?.elapsed ?? 0
        let fEnd = flowPoints.last?.elapsed ?? 0
        let maxTime = max(max(wEnd, fEnd), 30)

        let dataMax = max(
            weightPoints.map(\.value).max() ?? 0,
            0
        )
        let ceil10 = ceil(dataMax / 10) * 10
        let ceil50 = ceil(dataMax / 50) * 50
        let ceil100 = ceil(dataMax / 100) * 100
        let maxWeight: Double = {
            if dataMax < 20 { return max(ceil10, 50) }
            if dataMax < 100 { return ceil50 }
            return ceil100
        }()

        let maxFlow: Double = {
            guard flowAutoRange else { return flowMax }
            let fMax = flowPoints.map(\.value).max() ?? 0
            let fMin = flowPoints.map(\.value).min() ?? 0
            let absMax = max(abs(fMax), abs(fMin))
            if absMax < 1 { return 1 }
            if absMax < 5 { return ceil(absMax) }
            if absMax < 10 { return ceil(absMax / 2) * 2 }
            return ceil(absMax / 5) * 5
        }()

        return (maxTime, maxWeight, maxFlow)
    }

    /// Convenience overload for `GraphPoint` arrays (used at save time and by
    /// the thumbnail).
    static func compute(
        weightPoints: [GraphPoint],
        flowPoints: [GraphPoint],
        flowAutoRange: Bool,
        flowMax: Double
    ) -> (maxTime: Double, maxWeight: Double, maxFlow: Double) {
        compute(
            weightPoints: weightPoints.map { (elapsed: $0.elapsed, value: $0.value) },
            flowPoints: flowPoints.map { (elapsed: $0.elapsed, value: $0.value) },
            flowAutoRange: flowAutoRange,
            flowMax: flowMax
        )
    }
}
