import Foundation

enum CallVoiceLevel {
    nonisolated static func normalized(_ rms: Double) -> Double {
        guard rms.isFinite, rms > 0.008 else { return 0 }
        return min(1, max(0, (20 * log10(min(rms, 1)) + 42) / 34))
    }
    nonisolated static func smoothed(previous: Double, target: Double) -> Double {
        let value = previous + (target - previous) * (target > previous ? 0.8 : 0.55)
        return value < 0.025 ? 0 : min(1, max(0, value))
    }
}
