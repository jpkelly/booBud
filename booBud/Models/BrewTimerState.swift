import Foundation

/// Represents the state of the built-in brew timer.
struct BrewTimerState {
    /// Elapsed time in seconds.
    var elapsed: TimeInterval = 0
    /// Whether the timer is currently running.
    var isRunning: Bool = false
    /// When the timer was last started/resumed (wall-clock reference).
    var startedAt: Date?

    // MARK: - Computed

    var elapsedFormatted: String {
        let totalSeconds = Int(elapsed)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = Int((elapsed - Double(totalSeconds)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    // MARK: - Mutations

    mutating func startOrResume(now: Date = Date()) {
        isRunning = true
        startedAt = now
    }

    mutating func stop(now: Date = Date()) {
        guard isRunning, let started = startedAt else { return }
        elapsed += now.timeIntervalSince(started)
        isRunning = false
        startedAt = nil
    }

    mutating func reset() {
        elapsed = 0
        isRunning = false
        startedAt = nil
    }

    /// Call on each display-frame tick to advance elapsed while running.
    mutating func tick(now: Date = Date()) {
        guard isRunning, let started = startedAt else { return }
        elapsed += now.timeIntervalSince(started)
        startedAt = now
    }
}
