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
