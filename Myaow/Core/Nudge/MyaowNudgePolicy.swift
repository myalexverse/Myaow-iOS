import Foundation

/// Foreground effects are for live arrivals, never historical synchronization.
enum MyaowNudgePolicy {
    nonisolated static func shouldPresent(sentAt: Date, now: Date, lastPresentedAt: Date) -> Bool {
        let age = now.timeIntervalSince(sentAt)
        return age >= -5 && age < 8 && now.timeIntervalSince(lastPresentedAt) >= 5
    }
}
