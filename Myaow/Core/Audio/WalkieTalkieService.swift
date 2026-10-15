import SwiftUI
import AVFoundation
import MultipeerConnectivity

public enum WalkieTalkieState: Equatable, Sendable {
    case idle
    case transmitting(channel: Int)
    case receiving(fromName: String, channel: Int)
    case unverifiedBlocked(reason: String)
}

public struct RadioChannel: Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public static let defaultChannels = [
        RadioChannel(id: 1, name: "Encuentro"),
        RadioChannel(id: 2, name: "Equipo"),
        RadioChannel(id: 3, name: "Ruta")
    ]
}

@MainActor @Observable
public final class WalkieTalkieService: NSObject {
    public static let shared = WalkieTalkieService()
    public private(set) var state: WalkieTalkieState = .idle
    public private(set) var currentChannel = RadioChannel.defaultChannels[0]
    public private(set) var audioLevels: [CGFloat] = Array(repeating: 0, count: 24)
    public var isMuted = false { didSet { if isMuted { clearPlayback(); audioLevels = Array(repeating: 0, count: 24) } } }
    public private(set) var lastTransmissionDate: Date?
    public private(set) var transmissionStartedAt: Date?
    var notice: String?
    let transport = LocalRadioTransport()
    private var ownsAudioSession = false
    private var captureEngine: AVAudioEngine?
    private var playbackEngine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var receiveGate = RadioReceiveGate()
    private var stream: UUID?
    private var sequence: UInt32 = 0
    private var wantsToTalk = false
    private var pressGeneration = UUID()
    private var playbackGeneration = UUID()
    private var queuedBuffers = 0
    private var playReceiveEndAfterDrain = false
    private var limitTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private let format = RadioPCMCodec.format()

    var listeners: [RadioNeighbor] { transport.connected.filter { $0.channel == currentChannel.id } }
    var isTransmitting: Bool { if case .transmitting = state { return true }; return false }
    var canTalk: Bool { transport.isActive && !listeners.isEmpty && receiveGate.peer == nil }

    public override init() {
        super.init()
        transport.onConnect = { [weak self] in
            guard let self, self.transport.isActive, CallSessionService.shared.callState == .idle, !self.isMuted else { return }
            do { try self.configureAudio(); CommunicationTones.shared.playRadio(.linkReady) }
            catch { self.notice = "Enlace listo. Revisa la salida de audio antes de hablar." }
        }
        transport.onPacket = { [weak self] packet, peer in self?.receive(packet, from: peer) }
        transport.onDisconnect = { [weak self] peer in
            guard let self else { return }
            if self.receiveGate.peer == peer { self.finishReceiving() }
            if self.listeners.isEmpty { self.stopTransmitting() }
        }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.stopTransmitting(); self.finishReceiving() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            // Our own category activation also emits route changes; only unplugging cancels speech.
            guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            guard let self else { return }
                Task { @MainActor in self.stopTransmitting(); self.finishReceiving() }
        })
    }
    func activate() {
        guard CallSessionService.shared.callState == .idle else { notice = "Finaliza la llamada antes de activar Radio."; return }
        notice = nil; state = .idle
        transport.start(name: IdentityManager.shared.currentIdentity.displayName)
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, let self else { return }
                if self.receiveGate.expire(now: ProcessInfo.processInfo.systemUptime) { self.finishReceiving() }
                if !self.transport.isActive || CallSessionService.shared.callState != .idle { self.deactivate(); return }
            }
        }
    }
    func deactivate() {
        let ownedAudio = ownsAudioSession || captureEngine != nil || playbackEngine != nil
        stopTransmitting(); finishReceiving(); transport.stop()
        expiryTask?.cancel(); expiryTask = nil
        playbackEngine?.stop(); playbackEngine = nil; player = nil
        ownsAudioSession = false
        if ownedAudio, CallSessionService.shared.callState == .idle {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
    func select(_ channel: RadioChannel) {
        guard channel != currentChannel else { return }
        stopTransmitting(); finishReceiving(); currentChannel = channel
        transport.channel = channel.id; transport.announceChannel()
        notice = nil
    }
    public func startTransmitting(targetContactId: String? = nil, isTargetVerified: Bool = true) {
        guard !wantsToTalk else { return }
        guard isTargetVerified, targetContactId == nil else {
            state = .unverifiedBlocked(reason: "Conecta la radio cercana mediante una invitación antes de hablar."); return
        }
        guard canTalk, CallSessionService.shared.callState == .idle else { return }
        wantsToTalk = true; notice = nil
        let generation = UUID(); pressGeneration = generation
        Task { [weak self] in
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard let self, self.wantsToTalk, self.pressGeneration == generation, self.canTalk else { return }
            guard allowed else {
                self.wantsToTalk = false
                self.notice = "Activa el micrófono para Myaow en Ajustes y vuelve a mantener presionado."
                return
            }
            self.beginCapture()
        }
    }
    private func configureAudio() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        ownsAudioSession = true
    }
    private func beginCapture() {
        do {
            try configureAudio()
            clearPlayback()
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let sourceFormat = input.outputFormat(forBus: 0)
            guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0,
                  let converter = AVAudioConverter(from: sourceFormat, to: format) else { throw RadioAudioError.unavailable }
            let outputFormat = format
            let streamID = UUID(); stream = streamID; sequence = 0
            let handoff = DispatchSemaphore(value: 1)
            input.installTap(onBus: 0, bufferSize: 1024, format: sourceFormat) { [weak self] buffer, _ in
                // Bounded handoff: drop a frame instead of accumulating live microphone audio.
                guard handoff.wait(timeout: .now()) == .success else { return }
                guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 1024) else { handoff.signal(); return }
                var supplied = false
                var error: NSError?
                converter.convert(to: converted, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true; status.pointee = .haveData; return buffer
                }
                guard error == nil, let encoded = RadioPCMCodec.encode(converted) else { handoff.signal(); return }
                Task { @MainActor in
                    defer { handoff.signal() }
                    guard let self, self.stream == streamID, self.isTransmitting else { return }
                    self.sequence &+= 1
                    if !self.transport.send(RadioPacket(.audio, channel: self.currentChannel.id, stream: streamID, sequence: self.sequence, pcm: encoded.data)) {
                        self.stopTransmitting(); return
                    }
                    self.meter(CGFloat(encoded.level))
                }
            }
            captureEngine = engine
            try engine.start()
            guard transport.send(RadioPacket(.start, channel: currentChannel.id, stream: streamID)) else { throw RadioAudioError.unavailable }
            CommunicationTones.shared.playRadio(.transmitStart)
            transmissionStartedAt = Date()
            state = .transmitting(channel: currentChannel.id)
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            limitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.stopTransmitting(); self?.notice = "Turno terminado. Puedes volver a hablar."
            }
        } catch {
            stopTransmitting(); notice = "No pudimos iniciar el audio. Revisa el micrófono y la conexión local."
        }
    }
    public func stopTransmitting() {
        wantsToTalk = false; pressGeneration = UUID()
        limitTask?.cancel(); limitTask = nil
        if let stream { transport.send(RadioPacket(.end, channel: currentChannel.id, stream: stream)); lastTransmissionDate = Date() }
        stream = nil; transmissionStartedAt = nil
        if let engine = captureEngine { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        captureEngine = nil
        if isTransmitting { CommunicationTones.shared.playRadio(.transmitEnd); state = .idle; UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
        audioLevels = Array(repeating: 0, count: 24)
    }
    private func receive(_ packet: RadioPacket, from peer: RadioNeighbor) {
        guard transport.isActive, CallSessionService.shared.callState == .idle, packet.channel == currentChannel.id,
              peer.channel == currentChannel.id else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if receiveGate.expire(now: now) { finishReceiving() }
        if isTransmitting {
            guard packet.kind == .start, peer.id < transport.localPeer.displayName else { return }
            stopTransmitting()
        }
        guard receiveGate.accept(packet, from: peer.id, channel: currentChannel.id, now: now) else { return }
        switch packet.kind {
        case .start:
            stopTransmitting(); clearPlayback()
            state = .receiving(fromName: peer.name, channel: currentChannel.id)
            if !isMuted { try? configureAudio(); CommunicationTones.shared.playRadio(.receiveStart) }
        case .audio:
            if !isMuted { play(packet.pcm) }
        case .end: finishReceiving(drain: true)
        case .presence: break
        }
    }
    private func play(_ data: Data) {
        guard queuedBuffers < 8 else { return }
        do {
            if playbackEngine == nil {
                try configureAudio()
                let engine = AVAudioEngine(); let node = AVAudioPlayerNode()
                engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
                try engine.start(); node.play()
                playbackEngine = engine; player = node
            }
            guard let player, let decoded = RadioPCMCodec.decode(data) else { return }
            let buffer = decoded.buffer
            meter(CGFloat(decoded.level))
            let generation = playbackGeneration; queuedBuffers += 1
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    guard self.playbackGeneration == generation else { return }
                    self.queuedBuffers = max(0, self.queuedBuffers - 1)
                    if self.queuedBuffers == 0, self.receiveGate.peer == nil {
                        let cue = self.playReceiveEndAfterDrain && !self.isMuted
                        self.clearPlayback()
                        if cue { CommunicationTones.shared.playRadio(.receiveEnd) }
                    }
                }
            }
        } catch { notice = "No se pudo reproducir la voz. Revisa la salida de audio." }
    }
    private func meter(_ level: CGFloat) { audioLevels.removeFirst(); audioLevels.append(level) }
    private func clearPlayback() {
        player?.stop(); playbackEngine?.stop(); player = nil; playbackEngine = nil
        playbackGeneration = UUID(); queuedBuffers = 0; playReceiveEndAfterDrain = false
    }
    private func finishReceiving(drain: Bool = false) {
        receiveGate.reset()
        if drain, !isMuted {
            if queuedBuffers > 0 { playReceiveEndAfterDrain = true }
            else { CommunicationTones.shared.playRadio(.receiveEnd) }
        }
        if !drain || queuedBuffers == 0 { clearPlayback() }
        if case .receiving = state { state = .idle }
        audioLevels = Array(repeating: 0, count: 24)
    }
    private enum RadioAudioError: Error { case unavailable }
}
