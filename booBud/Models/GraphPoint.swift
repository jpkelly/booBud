import Foundation

/// A single (elapsed seconds, value) point — Codable bridge since
/// Swift tuples aren't Codable. Used to persist weight and flow rate
/// graph data for saved brews.
struct GraphPoint: Codable, Equatable {
    var elapsed: Double
    var value: Double

    init(elapsed: Double, value: Double) {
        self.elapsed = elapsed
        self.value = value
    }
}

// MARK: - Tuple bridging

extension Array where Element == GraphPoint {
    /// Convert to the (elapsed:, weight:) tuple array used by WeightGraphView.
    var asWeightTuples: [(elapsed: Double, weight: Double)] {
        map { (elapsed: $0.elapsed, weight: $0.value) }
    }

    /// Convert to the (elapsed:, flowRate:) tuple array used by WeightGraphView.
    var asFlowTuples: [(elapsed: Double, flowRate: Double)] {
        map { (elapsed: $0.elapsed, flowRate: $0.value) }
    }
}

extension Array where Element == (elapsed: Double, weight: Double) {
    /// Convert weight-history tuples to GraphPoint array for persistence.
    var asGraphPoints: [GraphPoint] {
        map { GraphPoint(elapsed: $0.elapsed, value: $0.weight) }
    }
}

extension Array where Element == (elapsed: Double, flowRate: Double) {
    /// Convert flow-rate-history tuples to GraphPoint array for persistence.
    var asGraphPoints: [GraphPoint] {
        map { GraphPoint(elapsed: $0.elapsed, value: $0.flowRate) }
    }
}

extension Array where Element == GraphPoint {
    /// Compute the brew-elapsed time when flow stopped, using the same detection
    /// algorithm as the live display timer (threshold in g/s, 1s debounce).
    /// Only triggers after flow has been active (peaked above 0.5 g/s).
    /// Returns nil if flow never stopped or points are insufficient.
    func computeFlowStoppedAt(threshold: Double) -> Double? {
        guard count > 1 else { return nil }
        // Gate: flow must have peaked above 0.5 g/s before we look for it stopping
        guard self.contains(where: { $0.value > 0.5 }) else { return nil }
        var belowSince: Double? = nil
        var flowHasBeenActive = false
        for point in self {
            if point.value > 0.5 { flowHasBeenActive = true }
            guard flowHasBeenActive else { continue }
            if point.value < threshold {
                if let since = belowSince {
                    if point.elapsed - since >= 1.0 {
                        return since
                    }
                } else {
                    belowSince = point.elapsed
                }
            } else {
                belowSince = nil
            }
        }
        return nil
    }
}
