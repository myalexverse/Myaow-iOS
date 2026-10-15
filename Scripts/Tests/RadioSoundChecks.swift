import Foundation

@main struct RadioSoundChecks {
    static func main() throws {
        var unique = Set<Data>()
        let output = CommandLine.arguments.dropFirst().first
        for cue in RadioSoundCue.allCases {
            let samples = RadioSoundDesign.samples(for: cue)
            let wave = RadioSoundDesign.wave(for: cue)
            precondition(wave.count == 44 + samples.count * 2)
            precondition(String(data: wave.prefix(4), encoding: .utf8) == "RIFF")
            precondition(samples.count == Int(cue.duration * 24000))
            precondition(samples.first == 0 && samples.last == 0, "No sharp start/end edges")
            let peak = samples.map { abs(Int($0)) }.max()!
            precondition(peak > 1000 && peak < 28000, "Audible, with headroom")
            precondition(samples.reduce(0.0) { $0 + Double($1) * Double($1) } > 1_000_000)
            precondition(unique.insert(wave).inserted, "Distinct transmit/receive cues")
            precondition(wave == RadioSoundDesign.wave(for: cue), "Deterministic generation")
            if let output { try wave.write(to: URL(fileURLWithPath: output).appendingPathComponent(cue.rawValue + ".wav")) }
        }
        precondition(RadioSoundMix.intensity(.nan) == RadioSoundMix.defaultIntensity)
        precondition(RadioSoundMix.intensity(.infinity) == RadioSoundMix.defaultIntensity)
        precondition(RadioSoundMix.intensity(-2) == 0 && RadioSoundMix.intensity(3) == 1)
        for cue in RadioSoundCue.allCases {
            let peak = Double(RadioSoundDesign.samples(for: cue).map { abs(Int($0)) }.max()!) / 32767
            precondition(abs(peak - RadioSoundMix.peak(for: cue)) < 0.001)
            precondition(peak * RadioSoundMix.defaultIntensity < 0.7)
        }
        precondition(RadioSoundMix.peak(for: .receiveStart) < RadioSoundMix.peak(for: .transmitStart) / 2)
        var transitions = RadioCueTransitions()
        precondition(transitions.update(transmitting: false, receiving: false) == nil)
        precondition(transitions.update(transmitting: true, receiving: false) == .transmitStart)
        for _ in 0..<30 { precondition(transitions.update(transmitting: true, receiving: false) == nil) }
        precondition(transitions.update(transmitting: false, receiving: false) == .transmitEnd)
        precondition(transitions.update(transmitting: false, receiving: true) == .receiveStart)
        for _ in 0..<30 { precondition(transitions.update(transmitting: false, receiving: true) == nil) }
        precondition(transitions.update(transmitting: false, receiving: false) == .receiveEnd)
        precondition(transitions.update(transmitting: false, receiving: false) == nil)
        precondition(transitions.update(transmitting: true, receiving: false) == .transmitStart)
        precondition(transitions.update(transmitting: false, receiving: true) == .receiveStart, "Collision emits one winning state cue")
        print("PASS: 7 original PCM cues, headroom, envelopes, distinct RX/TX, duplicate and collision transitions, calibrated gain and invalid settings")
    }
}
