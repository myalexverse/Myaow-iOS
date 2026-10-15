import Foundation

/// Original, band-limited radio cues. No recordings, network assets or voice processing.
enum RadioSoundCue: String, CaseIterable {
    case transmitStart, transmitEnd, receiveStart, receiveEnd, linkReady, busy, invitation
    var duration: Double {
        switch self {
        case .transmitStart: 0.16
        case .transmitEnd: 0.20
        case .receiveStart: 0.09
        case .receiveEnd: 0.24
        case .linkReady: 0.30
        case .busy: 0.28
        case .invitation: 3.2
        }
    }
}

struct RadioSoundDesign {
    static let sampleRate = 24000
    static func samples(for cue: RadioSoundCue) -> [Int16] {
        var seed: UInt32 = 0x4D59414F
        var low = 0.0, high = 0.0
        func envelope(_ time: Double, _ start: Double, _ end: Double) -> Double {
            guard time >= start, time < end else { return 0 }
            let edge = min(1, (time - start) / 0.005, (end - time) / 0.012)
            return sin(edge * .pi / 2) * sin(edge * .pi / 2)
        }
        let raw: [Double] = (0..<Int(cue.duration * Double(sampleRate))).map { index in
            let t = Double(index) / Double(sampleRate)
            seed = seed &* 1664525 &+ 1013904223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            low += 0.56 * (noise - low); high += 0.075 * (noise - high)
            let hiss = (low - high) * 0.22
            func tone(_ start: Double, _ end: Double, _ frequency: Double, _ gain: Double = 0.34) -> Double {
                let phase = 2 * Double.pi * frequency * (t - start)
                // Soft-shaped harmonics give a small radio speaker its recognisable body.
                let carrier = tanh(1.35 * (sin(phase) + 0.16 * sin(phase * 3))) / tanh(1.35)
                return carrier * envelope(t, start, end) * gain
            }
            let value: Double
            switch cue {
            case .transmitStart:
                value = tone(0.008, 0.066, 1320) + tone(0.086, 0.147, 1810) + hiss * envelope(t, 0, 0.025)
            case .transmitEnd:
                value = tone(0.006, 0.066, 1060, 0.28) + hiss * envelope(t, 0.080, 0.184)
            case .receiveStart:
                value = hiss * envelope(t, 0.004, 0.074) + tone(0.014, 0.048, 920, 0.12)
            case .receiveEnd:
                value = hiss * envelope(t, 0.005, 0.062) + tone(0.058, 0.117, 1810, 0.26) + tone(0.138, 0.213, 1060, 0.24)
            case .linkReady:
                value = tone(0.010, 0.075, 880, 0.27) + tone(0.093, 0.160, 1320, 0.29) + tone(0.180, 0.278, 1810, 0.27)
            case .busy:
                value = tone(0.012, 0.110, 460, 0.25) + tone(0.151, 0.255, 460, 0.25)
            case .invitation:
                value = tone(0.01, 0.073, 1320, 0.26) + tone(0.104, 0.186, 1810, 0.26)
            }
            return value
        }
        // Match the family by peak, with quieter receive-open so it does not mask speech.
        let peak = raw.map { abs($0) }.max() ?? 1
        let target = RadioSoundMix.peak(for: cue)
        return raw.map { Int16(max(-target, min(target, $0 * target / max(peak, 0.001))) * 32767) }
    }
    static func wave(for cue: RadioSoundCue) -> Data {
        let samples = samples(for: cue)
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ number: T) {
            var n = number.littleEndian
            withUnsafeBytes(of: &n) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + samples.count * 2)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(samples.count * 2))
        for sample in samples { append(sample) }
        return data
    }
}

/// Only actual floor changes produce cues, never repeated or stale control packets.
struct RadioCueTransitions {
    private var transmitting = false
    private var receiving = false
    mutating func update(transmitting tx: Bool, receiving rx: Bool) -> RadioSoundCue? {
        defer { transmitting = tx; receiving = rx }
        if tx && !transmitting { return .transmitStart }
        if rx && !receiving { return .receiveStart }
        if transmitting && !tx { return .transmitEnd }
        if receiving && !rx { return .receiveEnd }
        return nil
    }
}

/// A per-app signal level, independent of the user's system/call volume.
struct RadioSoundMix {
    static let defaultIntensity = 0.85
    static func intensity(_ stored: Double) -> Double {
        stored.isFinite ? max(0, min(1, stored)) : defaultIntensity
    }
    static func peak(for cue: RadioSoundCue) -> Double {
        switch cue {
        case .receiveStart: 0.30
        case .busy: 0.58
        case .invitation: 0.66
        default: 0.76
        }
    }
}
