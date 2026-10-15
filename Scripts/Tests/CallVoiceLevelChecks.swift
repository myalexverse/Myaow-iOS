import Foundation

@main struct CallVoiceLevelChecks {
    static func main() {
        for invalid in [Double.nan, .infinity, -.infinity, -1, 0, 0.004] {
            precondition(CallVoiceLevel.normalized(invalid) == 0, "Silence and invalid samples must close the mouth")
        }
        var previous = 0.0
        for index in 0...1_000 {
            let level = CallVoiceLevel.normalized(Double(index) / 1_000)
            precondition(level.isFinite && (0...1).contains(level) && level >= previous)
            previous = level
        }
        var mouth = CallVoiceLevel.smoothed(previous: 0, target: 1)
        precondition(mouth > 0.5, "Speech must animate promptly")
        for _ in 0..<8 { mouth = CallVoiceLevel.smoothed(previous: mouth, target: 0) }
        precondition(mouth == 0, "The mouth must settle completely after silence")
        print("Call voice levels: silence, non-finite input, monotonic amplitude, fast response and decay passed.")
    }
}
