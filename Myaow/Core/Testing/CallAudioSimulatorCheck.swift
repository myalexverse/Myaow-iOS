#if DEBUG && targetEnvironment(simulator) && canImport(WebRTC)
import SwiftUI
import AudioToolbox
@preconcurrency import WebRTC

/// Test-only PCM device. No microphone, user audio, external server or production identity is used.
nonisolated final class SimulatorPCMDevice: NSObject, RTCAudioDevice, @unchecked Sendable {
    let deviceInputSampleRate = 48000.0
    let deviceOutputSampleRate = 48000.0
    let inputIOBufferDuration = 0.01
    let outputIOBufferDuration = 0.01
    let inputNumberOfChannels = 1
    let outputNumberOfChannels = 1
    let inputLatency = 0.0
    let outputLatency = 0.0
    private let lock = NSLock()
    private var delegate: RTCAudioDeviceDelegate?
    private var recording = false
    private var playing = false
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "myaow.test.pcm")
    private var frame = 0
    private var receivedPeak = 0.0
    private var firstAudible: Double?
    private let transmits: Bool
    init(transmits: Bool) { self.transmits = transmits; super.init() }
    var isInitialized: Bool { lock.withLock { delegate != nil } }
    var isPlayoutInitialized: Bool { true }
    var isRecordingInitialized: Bool { true }
    var isPlaying: Bool { lock.withLock { playing } }
    var isRecording: Bool { lock.withLock { recording } }
    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        lock.withLock { self.delegate = delegate }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(10))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source; source.resume(); return true
    }
    func terminateDevice() -> Bool { timer?.cancel(); timer = nil; lock.withLock { delegate = nil }; return true }
    func initializePlayout() -> Bool { true }
    func initializeRecording() -> Bool { true }
    func startPlayout() -> Bool { lock.withLock { playing = true }; return true }
    func stopPlayout() -> Bool { lock.withLock { playing = false }; return true }
    func startRecording() -> Bool { lock.withLock { recording = true }; return true }
    func stopRecording() -> Bool { lock.withLock { recording = false }; return true }
    func observation() -> (peak: Double, firstAudible: Double?) { lock.withLock { (receivedPeak, firstAudible) } }
    private func tick() {
        let state = lock.withLock { (delegate, recording, playing) }
        guard let delegate = state.0 else { return }
        var flags = AudioUnitRenderActionFlags()
        var stamp = AudioTimeStamp(); stamp.mSampleTime = Double(frame); stamp.mFlags = .sampleTimeValid
        if state.1 {
            var samples = [Int16](repeating: 0, count: 480)
            for i in samples.indices {
                let t = Double(frame + i) / 48000
                let gate = Int(t * 2) % 4 < 3
                let envelope = 0.35 + 0.65 * pow(sin(t * .pi * 3), 2)
                if transmits && gate { samples[i] = Int16(11000 * envelope * (sin(2 * .pi * 220 * t) + 0.3 * sin(2 * .pi * 440 * t))) }
            }
            samples.withUnsafeMutableBytes { bytes in
                var buffers = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                _ = delegate.deliverRecordedData(&flags, &stamp, 0, 480, &buffers, nil, nil)
            }
            frame += 480
        }
        if state.2 {
            var samples = [Int16](repeating: 0, count: 480)
            samples.withUnsafeMutableBytes { bytes in
                var buffers = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress))
                _ = delegate.getPlayoutData(&flags, &stamp, 0, 480, &buffers)
            }
            let peak = samples.map { abs(Double($0)) / 32768 }.max() ?? 0
            lock.withLock {
                receivedPeak = peak
                if peak > 0.01 && firstAudible == nil { firstAudible = ProcessInfo.processInfo.systemUptime }
            }
        }
    }
}

@MainActor @Observable final class CallAudioSimulatorCheck {
    var status = "Preparando dos extremos WebRTC…"
    var level = 0.0
    var audio = 0.0
    var elapsed = 0.0
    var result = ""
    var emotion: MyaowCatState = .friendly
    private var caller: WebRTCPeerService?
    private var callee: WebRTCPeerService?
    func run() async {
        guard DesignPreviewData.isEnabled else { return }
        let radioCheck = ProcessInfo.processInfo.arguments.contains("--radio-audio-check")
        let tx = SimulatorPCMDevice(transmits: true), rx = SimulatorPCMDevice(transmits: radioCheck)
        let a = WebRTCPeerService(testAudioDevice: tx), b = WebRTCPeerService(testAudioDevice: rx)
        caller = a; callee = b
        let config = CallICEConfiguration(iceServers: [], expiresAt: Date().timeIntervalSince1970 + 120, iceTransportPolicy: "relay")
        a.configureICE(config); b.configureICE(config)
        a.onLocalSDPGenerated = { type, sdp in if type == "offer" { b.handleRemoteOffer(sdp: sdp, isVideo: false) } }
        b.onLocalSDPGenerated = { type, sdp in if type == "answer" { a.handleRemoteAnswer(sdp: sdp) } }
        a.onIceCandidateGenerated = { mid, line, candidate in b.handleRemoteIceCandidate(sdpMid: mid, sdpMLineIndex: Int32(line), candidate: candidate) }
        b.onIceCandidateGenerated = { mid, line, candidate in a.handleRemoteIceCandidate(sdpMid: mid, sdpMLineIndex: Int32(line), candidate: candidate) }
        let start = ProcessInfo.processInfo.systemUptime
        var connected: Double?
        b.onConnectionStateChanged = { state in if state == "connected" && connected == nil { connected = ProcessInfo.processInfo.systemUptime - start } }
        var floorA = RadioTurnState(isAuthority: true), floorB = RadioTurnState(isAuthority: false)
        if radioCheck {
            a.setMuted(true); b.setMuted(true)
            a.onRadioControl = { text in
                for message in floorA.receive(text, now: ProcessInfo.processInfo.systemUptime) { _ = a.sendRadioControl(message) }
                a.setMuted(!floorA.transmitting)
            }
            b.onRadioControl = { text in
                for message in floorB.receive(text, now: ProcessInfo.processInfo.systemUptime) { _ = b.sendRadioControl(message) }
                b.setMuted(!floorB.transmitting)
            }
        }
        a.startCall(isVideo: false, radio: radioCheck)
        var samples: [[String: Double]] = []
        let showcase = ProcessInfo.processInfo.arguments.contains("--emotions-audio-check")
        for index in 0..<(showcase ? MyaowCatState.allCases.count * 24 : 240) {
            guard !Task.isCancelled else { break }
            if radioCheck {
                let now = ProcessInfo.processInfo.systemUptime
                if index == 20 { for message in floorA.request(now: now) { _ = a.sendRadioControl(message) }; a.setMuted(!floorA.transmitting) }
                if index == 50 { for message in floorA.stop() { _ = a.sendRadioControl(message) }; a.setMuted(true) }
                if index == 70 { for message in floorB.request(now: now) { _ = b.sendRadioControl(message) } }
                if index == 100 { for message in floorB.stop() { _ = b.sendRadioControl(message) }; b.setMuted(true) }
            }
            b.sampleRemoteVoice()
            level = b.remoteSpeakingLevel
            let observation = rx.observation()
            audio = observation.peak
            if showcase { emotion = MyaowCatState.allCases[min(MyaowCatState.allCases.count - 1, index / 24)] }
            elapsed = ProcessInfo.processInfo.systemUptime - start
            status = connected == nil ? "Conectando WebRTC local…" : "Audio sintético por RTP · sin micrófono"
            samples.append(["time": elapsed, "mouth": level, "decodedPeak": audio, "reversePeak": tx.observation().peak, "emotionIndex": Double(MyaowCatState.allCases.firstIndex(of: emotion) ?? 0)])
            try? await Task.sleep(for: .milliseconds(80))
        }
        let audible = rx.observation().firstAudible.map { $0 - start }
        let active = samples.filter { $0["decodedPeak", default: 0] > 0.03 }
        let quiet = samples.filter { $0["time", default: 0] > 5 && $0["decodedPeak", default: 0] < 0.001 }
        let followsAudio = active.contains { $0["mouth", default: 0] > 0.1 }
        let rests = quiet.contains { $0["mouth", default: 1] == 0 }
        let voicedEmotions = Set(samples.filter { $0["mouth", default: 0] > 0.1 && $0["decodedPeak", default: 0] > 0.01 }.compactMap { $0["emotionIndex"] })
        let receiverHeardCaller = samples.contains { (2.0...3.8).contains($0["time", default: 0]) && $0["decodedPeak", default: 0] > 0.03 }
        let callerHeardReceiver = samples.contains { (6.0...8.0).contains($0["time", default: 0]) && $0["reversePeak", default: 0] > 0.03 }
        let closedMicrophones = samples.filter { $0["time", default: 0] > 11 }.allSatisfy { $0["decodedPeak", default: 1] < 0.001 && $0["reversePeak", default: 1] < 0.001 }
        let radioPassed = !radioCheck || (receiverHeardCaller && callerHeardReceiver && closedMicrophones)
        let passed = radioPassed && connected != nil && audible != nil && followsAudio && rests && (!showcase || voicedEmotions.count == MyaowCatState.allCases.count)
        result = passed ? "PASS: audio recibido, boca activa y silencio" : "FAIL: revisar conexión, audio o amplitud"
        var report: [String: Any] = ["result": result, "scope": "Two local WebRTC peers in one iOS simulator; synthetic PCM; no TURN, backend, CallKit or physical network timing claim", "samples": samples]
        report["connectedSeconds"] = connected; report["firstDecodedAudioSeconds"] = audible
        report["voicedEmotions"] = voicedEmotions.count
        report["radioTurnsPassed"] = radioCheck ? radioPassed : nil
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? data.write(to: folder.appendingPathComponent(radioCheck ? "radio-audio-check.json" : "call-audio-check.json"), options: .atomic)
        }
        a.endCall(); b.endCall(); _ = tx.terminateDevice(); _ = rx.terminateDevice(); level = 0
    }
}

struct CallAudioSimulatorCheckView: View {
    @State private var check = CallAudioSimulatorCheck()
    var body: some View {
        VStack(spacing: 28) {
            Text("PRUEBA LOCAL DE AUDIO").font(.caption).tracking(2).foregroundStyle(MyaowColor.orange)
            MyaowCatView(state: check.emotion, style: .darkOnOrange, size: 190, isInteractive: false, speakingLevel: check.level)
            Text(check.emotion.displayName).font(.title2.weight(.semibold))
            Text(check.status).multilineTextAlignment(.center)
            Text(String(format: "%.1f s · Boca %.2f · Audio %.3f", check.elapsed, check.level, check.audio)).font(.caption.monospacedDigit())
            Text(check.result).font(.headline).foregroundStyle(MyaowColor.orange)
            Text("Audio de prueba transmitido y decodificado por WebRTC. No es una llamada a una persona.").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(MyaowColor.charcoal).task { await check.run() }
    }
}
#endif
