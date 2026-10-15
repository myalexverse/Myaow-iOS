import AVFoundation

/// Procedural cues mixed into the session owned by CallKit or local Radio.
@MainActor
final class CommunicationTones {
    static let shared = CommunicationTones()
    private var ring: AVAudioPlayer?
    private var cue: AVAudioPlayer?
    private var ringIsRadio = false
    private var radioWaves: [RadioSoundCue: Data] = [:]
    private var lastRadioCueAt: TimeInterval = 0
    var radioSoundsEnabled: Bool { UserDefaults.standard.object(forKey: "radioSoundsEnabled") as? Bool ?? true }
    var radioIntensity: Float {
        Float(RadioSoundMix.intensity(UserDefaults.standard.object(forKey: "radioCueIntensity") as? Double ?? RadioSoundMix.defaultIntensity))
    }
    func updateRadioMix() {
        cue?.volume = radioIntensity
        if ringIsRadio { ring?.volume = radioIntensity }
    }
    func previewRadio() -> String? {
        guard radioSoundsEnabled, radioIntensity > 0 else { return "Activa las señales y sube su intensidad para escucharlas." }
        let call = CallSessionService.shared, local = WalkieTalkieService.shared
        guard call.callState == .idle || (call.callType == .radio && call.canRequestRadioTurn && !call.radioRequestPending),
              !local.isTransmitting else { return "Prueba el sonido cuando el canal esté libre." }
        if case .receiving = local.state { return "Espera a que termine tu contacto." }
        if call.callState == .idle && !local.transport.isActive {
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            } catch { return "No se pudo abrir la salida de audio." }
        }
        playRadio(.linkReady)
        return nil
    }
    func ringback(_ enabled: Bool, radio: Bool = false) {
        guard enabled else { ring?.stop(); ring = nil; return }
        guard ring == nil, !radio || radioSoundsEnabled else { return }
        ring = try? AVAudioPlayer(data: radio ? radioWave(.invitation) : wave(duration: 4, tones: [(0, 1, 440), (0, 1, 480)]))
        ringIsRadio = radio
        ring?.volume = radio ? radioIntensity : 0.22; ring?.numberOfLoops = -1; ring?.play()
    }
    func playRadio(_ sound: RadioSoundCue) {
        guard radioSoundsEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if sound == .busy, now - lastRadioCueAt < 0.4 { return }
        lastRadioCueAt = now
        cue?.stop()
        cue = try? AVAudioPlayer(data: radioWave(sound))
        cue?.volume = radioIntensity
        cue?.prepareToPlay(); cue?.play()
    }
    func silenceRadio() { cue?.stop(); cue = nil }
    private func radioWave(_ sound: RadioSoundCue) -> Data {
        if let data = radioWaves[sound] { return data }
        let data = RadioSoundDesign.wave(for: sound); radioWaves[sound] = data
        return data
    }
    private func wave(duration: Double, tones: [(Double, Double, Double)]) -> Data {
        let rate = 24000, count = Int(duration * Double(rate))
        var pcm = Data()
        for i in 0..<count {
            let t = Double(i) / Double(rate)
            let sample = tones.reduce(0.0) { value, tone in
                guard t >= tone.0 && t < tone.1 else { return value }
                let envelope = min(1, (t-tone.0) / 0.006, (tone.1-t) / 0.006)
                return value + sin(2 * .pi * tone.2 * t) * envelope * 0.32
            }
            var value = Int16(max(-1, min(1, sample)) * 32767).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ number: T) { var n = number.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        append(UInt32(36 + pcm.count)); data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(rate)); append(UInt32(rate*2)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}
