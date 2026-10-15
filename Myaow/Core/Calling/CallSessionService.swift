import SwiftUI
import Combine
import AVFoundation

public enum CallType: String, Sendable { case audio = "Llamada de Audio", video = "Videollamada", radio = "Walkie-talkie" }
public enum CallState: String, Sendable {
    case idle = "Inactivo", calling = "Llamando…", ringing = "Conectando…", incoming = "Llamada entrante", connected = "En llamada", ended = "Llamada finalizada"
}

@MainActor @Observable
public final class CallSessionService: NSObject {
    public static let shared = CallSessionService()
    public private(set) var activeCallCatState: MyaowCatState = .friendly
    public func refreshContactExpression() { activeCallCatState = CallSystemCoordinator.shared.contactCatState(activeCallMyaowId) }
    public var isMinimized = false
    public private(set) var radioReady = false
    public var radioTransmitting: Bool { radioFloor.transmitting }
    public var radioReceiving: Bool { radioFloor.receiving }
    public var radioRequestPending: Bool { radioFloor.requestID != nil && !radioFloor.transmitting }
    public var radioTurnSecondsRemaining: Int {
        guard radioTransmitting, let deadline = radioFloor.deadline else { return 0 }
        return min(60, max(0, Int(ceil(deadline - ProcessInfo.processInfo.systemUptime))))
    }
    public private(set) var radioNotice: String?
    private var radioCues = RadioCueTransitions()
    private var radioFloor = RadioTurnState(isAuthority: true)
    private var radioLease: Task<Void, Never>?
    private var audioActive = false
    public private(set) var activeCallContactName = ""
    public private(set) var activeCallMyaowId = ""
    public private(set) var callType: CallType = .audio
    public private(set) var callState: CallState = .idle {
        didSet {
            if callState != oldValue {
                OnlineMessagingService.shared.callStateDidChange()
                CommunicationTones.shared.ringback(audioActive && !incoming && (callState == .calling || callState == .ringing), radio: callType == .radio)
            }
        }
    }
    public private(set) var callDuration: TimeInterval = 0
    public private(set) var endReason = ""
    public private(set) var isMuted = false
    public private(set) var isSpeakerOn = false
    public private(set) var isCameraOff = true
    public private(set) var isFrontCamera = true
    public var resolveContact: ((String) -> String?)?
    private var callID: String?
    public var currentCallUUID: UUID? { callID.flatMap(UUID.init(uuidString:)) }
    private var signalTask: Task<Void, Never>?
    private let icePreparation = CallResourcePreparation<CallICEConfiguration>()
    #if DEBUG && targetEnvironment(simulator)
    private var isSystemPreview = false
    private var didPresentSystemPreview = false
    func previewSystemIncomingCall(contactID: String, name: String) {
        guard DesignPreviewData.isEnabled, !didPresentSystemPreview,
              ProcessInfo.processInfo.arguments.contains("--call-system-preview") else { return }
        didPresentSystemPreview = true
        handleSignalingEvent(type: "call_offer", senderMyaowId: contactID, senderName: name,
            data: ["callId":UUID().uuidString,"id":UUID().uuidString,"expiresAt":Date().timeIntervalSince1970+45,"callType":CallType.audio.rawValue])
        isSystemPreview = true
    }
    #endif
    private var incoming = false
    private var accepted = false
    private var timer: AnyCancellable?
    private var timeout: Task<Void, Never>?
    private var startedAt: Date?
    private var seenSignals = Set<String>()
    private var endedCalls = Set<String>()
    public var durationFormatted: String { String(format: "%02d:%02d", Int(callDuration) / 60, Int(callDuration) % 60) }

    public override init() {
        super.init()
        let peer = WebRTCPeerService.shared
        peer.onRadioControl = { [weak self] text in self?.receiveRadioControl(text) }
        peer.onRadioReady = { [weak self] ready in
            guard let self, self.callType == .radio else { return }
            let wasReady = self.radioReady
            self.radioReady = ready
            if ready && !wasReady { CommunicationTones.shared.playRadio(.linkReady) }
            if !ready && wasReady { self.finish("Se perdió el canal de Radio. Vuelve a conectar.", notify: true); return }
            if !ready { self.stopRadioTransmission(); self.radioNotice = "Reconectando el canal de voz…" }
        }
        peer.onLocalSDPGenerated = { [weak self] type, sdp in self?.send("webrtc_\(type)", ["sdp": sdp]) }
        peer.onIceCandidateGenerated = { [weak self] mid, line, candidate in
            self?.send("webrtc_ice_candidate", ["sdpMid": mid, "sdpMLineIndex": line, "candidate": candidate])
        }
        peer.onConnectionStateChanged = { [weak self] state in
            guard let self, self.callState == .ringing || self.callState == .connected else { return }
            if state == "connected" {
                self.timeout?.cancel()
                guard self.callState != .connected else { return }
                self.callState = .connected; self.timeout?.cancel(); self.startedAt = Date()
                self.timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                    guard let self, let start = self.startedAt else { return }
                    self.callDuration = Date().timeIntervalSince(start)
                }
                self.applySpeaker()
                if let id = self.currentCallUUID { CallSystemCoordinator.shared.connected(id) }
            } else if state == "disconnected" {
                self.stopRadioTransmission()
                let id = self.callID
                self.timeout?.cancel()
                self.timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(12)) } catch { return }
                    guard let self, self.callID == id else { return }
                    self.finish("Se perdió la conexión.", notify: true)
                }
            } else if state == "failed" { self.finish("No se pudo establecer la conexión.", notify: true) }
        }
    }
    private func permitted(_ id: String) -> String? {
        guard !ContactBlockingService.shared.isBlocked(id) else { return nil }
        return resolveContact?(id) ?? CallSystemCoordinator.shared.contactName(id)
    }
    public func startCall(contactName: String, myaowId: String, type: CallType) {
        guard callState == .idle || callState == .ended else { return }
        WalkieTalkieService.shared.deactivate()
        reset()
        activeCallContactName = permitted(myaowId) ?? contactName
        activeCallMyaowId = myaowId; refreshContactExpression(); callType = type; callID = UUID().uuidString
        callState = .calling; isCameraOff = type != .video; isSpeakerOn = type != .audio
        if type == .radio { setMuted(true) }
        guard permitted(myaowId) != nil else { finish("Guarda este contacto antes de llamarlo.", notify: false); return }
        guard OnlineMessagingService.shared.status == .online else { finish("Sin conexión. Intenta de nuevo cuando vuelvas a estar en línea.", notify: false); return }
        let id = callID
        Task {
            let allowed = await permissions(video: type == .video)
            guard callID == id, callState == .calling else { return }
            guard allowed else { finish("Permite el acceso al micrófono y, para video, a la cámara en Ajustes.", notify: false); return }
            guard await prepareICE(id: id), callID == id, callState == .calling else { return }
            if let uuid = currentCallUUID { CallSystemCoordinator.shared.startOutgoing(uuid, name: activeCallContactName, video: type == .video) }
            send("call_offer", ["callType": type.rawValue, "radioProtocol": type == .radio ? 1 : 0]); armTimeout(id)
        }
    }
    public func acceptCall(fromSystem: Bool = false) {
        guard callState == .incoming else { return }
        if !fromSystem, let uuid = currentCallUUID { CallSystemCoordinator.shared.requestAnswer(uuid); return }
        #if DEBUG && targetEnvironment(simulator)
        if isSystemPreview { finish("Prueba de interfaz completada. No se realizó una llamada real.", notify: false); return }
        #endif
        let id = callID
        callState = .ringing
        Task {
            let allowed = await permissions(video: callType == .video)
            guard callID == id, callState == .ringing else { return }
            guard allowed else { finish("No se concedió acceso al micrófono o la cámara.", notify: true); return }
            guard await prepareICE(id: id), callID == id, callState == .ringing else { return }
            accepted = true
            send("call_answer", ["accepted": true, "radioProtocol": callType == .radio ? 1 : 0])
            armTimeout(id)
        }
    }
    public func endCall() {
        guard callState != .idle, callState != .ended else { return }
        finish(callState == .incoming ? "Llamada rechazada." : "La llamada terminó.", notify: true)
    }
    public func dismissCall() {
        if callState != .idle && callState != .ended { endCall() }
        reset(); callState = .idle
    }
    private func finish(_ reason: String, notify: Bool) {
        guard callState != .idle, callState != .ended else { return }
        if notify { send("call_hangup", [:]) }
        if let startedAt { callDuration = Date().timeIntervalSince(startedAt) }
        if let callID { endedCalls.insert(callID) }
        if endedCalls.count > 256 { endedCalls = Set([callID].compactMap { $0 }) }
        stopRadioTransmission(); radioLease?.cancel(); radioLease = nil; radioFloor.reset()
        CallPictureInPicture.shared.stop()
        callState = .ended; endReason = reason
        timeout?.cancel(); timer?.cancel(); timer = nil
        icePreparation.cancel()
        WebRTCPeerService.shared.endCall()
        if let id = currentCallUUID { CallSystemCoordinator.shared.end(id) }
    }
    private func reset() {
        #if DEBUG && targetEnvironment(simulator)
        isSystemPreview = false
        #endif
        CommunicationTones.shared.ringback(false)
        stopRadioTransmission(); radioLease?.cancel(); radioLease = nil
        radioCues = RadioCueTransitions()
        radioFloor = RadioTurnState(isAuthority: true); radioReady = false; radioNotice = nil; isMinimized = false
        timeout?.cancel(); timer?.cancel(); timer = nil; startedAt = nil
        icePreparation.cancel()
        WebRTCPeerService.shared.endCall()
        callID = nil; incoming = false; accepted = false; callDuration = 0
        isMuted = false; isFrontCamera = true; endReason = ""
    }
    private func armTimeout(_ id: String?) {
        timeout?.cancel()
        timeout = Task {
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard callID == id, callState != .connected else { return }
            finish("No hubo respuesta o no se pudo conectar.", notify: true)
        }
    }
    private func permissions(video: Bool) async -> Bool {
        guard WebRTCPeerService.shared.isWebRTCAvailable else { return false }
        let audio = await AVAudioApplication.requestRecordPermission()
        guard audio else { return false }
        if video { return await AVCaptureDevice.requestAccess(for: .video) }
        return true
    }
    // Only invoked after authenticated decryption; session, expiry and saved contact must all match.
    public func handleSignalingEvent(type: String, senderMyaowId: String, senderName: String, data: [String: Any]) {
        guard let name = permitted(senderMyaowId), let id = data["callId"] as? String, UUID(uuidString: id) != nil,
              let signalID = data["id"] as? String, UUID(uuidString: signalID) != nil,
              let expiry = data["expiresAt"] as? Double, expiry > Date().timeIntervalSince1970,
              expiry <= Date().timeIntervalSince1970 + 95, !seenSignals.contains(signalID) else { return }
        if seenSignals.count > 2048 { seenSignals.removeAll() }
        seenSignals.insert(signalID)
        if type == "call_hangup" { endedCalls.insert(id) }
        if type == "call_offer" {
            guard !endedCalls.contains(id) else { return }
            guard callState == .idle || callState == .ended else { return }
            WalkieTalkieService.shared.deactivate()
            reset(); callID = id; incoming = true; radioFloor = RadioTurnState(isAuthority: false)
            activeCallMyaowId = senderMyaowId; refreshContactExpression(); activeCallContactName = name
            callType = CallType(rawValue: data["callType"] as? String ?? "") ?? .audio
            isCameraOff = callType != .video; isSpeakerOn = callType != .audio
            if callType == .radio { setMuted(true) }
            callState = .incoming; armTimeout(id)
            beginICEPreparation()
            if let uuid = currentCallUUID { CallSystemCoordinator.shared.reportIncoming(uuid, name: name, video: callType == .video) }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        guard callID == id, activeCallMyaowId == senderMyaowId, callState != .idle, callState != .ended else { return }
        switch type {
        case "call_answer":
            guard !incoming, callState == .calling, (data["accepted"] as? Bool) == true else { return }
            if callType == .radio && (data["radioProtocol"] as? Int) != 1 {
                finish("Tu contacto necesita actualizar Myaow para usar Radio por internet.", notify: true); return
            }
            accepted = true; callState = .ringing
            WebRTCPeerService.shared.startCall(isVideo: callType == .video, radio: callType == .radio)
            armTimeout(id)
        case "call_hangup": finish("La otra persona terminó la llamada.", notify: false)
        case "webrtc_offer":
            guard incoming, accepted, let sdp = data["sdp"] as? String else { return }
            WebRTCPeerService.shared.handleRemoteOffer(sdp: sdp, isVideo: callType == .video)
        case "webrtc_answer":
            guard !incoming, accepted, let sdp = data["sdp"] as? String else { return }
            WebRTCPeerService.shared.handleRemoteAnswer(sdp: sdp)
        case "webrtc_ice_candidate":
            guard accepted, let mid = data["sdpMid"] as? String, let line = data["sdpMLineIndex"] as? Int,
                  (0...65535).contains(line), let candidate = data["candidate"] as? String else { return }
            WebRTCPeerService.shared.handleRemoteIceCandidate(sdpMid: mid, sdpMLineIndex: Int32(line), candidate: candidate)
        default: break
        }
    }
    private func send(_ type: String, _ payload: [String: Any]) {
        #if DEBUG && targetEnvironment(simulator)
        if isSystemPreview { return }
        #endif
        guard let callID, !activeCallMyaowId.isEmpty else { return }
        var packet = payload
        packet["type"] = type; packet["callId"] = callID; packet["id"] = UUID().uuidString
        packet["expiresAt"] = Date().timeIntervalSince1970 + (type == "call_offer" ? 45 : 90)
        guard let bytes = try? JSONSerialization.data(withJSONObject: packet) else { return }
        let recipient = activeCallMyaowId
        let owner = IdentityManager.shared.currentIdentity.myaowId
        let host = OnlineMessagingService.shared.relayHost
        let previous = signalTask
        signalTask = Task { [weak self] in
            await previous?.value
            guard let self, owner == IdentityManager.shared.currentIdentity.myaowId, host == OnlineMessagingService.shared.relayHost,
                  type == "call_hangup" || (self.callID == callID && self.callState != .ended && self.callState != .idle) else { return }
            do {
                try await OnlineMessagingService.shared.waitUntilAuthenticated()
                let messageID = packet["id"] as! String
                let encrypted = try await SecureMessagingService.shared.seal(.init(text: String(decoding: bytes, as: UTF8.self), messageType: "call-signal-v2"), messageId: messageID, recipientId: recipient)
                let body: [String: Any] = ["callId":callID, "signalType":type, "expiresAt":packet["expiresAt"]!,
                    "packet":["id":messageID,"type":"message","recipientMyaowId":recipient,"encryptedPayload":encrypted]]
                for attempt in 0..<2 {
                    guard owner == IdentityManager.shared.currentIdentity.myaowId, host == OnlineMessagingService.shared.relayHost else { return }
                    do { _ = try await RelayAPI.request("/api/v1/calls/signal", method: "POST", body: body); break }
                    catch {
                        guard attempt == 0, error is URLError || (error as? SupabaseHTTPError)?.status == 503 else { throw error }
                        try await Task.sleep(for: .milliseconds(500))
                    }
                }
            } catch {
                guard self.callID == callID, type != "call_hangup" else { return }
                // ICE gathering may finish after media already connects. A failed
                // redundant candidate must never tear down a working media path.
                guard CallSignalFailurePolicy.shouldEndCall(signal: type, connected: self.callState == .connected) else { return }
                self.finish((error as? SupabaseHTTPError)?.status == 403
                    ? "Ambos deben guardarse en Tu gente y abrir Myaow para habilitar la llamada."
                    : (error as? SupabaseHTTPError)?.status == 429
                        ? "La señalización alcanzó su límite temporal. Espera un minuto antes de volver a llamar."
                        : "No pudimos comunicar con el contacto. Revisa la conexión e inténtalo de nuevo.", notify: type != "call_offer")
            }
        }
    }
    /// Prepare only signaling credentials while ringing. CallKit still owns microphone activation.
    private func beginICEPreparation() {
        guard !icePreparation.isStarted else { return }
        let owner = IdentityManager.shared.currentIdentity.myaowId
        let host = OnlineMessagingService.shared.relayHost
        icePreparation.start {
            try await OnlineMessagingService.shared.waitUntilAuthenticated()
            try Task.checkCancellation()
            guard owner == IdentityManager.shared.currentIdentity.myaowId, host == OnlineMessagingService.shared.relayHost else { throw CancellationError() }
            if RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL != nil {
                _ = try await RelayAPI.request("/api/v1/calls/contacts", method: "PUT", body: ["callers": CallSystemCoordinator.shared.allowedCallers])
            }
            let config = try await CallICEConfiguration.fetch()
            try Task.checkCancellation()
            guard owner == IdentityManager.shared.currentIdentity.myaowId, host == OnlineMessagingService.shared.relayHost else { throw CancellationError() }
            return config
        }
    }
    private func prepareICE(id: String?) async -> Bool {
        beginICEPreparation()
        do {
            let config: CallICEConfiguration
            do { config = try await icePreparation.value() }
            catch {
                // An incoming call may have rung during a brief network loss. Retry at answer time.
                guard callID == id, callState != .ended, callState != .idle else { return false }
                icePreparation.cancel(); beginICEPreparation()
                config = try await icePreparation.value()
            }
            guard callID == id, callState != .ended, callState != .idle else { return false }
            WebRTCPeerService.shared.configureICE(config)
            return true
        } catch {
            if callID == id { finish("No pudimos preparar la conexión de llamada. Revisa la red o la configuración del servidor.", notify: true) }
            return false
        }
    }
    func systemCallFailed(_ id: UUID) {
        guard currentCallUUID == id else { return }
        finish("El iPhone no pudo abrir esta llamada.", notify: true)
    }
    public func setMuted(_ value: Bool) {
        // System mute always ends a turn; system unmute cannot bypass push-to-talk consent.
        if callType == .radio, value, radioTransmitting { stopRadioTransmission(); return }
        let muted = callType == .radio ? !radioTransmitting : value
        isMuted = muted; WebRTCPeerService.shared.setMuted(muted)
    }

    public func toggleMute() { setMuted(!isMuted) }
    public func toggleSpeaker() { isSpeakerOn.toggle(); applySpeaker() }
    private func applySpeaker() {
        do { try AVAudioSession.sharedInstance().overrideOutputAudioPort(isSpeakerOn ? .speaker : .none) }
        catch { isSpeakerOn = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker } }
    }
    func systemAudioChanged(active: Bool) {
        audioActive = active
        if !active { stopRadioTransmission() }
        CommunicationTones.shared.ringback(active && !incoming && (callState == .calling || callState == .ringing), radio: callType == .radio)
        if active { applySpeaker() }
    }
    public func minimize() { stopRadioTransmission(); isMinimized = true }
    public var canRequestRadioTurn: Bool { callType == .radio && callState == .connected && radioReady && audioActive && !radioReceiving }
    public func startRadioTransmission() {
        guard canRequestRadioTurn else {
            if radioReceiving { radioNotice = "Canal ocupado. Espera a que termine tu contacto."; CommunicationTones.shared.playRadio(.busy) }
            return
        }
        radioNotice = nil
        applyRadio(radioFloor.request(now: ProcessInfo.processInfo.systemUptime))
    }
    public func stopRadioTransmission() {
        applyRadio(radioFloor.stop())
    }
    private func receiveRadioControl(_ text: String) {
        guard callType == .radio, callState == .connected else { return }
        applyRadio(radioFloor.receive(text, now: ProcessInfo.processInfo.systemUptime))
    }
    private func applyRadio(_ messages: [String]) {
        guard callType == .radio else { return }
        for message in messages {
            if !WebRTCPeerService.shared.sendRadioControl(message) {
                radioFloor.reset(); radioReady = false; radioNotice = "Se perdió el canal de turnos. Vuelve a conectar Radio."
                break
            }
        }
        setMuted(!radioTransmitting)
        if let cue = radioCues.update(transmitting: radioTransmitting, receiving: radioReceiving) {
            CommunicationTones.shared.playRadio(cue)
        }
        radioLease?.cancel(); radioLease = nil
        if let deadline = radioFloor.deadline {
            radioLease = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(max(0, deadline - ProcessInfo.processInfo.systemUptime))) } catch { return }
                guard let self else { return }
                self.applyRadio(self.radioFloor.expire(now: ProcessInfo.processInfo.systemUptime))
            }
        }
    }
    public func toggleCamera() {
        guard callType == .video else { return }
        isCameraOff.toggle(); WebRTCPeerService.shared.setCameraEnabled(!isCameraOff)
    }
    public func flipCamera() { guard !isCameraOff else { return }; isFrontCamera.toggle(); WebRTCPeerService.shared.flipCamera() }
}
