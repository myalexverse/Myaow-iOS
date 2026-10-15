import Foundation
import Observation
import AVFoundation
#if canImport(WebRTC)
@preconcurrency import WebRTC
#endif

@MainActor @Observable
public final class WebRTCPeerService: NSObject {
    public static let shared = WebRTCPeerService()
    public var onLocalSDPGenerated: ((String, String) -> Void)?
    public var onIceCandidateGenerated: ((String, Int, String) -> Void)?
    public var onConnectionStateChanged: ((String) -> Void)?
    public var onRadioControl: ((String) -> Void)?
    public var onRadioReady: ((Bool) -> Void)?
    public var onRemoteAudioTrackReceived: (() -> Void)?
    public private(set) var isWebRTCAvailable = false
    #if canImport(WebRTC)
    private let factory: RTCPeerConnectionFactory
    private var localDescriptionPublished = false
    private var pendingLocalICE: [RTCIceCandidate] = []
    #if DEBUG && targetEnvironment(simulator)
    private var usesTestAudio = false
    func injectFilterTestFrame(_ frame: RTCVideoFrame) {
        guard usesTestAudio, let capturer else { return }
        filterProcessor?.capturer(capturer, didCapture: frame)
    }
    init(testAudioDevice: RTCAudioDevice) {
        precondition(DesignPreviewData.isEnabled)
        factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory(), audioDevice: testAudioDevice)
        super.init()
        usesTestAudio = true; isWebRTCAvailable = true
    }
    #endif
    private var radioChannel: RTCDataChannel?
    private var effectsChannel: RTCDataChannel?
    private var filterProcessor: CallVideoFilterProcessor?
    private(set) var filterPreviewTrack: RTCVideoTrack?
    private var filterDraft: VideoFilterSettings?
    private var portalTimer: Task<Void, Never>?
    private var beforePortal = VideoFilterSettings()
    private var ownsPortalFilter = false
    private var systemAudioIsActive = false
    private var peer: RTCPeerConnection?
    private var audio: RTCAudioTrack?
    public private(set) var localVideoTrack: RTCVideoTrack?
    public private(set) var remoteVideoTrack: RTCVideoTrack?
    private var capturer: RTCCameraVideoCapturer?
    private var pendingICE: [RTCIceCandidate] = []
    private var front = true
    private var muted = false
    private var iceConfiguration: CallICEConfiguration?
    #endif
    private(set) var videoFilter = VideoFilterSettings()
    private(set) var portalSession = PortalSession()
    private(set) var effectsReady = false
    var filterNotice: String?
    var portalNotice: String?
    public private(set) var remoteSpeakingLevel = 0.0
    private var lastAudioTimestamp: Double?
    private var lastAudioArrival = Date.distantPast
    /// Reads only the amplitude already provided by RTP; never records or stores call audio.
    public func sampleRemoteVoice() {
        #if canImport(WebRTC)
        let sources = peer?.receivers.filter { $0.track?.kind == "audio" }.flatMap(\.sources) ?? []
        let source = sources.max { $0.timestampUs < $1.timestampUs }
        if let source, source.timestampUs != lastAudioTimestamp {
            lastAudioTimestamp = source.timestampUs; lastAudioArrival = Date()
        }
        let fresh = Date().timeIntervalSince(lastAudioArrival) < 0.25
        let target = CallVoiceLevel.normalized(fresh ? source?.audioLevel?.doubleValue ?? 0 : 0)
        remoteSpeakingLevel = CallVoiceLevel.smoothed(previous: remoteSpeakingLevel, target: target)
        #endif
    }
    public func clearVoiceLevel() { remoteSpeakingLevel = 0; lastAudioTimestamp = nil; lastAudioArrival = .distantPast }
    private override init() {
        #if canImport(WebRTC)
        factory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory())
        #endif
        super.init()
        #if canImport(WebRTC)
        isWebRTCAvailable = true
        RTCAudioSession.sharedInstance().useManualAudio = true
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        #endif
    }
    #if canImport(WebRTC)
    private func makePeer(video: Bool) -> RTCPeerConnection? {
        let configuration = RTCConfiguration()
        guard let iceConfiguration, iceConfiguration.expiresAt > Date().timeIntervalSince1970 else {
            onConnectionStateChanged?("failed"); return nil
        }
        configuration.iceServers = iceConfiguration.iceServers.map { RTCIceServer(urlStrings: $0.urls, username: $0.username, credential: $0.credential) }
        configuration.iceTransportPolicy = .relay
        #if DEBUG && targetEnvironment(simulator)
        if usesTestAudio { configuration.iceTransportPolicy = .all }
        #endif
        configuration.sdpSemantics = .unifiedPlan
        guard let connection = factory.peerConnection(with: configuration, constraints: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil), delegate: self) else { return nil }
        peer = connection
        // Category is prepared before CallKit fulfills start/answer. Changing it here
        // used to race the activation callback on the first connection.
        if systemAudioIsActive { RTCAudioSession.sharedInstance().isAudioEnabled = true }
        audio = factory.audioTrack(with: factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)), trackId: "audio")
        if let audio { audio.isEnabled = !muted; connection.add(audio, streamIds: ["myaow"]) }
        if video {
            let source = factory.videoSource()
            localVideoTrack = factory.videoTrack(with: source, trackId: "video")
            if let localVideoTrack { connection.add(localVideoTrack, streamIds: ["myaow"]) }
            let previewSource = factory.videoSource()
            filterPreviewTrack = factory.videoTrack(with: previewSource, trackId: "filter-preview")
            let processor = CallVideoFilterProcessor(output: source, preview: previewSource)
            processor.onFailure = { [weak self, weak processor] in
                Task { @MainActor in
                    guard let self, let processor, self.filterProcessor === processor else { return }
                    self.filterNotice = "No se pudo dibujar el efecto. Prueba Natural o vuelve a elegirlo."
                }
            }
            filterProcessor = processor
            capturer = RTCCameraVideoCapturer(delegate: processor); capture()
        }
        return connection
    }
    private func constraints(_ video: Bool) -> RTCMediaConstraints {
        RTCMediaConstraints(mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": video ? "true" : "false"], optionalConstraints: nil)
    }
    private func publish(_ sdp: RTCSessionDescription, connection: RTCPeerConnection, type: String) {
        connection.setLocalDescription(sdp) { [self, connection] error in
            Task { @MainActor in
                guard self.peer === connection else { return }
                if error != nil { self.onConnectionStateChanged?("failed"); return }
                self.onLocalSDPGenerated?(type, sdp.sdp)
                self.localDescriptionPublished = true
                for candidate in self.pendingLocalICE {
                    self.onIceCandidateGenerated?(candidate.sdpMid ?? "", Int(candidate.sdpMLineIndex), candidate.sdp)
                }
                self.pendingLocalICE.removeAll()
            }
        }
    }
    private func flushICE() {
        guard let peer, peer.remoteDescription != nil else { return }
        for ice in pendingICE { peer.add(ice) { _ in } }
        pendingICE.removeAll()
    }
    private func capture() {
        #if DEBUG && targetEnvironment(simulator)
        if usesTestAudio { return }
        #endif
        guard let capturer, let device = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == (front ? .front : .back) }) else { return }
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        let format = formats.min { a, b in
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return abs(Int(da.width) - 1280) + abs(Int(da.height) - 720) < abs(Int(db.width) - 1280) + abs(Int(db.height) - 720)
        }
        guard let format else { return }
        let maxFPS = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        capturer.startCapture(with: device, format: format, fps: min(30, Int(maxFPS)))
    }
    #endif
    func configureICE(_ config: CallICEConfiguration) {
        #if canImport(WebRTC)
        iceConfiguration = config
        #endif
    }
    func prepareSystemAudio(video: Bool) throws {
        #if canImport(WebRTC)
        let session = RTCAudioSession.sharedInstance()
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        let config = RTCAudioSessionConfiguration.webRTC()
        config.category = AVAudioSession.Category.playAndRecord.rawValue
        config.mode = (video ? AVAudioSession.Mode.videoChat : .voiceChat).rawValue
        config.categoryOptions = [.allowBluetoothHFP]
        try session.setConfiguration(config)
        #endif
    }
    func sendRadioControl(_ message: String) -> Bool {
        #if canImport(WebRTC)
        guard let radioChannel, radioChannel.readyState == .open, message.utf8.count < 256 else { return false }
        return radioChannel.sendData(RTCDataBuffer(data: Data(message.utf8), isBinary: false))
        #else
        return false
        #endif
    }
    func systemAudioActivated(_ session: AVAudioSession) {
        #if canImport(WebRTC)
        systemAudioIsActive = true
        RTCAudioSession.sharedInstance().audioSessionDidActivate(session)
        RTCAudioSession.sharedInstance().isAudioEnabled = true
        #endif
    }
    func systemAudioDeactivated(_ session: AVAudioSession) {
        #if canImport(WebRTC)
        systemAudioIsActive = false
        RTCAudioSession.sharedInstance().isAudioEnabled = false
        RTCAudioSession.sharedInstance().audioSessionDidDeactivate(session)
        #endif
    }
    public func startCall(isVideo: Bool, radio: Bool = false) {
        #if canImport(WebRTC)
        guard peer == nil, let connection = makePeer(video: isVideo) else { return }
        if isVideo {
            let config = RTCDataChannelConfiguration(); config.isOrdered = true
            effectsChannel = connection.dataChannel(forLabel: "myaow-effects-v1", configuration: config)
            effectsChannel?.delegate = self
        }
        if radio {
            let config = RTCDataChannelConfiguration(); config.isOrdered = true
            radioChannel = connection.dataChannel(forLabel: "myaow-radio-v1", configuration: config)
            radioChannel?.delegate = self
        }
        connection.offer(for: constraints(isVideo)) { [self, connection] sdp, error in
            Task { @MainActor in
                guard self.peer === connection else { return }
                guard let sdp, error == nil else { self.onConnectionStateChanged?("failed"); return }
                self.publish(sdp, connection: connection, type: "offer")
            }
        }
        #endif
    }
    public func handleRemoteOffer(sdp: String, isVideo: Bool) {
        #if canImport(WebRTC)
        guard peer == nil, let connection = makePeer(video: isVideo) else { return }
        connection.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp)) { [self, connection] error in
            Task { @MainActor in
                guard self.peer === connection else { return }
                guard error == nil else { self.onConnectionStateChanged?("failed"); return }
                self.flushICE()
                connection.answer(for: self.constraints(isVideo)) { [self, connection] sdp, error in
                    Task { @MainActor in
                        guard self.peer === connection else { return }
                        guard let sdp, error == nil else { self.onConnectionStateChanged?("failed"); return }
                        self.publish(sdp, connection: connection, type: "answer")
                    }
                }
            }
        }
        #endif
    }
    public func handleRemoteAnswer(sdp: String) {
        #if canImport(WebRTC)
        guard let connection = peer, connection.remoteDescription == nil else { return }
        connection.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp)) { [self, connection] error in
            Task { @MainActor in
                guard self.peer === connection else { return }
                if error != nil { self.onConnectionStateChanged?("failed") } else { self.flushICE() }
            }
        }
        #endif
    }
    public func handleRemoteIceCandidate(sdpMid: String, sdpMLineIndex: Int32, candidate: String) {
        #if canImport(WebRTC)
        let ice = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        if let peer, peer.remoteDescription != nil { peer.add(ice) { _ in } }
        else if pendingICE.count < 256 { pendingICE.append(ice) }
        #endif
    }
    public func setMuted(_ value: Bool) {
        #if canImport(WebRTC)
        muted = value; audio?.isEnabled = !value
        #endif
    }
    public func setCameraEnabled(_ value: Bool) {
        #if canImport(WebRTC)
        filterProcessor?.setEnabled(value)
        localVideoTrack?.isEnabled = value
        filterPreviewTrack?.isEnabled = value
        if value { capture() } else { capturer?.stopCapture() }
        #endif
    }
    public func flipCamera() {
        #if canImport(WebRTC)
        front.toggle(); capture()
        #endif
    }
    public func endCall() {
        clearVoiceLevel()
        videoFilter = .init(); filterNotice = nil; portalNotice = nil
        portalSession = .init(); effectsReady = false
        #if canImport(WebRTC)
        portalTimer?.cancel(); portalTimer = nil
        filterProcessor?.invalidate(); filterProcessor = nil; filterPreviewTrack = nil; filterDraft = nil
        ownsPortalFilter = false; beforePortal = .init()
        effectsChannel?.delegate = nil; effectsChannel?.close(); effectsChannel = nil
        radioChannel?.delegate = nil; radioChannel?.close(); radioChannel = nil
        let previous = peer; peer = nil
        previous?.close(); audio = nil; localVideoTrack = nil; remoteVideoTrack = nil
        capturer?.stopCapture(); capturer = nil; pendingICE.removeAll(); front = true; muted = false
        iceConfiguration = nil
        localDescriptionPublished = false; pendingLocalICE.removeAll()
        #endif
    }
}
#if canImport(WebRTC)
extension WebRTCPeerService: RTCPeerConnectionDelegate {
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Task { @MainActor in
            guard self.peer === peerConnection else { return }
            self.remoteVideoTrack = stream.videoTracks.first; self.onRemoteAudioTrackReceived?()
        }
    }
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        Task { @MainActor in
            guard self.peer === peerConnection else { return }
            if let track = rtpReceiver.track as? RTCVideoTrack { self.remoteVideoTrack = track }
        }
    }
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            guard self.peer === peerConnection else { return }
            if newState == .connected || newState == .completed { self.onConnectionStateChanged?("connected") }
            else if newState == .failed { self.onConnectionStateChanged?("failed") }
            else if newState == .disconnected { self.onConnectionStateChanged?("disconnected") }
        }
    }
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in
            guard self.peer === peerConnection else { return }
            guard self.localDescriptionPublished else {
                if self.pendingLocalICE.count < 256 { self.pendingLocalICE.append(candidate) }
                return
            }
            self.onIceCandidateGenerated?(candidate.sdpMid ?? "", Int(candidate.sdpMLineIndex), candidate.sdp)
        }
    }
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        Task { @MainActor in
            guard self.peer === peerConnection else { return }
            if dataChannel.label == "myaow-effects-v1", self.effectsChannel == nil {
                self.effectsChannel = dataChannel; dataChannel.delegate = self
                self.updateEffectsChannel(); return
            }
            guard dataChannel.label == "myaow-radio-v1", self.radioChannel == nil else { return }
            self.radioChannel = dataChannel; dataChannel.delegate = self
            self.onRadioReady?(dataChannel.readyState == .open)
        }
    }
}
#endif

#if canImport(WebRTC)
extension WebRTCPeerService: RTCDataChannelDelegate {
    nonisolated public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Task { @MainActor in
            if self.effectsChannel === dataChannel { self.updateEffectsChannel(); return }
            guard self.radioChannel === dataChannel else { return }
            self.onRadioReady?(dataChannel.readyState == .open)
        }
    }
    nonisolated public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard !buffer.isBinary, buffer.data.count <= 512 else { return }
        let data = buffer.data
        Task { @MainActor in
            if self.effectsChannel === dataChannel {
                if let message = PortalMessage.decode(data) { self.receivePortal(message) }
                return
            }
            guard self.radioChannel === dataChannel, data.count < 256, let text = String(data: data, encoding: .utf8) else { return }
            self.onRadioControl?(text)
        }
    }
}
#endif

#if canImport(WebRTC)
extension WebRTCPeerService {
    func previewFilter(_ settings: VideoFilterSettings) {
        filterNotice = nil; filterDraft = settings
        filterProcessor?.configure(active: videoFilter, draft: settings)
    }
    func closeFilterPreview() {
        filterDraft = nil; filterProcessor?.configure(active: videoFilter, draft: nil)
    }
    func applyFilter(_ settings: VideoFilterSettings) {
        if settings.type != .duoPortal {
            if let cancel = portalSession.cancel() { _ = sendPortal(cancel) }
            ownsPortalFilter = false
        }
        videoFilter = settings; filterNotice = nil
        filterProcessor?.configure(active: settings, draft: filterDraft)
    }
    func inviteToPortal() {
        guard effectsReady, let message = portalSession.invite(now: ProcessInfo.processInfo.systemUptime) else { return }
        if sendPortal(message) { portalNotice = "Invitación enviada · vence en 30 segundos" }
        else { _ = portalSession.cancel(); portalNotice = "No se pudo enviar. Inténtalo de nuevo." }
    }
    func answerPortal(accept: Bool, reducedMotion: Bool) {
        guard let response = portalSession.answer(accept: accept, now: ProcessInfo.processInfo.systemUptime) else { return }
        guard sendPortal(response) else { _ = portalSession.cancel(); portalNotice = "Se perdió la conexión del portal."; return }
        if portalSession.connected { activatePortal(reducedMotion: reducedMotion) }
    }
    func leavePortal() {
        if let cancel = portalSession.cancel() { _ = sendPortal(cancel) }
        restoreAfterPortal(); portalNotice = nil
    }
    func sendPortalGift(_ gift: PortalGift) {
        guard let message = portalSession.send(gift, now: ProcessInfo.processInfo.systemUptime) else { return }
        if sendPortal(message) { filterProcessor?.show(gift); portalNotice = "\(gift.title) enviada" }
        else { portalNotice = "No se pudo enviar la sorpresa." }
    }
    private func activatePortal(reducedMotion: Bool) {
        if videoFilter.type != .duoPortal {
            beforePortal = videoFilter; ownsPortalFilter = true
            applyFilter(VideoFilterSettings(type: .duoPortal, reducedMotion: reducedMotion))
        }
        portalNotice = "Portal conectado · elige una sorpresa"
    }
    private func restoreAfterPortal() {
        if ownsPortalFilter { let previous = beforePortal; ownsPortalFilter = false; applyFilter(previous) }
    }
    private func sendPortal(_ message: PortalMessage) -> Bool {
        guard let channel = effectsChannel, channel.readyState == .open, channel.bufferedAmount < 4096, let data = message.data, data.count <= 512 else { return false }
        return channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }
    private func receivePortal(_ message: PortalMessage) {
        guard effectsReady else { return }
        let wasConnected = portalSession.connected
        let result = portalSession.receive(message, now: ProcessInfo.processInfo.systemUptime)
        if let reply = result.reply { _ = sendPortal(reply) }
        if let gift = result.gift { filterProcessor?.show(gift); portalNotice = "Recibiste: \(gift.title)" }
        if !wasConnected && portalSession.connected { activatePortal(reducedMotion: videoFilter.reducedMotion) }
        if wasConnected && !portalSession.connected { restoreAfterPortal(); portalNotice = "Tu contacto cerró el portal." }
        if message.kind == .decline, portalSession.phase == .idle { portalNotice = "Tu contacto no se unió al portal." }
    }
    private func updateEffectsChannel() {
        effectsReady = effectsChannel?.readyState == .open
        portalTimer?.cancel(); portalTimer = nil
        if !effectsReady { _ = portalSession.cancel(); restoreAfterPortal(); return }
        portalTimer = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                if let expired = self.portalSession.expire(now: ProcessInfo.processInfo.systemUptime) {
                    _ = self.sendPortal(expired); self.portalNotice = "La invitación al portal venció."
                }
            }
        }
    }
}
#endif
