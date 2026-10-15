//
//  OnlineMessagingService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import Combine
import CryptoKit

public enum OnlineConnectionStatus: String, Sendable {
    case online = "En línea"
    case connecting = "Conectando..."
    case offline = "Sin conexión"
}

public struct OnlineMessageEvent: Identifiable, Sendable {
    public let id: String
    public let conversationId: String
    public let senderMyaowId: String
    public let senderDisplayName: String
    public let text: String
    public let timestamp: Date
    public let messageType: String
    public let mediaBase64: String?
    public let mediaUrl: String?
    public let encryptedPayloadJSON: String?
    public let replyToId: String?
    
    public init(
        id: String,
        conversationId: String,
        senderMyaowId: String,
        senderDisplayName: String,
        text: String,
        timestamp: Date,
        messageType: String = "text",
        mediaBase64: String? = nil,
        mediaUrl: String? = nil,
        encryptedPayloadJSON: String? = nil,
        replyToId: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderMyaowId = senderMyaowId
        self.senderDisplayName = senderDisplayName
        self.text = text
        self.timestamp = timestamp
        self.messageType = messageType
        self.mediaBase64 = mediaBase64
        self.mediaUrl = mediaUrl
        self.encryptedPayloadJSON = encryptedPayloadJSON
        self.replyToId = replyToId
    }
}

/// Cliente WebSocket Nativo en Tiempo Real para el Relay Zero-Knowledge de Myaow
@MainActor
@Observable
public final class OnlineMessagingService: NSObject {
    public static let shared = OnlineMessagingService()
    
    public static var defaultServerHost: String {
        if let configured = Bundle.main.object(forInfoDictionaryKey: "MyaowRelayURL") as? String,
           RelayEndpoint(configured) != nil { return configured }
        #if DEBUG
        #if targetEnvironment(simulator)
        return "localhost:8080"
        #else
        return "192.168.101.108:8080"
        #endif
        #else
        return "" // Production must receive an explicit HTTPS origin at build time.
        #endif
    }

    public var status: OnlineConnectionStatus = .connecting
    public var latencyMs: Int = 0
    public var isRealtimeActive: Bool = false
    public private(set) var collaborationRevision = 0
    public private(set) var authenticationError: String?
    public var messagingError: String?
    public private(set) var sessionToken: String?
    
    public var relayHost: String {
        get {
            #if DEBUG
            let saved = UserDefaults.standard.string(forKey: "myaow_relay_host")
            #if !targetEnvironment(simulator)
            if let saved = saved, (saved.contains("localhost") || saved.contains("127.0.0.1")) {
                return Self.defaultServerHost
            }
            #endif
            return saved ?? Self.defaultServerHost
            #else
            // Distributed builds must not inherit a development server override.
            return Self.defaultServerHost
            #endif
        }
        set {
            #if DEBUG
            stopConnection()
            UserDefaults.standard.set(newValue, forKey: "myaow_relay_host")
            reconnect()
            #endif
        }
    }
    
    public var serverURL: URL {
        RelayEndpoint(relayHost)?.webSocketURL ?? URL(string: "ws://localhost:8080/ws")!
    }

    // Hooks de integración para SwiftData
    public var onMessageReceived: ((OnlineMessageEvent) -> Void)?
    public var onDeliveryAckReceived: ((String, String) -> Bool)? // true only after durable local status update
    public var onAvatarStatusReceived: ((String, String, String, String?) -> Void)? // (senderMyaowId, displayName, avatarStateName, avatarUrl)
    public var onTypingIndicatorReceived: ((String, String, Bool) -> Void)? // (senderMyaowId, displayName, isTyping)
    
    private var outbox: MessageOutbox {
        guard let base = RelayEndpoint(relayHost)?.supabaseAPIURL else { return MessageOutbox() }
        let scope = SHA256.hash(data: Data(base.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SupabaseOutbox-v1", isDirectory: true).appendingPathComponent(scope, isDirectory: true)
        return MessageOutbox(root: root)
    }
    private var outboxInFlight: [String: Date] = [:]
    private var groupReceipts: GroupReceiptStore { GroupReceiptStore(root: outbox.root.appendingPathComponent("GroupReceipts", isDirectory: true)) }
    private var groupReceiptOffset = 0

    func trackGroupDelivery(localID: String, packetIDs: [String]) throws {
        guard RelayEndpoint(relayHost)?.supabaseAPIURL != nil else { return }
        try groupReceipts.register(owner: IdentityManager.shared.currentIdentity.myaowId, localID: localID, packetIDs: packetIDs)
        if supabaseFailures == 0 { supabaseNextSync = min(supabaseNextSync, Date()) }
    }
    private var lastPingAt: Date?
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var pingTimer: AnyCancellable?
    private var reconnectAttempts: Int = 0
    private var isIntentionalDisconnect: Bool = false
    private var supabaseTask: Task<Void, Never>?
    private var supabaseRealtimeTask: Task<Void, Never>?
    private var supabaseRealtimeID = UUID()
    private var supabaseRealtimeNextAttempt = Date.distantPast
    private var supabaseRealtimeFailures = 0
    private var supabaseWakePending = false
    private var supabaseCollaborationPending = false
    private var supabaseNextCollaborationRefresh = Date.distantPast
    private var supabaseLastCollaborationRefresh = Date.distantPast
    private var supabaseGeneration = UUID()
    private var supabaseSyncing = false
    private var supabaseNextSync = Date.distantPast
    private var supabaseAccepted: Set<String> = []
    private var supabaseReceiptOffset = 0
    private var visibleConversations = Set<String>()
    private var supabaseFailures = 0
    private var supabaseSenderNames: [String: String] = [:]
    public func setConversationVisible(_ id: String, visible: Bool) {
        if visible { visibleConversations.insert(id) } else { visibleConversations.remove(id) }
        // Advance idle polling, but never bypass the failure/rate-limit backoff.
        if visible && supabaseFailures == 0 { supabaseNextSync = min(supabaseNextSync, Date()) }
    }

    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
        startConnectionHeartbeat()
    }
    
    private var hasActiveCall: Bool {
        ![.idle, .ended].contains(CallSessionService.shared.callState)
    }
    private var isNegotiatingCall: Bool {
        hasActiveCall && CallSessionService.shared.callState != .connected
    }
    private var canMaintainConnection: Bool {
        SupabaseSyncPolicy.keepsConnection(applicationActive: UIApplication.shared.applicationState == .active,
                                           callActive: hasActiveCall)
    }
    func callStateDidChange() {
        guard hasActiveCall else { return }
        // PushKit/CallKit may wake an existing task whose next chat poll was 60 seconds away.
        if supabaseFailures == 0 { supabaseNextSync = min(supabaseNextSync, Date()) }
        startConnectionHeartbeat()
        flushOutbox()
    }

    func waitUntilAuthenticated() async throws {
        if status == .online, sessionToken != nil { return }
        startConnectionHeartbeat()
        for _ in 0..<75 {
            try await Task.sleep(for: .milliseconds(200))
            if status == .online, sessionToken != nil { return }
        }
        throw URLError(.cannotConnectToHost)
    }
    public func reconnect() {
        stopConnection()
        reconnectAttempts = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.startConnectionHeartbeat()
        }
    }
    
    /// Inicia la conexión WebSocket con el Relay
    public func startConnectionHeartbeat() {
        guard IdentityManager.shared.hasCompletedOnboarding else { return }
        if let base = RelayEndpoint(relayHost)?.supabaseAPIURL {
            startSupabase(base)
            return
        }
        guard webSocketTask == nil else { return }
        
        guard let endpoint = RelayEndpoint(relayHost) else {
            authenticationError = "Configura la dirección HTTPS del servidor de Myaow para conectar."
            status = .offline
            return
        }
        self.status = .connecting
        self.isIntentionalDisconnect = false
        
        print("📡 [WebSocket] Conectando a \(serverURL)...")
        let wsTask = urlSession?.webSocketTask(with: endpoint.webSocketURL)
        self.webSocketTask = wsTask
        wsTask?.resume()
        
        // Autenticar la sesión con el Myaow ID local
        Task { @MainActor [weak self] in
            guard let self else { return }
            if IdentityManager.shared.isDirectoryRegistrationPending {
                guard await UserDirectoryService.shared.registerIdentityOnServer(identity: IdentityManager.shared.currentIdentity) else {
                    self.authenticationError = UserDirectoryService.shared.registrationError
                    self.stopConnection()
                    self.isIntentionalDisconnect = false
                    self.handleDisconnection()
                    return
                }
                IdentityManager.shared.isDirectoryRegistrationPending = false
            }
            guard self.webSocketTask === wsTask else { return }
            self.sendAuthPacket()
        }
        listenForIncomingMessages()
        startPingTimer()
    }
    
    /// Desconecta el WebSocket de forma intencional
    public func stopConnection() {
        if let base = RelayEndpoint(relayHost)?.supabaseAPIURL, let token = sessionToken {
            Task { _ = try? await SupabaseClient.request(base: base, path: "logout", token: token) }
        }
        isIntentionalDisconnect = true
        supabaseAccepted.removeAll()
        supabaseSenderNames.removeAll()
        supabaseReceiptOffset = 0
        groupReceiptOffset = 0
        supabaseFailures = 0
        supabaseGeneration = UUID()
        supabaseTask?.cancel()
        supabaseTask = nil
        stopSupabaseRealtime()
        supabaseRealtimeNextAttempt = .distantPast
        supabaseRealtimeFailures = 0
        supabaseWakePending = false
        supabaseCollaborationPending = false
        supabaseNextCollaborationRefresh = .distantPast
        supabaseSyncing = false
        supabaseNextSync = .distantPast
        pingTimer?.cancel()
        pingTimer = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        self.status = .offline
        self.isRealtimeActive = false
        self.sessionToken = nil
        self.lastPingAt = nil
    }
    
    /// Envía un paquete cifrado al servidor Relay en tiempo real
    public func sendOnlineMessage(
        messageId: String = UUID().uuidString,
        conversationId: String,
        recipientMyaowId: String,
        plaintext: String,
        messageType: String = "text",
        mediaBase64: String? = nil,
        mediaUrl: String? = nil,
        encryptedPayloadJSON: String? = nil,
        replyToId: String? = nil,
        decorationJSON: String? = nil,
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        Task { @MainActor in
            do {
                guard IdentityManager.shared.isInitialized else { throw SecureMessageError.keyUnavailable }
                let identity = IdentityManager.shared.currentIdentity
                if try outbox.packet(account: identity.myaowId, id: messageId) != nil {
                    flushOutbox()
                    completion(true)
                    return
                }
                let encrypted: String
                if let existing = encryptedPayloadJSON {
                    let envelope = try JSONDecoder().decode(SecureMessageEnvelope.self, from: Data(existing.utf8))
                    guard envelope.version == 2, envelope.messageId == messageId,
                          envelope.senderId == identity.myaowId, envelope.recipientId == recipientMyaowId else {
                        throw SecureMessageError.invalidEnvelope
                    }
                    encrypted = existing
                } else {
                    encrypted = try await SecureMessagingService.shared.seal(
                        .init(text: plaintext, messageType: messageType, mediaBase64: mediaBase64, mediaUrl: mediaUrl, replyToId: replyToId, decorationJSON: decorationJSON),
                        messageId: messageId, recipientId: recipientMyaowId)
                }
                // Only routing metadata and authenticated ciphertext leave the device.
                let packet: [String: Any] = [
                    "id": messageId, "type": "message", "messageType": "secure-v2",
                    "conversationId": conversationId, "senderMyaowId": identity.myaowId,
                    "senderDisplayName": identity.displayName, "recipientMyaowId": recipientMyaowId,
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "encryptedPayload": encrypted, "text": "Mensaje protegido"
                ]
                let json = String(decoding: try JSONSerialization.data(withJSONObject: packet), as: UTF8.self)
                try outbox.enqueue(json, account: identity.myaowId, id: messageId)
                MediaUploadService.shared.forgetPendingUpload(messageId: messageId, owner: identity.myaowId)
                flushOutbox()
                if status != .online { startConnectionHeartbeat() }
                completion(true)

            } catch {
                messagingError = "No pudimos proteger este mensaje. Se conserva en este dispositivo. Revisa la conexión y la identidad del contacto antes de reintentar."
                completion(false)
            }
        }
    }

    public func hasQueuedPacket(messageId: String) -> Bool {
        (try? outbox.packet(account: IdentityManager.shared.currentIdentity.myaowId, id: messageId)) != nil
    }

    public func flushOutbox() {
        if let base = RelayEndpoint(relayHost)?.supabaseAPIURL {
            let generation = supabaseGeneration
            Task { @MainActor [weak self] in
                guard let self else { return }
                do { try await self.syncSupabase(base, generation: generation) }
                catch { self.recordSupabaseError(error, generation: generation) }
            }
            return
        }
        guard let ws = webSocketTask, status == .online, sessionToken != nil else { return }
        do {
            for item in try outbox.pending(account: IdentityManager.shared.currentIdentity.myaowId) {
                guard outboxInFlight[item.id].map({ Date().timeIntervalSince($0) >= 30 }) ?? true else { continue }
                outboxInFlight[item.id] = Date()
                ws.send(.string(item.packet)) { [weak self] error in
                    guard error != nil else { return }
                    Task { @MainActor in self?.outboxInFlight.removeValue(forKey: item.id) }
                }
            }
        } catch {
            messagingError = "No pudimos leer los mensajes pendientes. Tu historial se conserva; vuelve a intentarlo."
        }
    }

    public func acknowledgeStoredMessage(id: String, senderId: String) {
        if let base = RelayEndpoint(relayHost)?.supabaseAPIURL, let token = sessionToken {
            let generation = supabaseGeneration
            Task { @MainActor [weak self] in
                do { _ = try await SupabaseClient.request(base: base, path: "messages/acknowledge", body: ["id": id, "senderId": senderId], token: token) }
                catch { self?.recordSupabaseError(error, generation: generation) }
            }
            return // A failed ACK is retried when the durable message is replayed.
        }
        guard let data = try? JSONSerialization.data(withJSONObject: ["type": "message_received", "messageId": id, "originalSenderId": senderId]) else { return }
        sendRawJSON(String(decoding: data, as: UTF8.self))
    }

    public func sendRawJSON(_ jsonString: String) {
        if let ws = webSocketTask, status == .online {
            ws.send(.string(jsonString)) { error in
                Task { @MainActor in
                    if let error = error {
                        print("❌ [WebSocket] Error sending raw JSON: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    public func sendMessageReaction(messageId: String, emoji: String, recipientMyaowId: String, completion: @escaping (Bool) -> Void = { _ in }) {
        sendMutation(.init(action: .react, targetId: messageId, text: emoji, date: Date()), recipient: recipientMyaowId, completion: completion)
    }

    /// Adds the Bearer auth header to a URLRequest if a session token is available
    public func authenticatedRequest(_ request: inout URLRequest) {
        if let token = sessionToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    
    /// Difunde la nueva emoción seleccionada por el usuario a todos los pares en tiempo real
    public func broadcastAvatarStateUpdate(newStateName: String) {
        var packet: [String: Any] = [
            "id": UUID().uuidString,
            "type": "avatar_status_update",
            "senderMyaowId": IdentityManager.shared.currentIdentity.myaowId,
            "senderDisplayName": IdentityManager.shared.currentIdentity.displayName,
            "avatarStateName": newStateName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let avatarUrl = IdentityManager.shared.profilePhotoUrl {
            packet["avatarUrl"] = avatarUrl
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: packet),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        webSocketTask?.send(.string(jsonString)) { _ in }
    }
    
    // MARK: - Protocolo de Comunicación
    private func sendAuthPacket() {
        let authPayload: [String: Any] = [
            "type": "auth",
            "myaowId": IdentityManager.shared.currentIdentity.myaowId,
            "displayName": IdentityManager.shared.currentIdentity.displayName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: authPayload),
           let string = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(string)) { error in
                Task { @MainActor in
                    if error == nil {
                        print("📡 [WebSocket] Solicitud de autenticación enviada como \(IdentityManager.shared.currentIdentity.myaowId)")
                    }
                }
            }
        }
    }
    
    /// Responde al challenge del servidor firmando el nonce con la llave de identidad
    private func handleAuthChallenge(nonce: String, serverPublicKeyHex: String) {
        let myaowId = IdentityManager.shared.currentIdentity.myaowId
        let displayName = IdentityManager.shared.currentIdentity.displayName
        guard let proof = try? RelayAuthentication.proof(myaowId: myaowId, privateKeyHex: IdentityManager.shared.privateKeyHex, nonce: nonce, serverPublicKeyHex: serverPublicKeyHex) else {
            authenticationError = "No se pudo comprobar tu identidad con este servidor."
            stopConnection()
            return
        }

        let responsePayload: [String: Any] = [
            "type": "auth_response",
            "myaowId": myaowId,
            "displayName": displayName,
            "proof": proof,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: responsePayload),
           let string = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(string)) { error in
                Task { @MainActor in
                    if error == nil {
                        print("🔐 [WebSocket] Respuesta de autenticación firmada enviada")
                    }
                }
            }
        }
    }
    
    /// Envía indicador de "escribiendo..." al destinatario
    public func sendTypingIndicator(recipientMyaowId: String, isTyping: Bool, groupId: String? = nil) {
        var packet: [String: Any] = [
            "type": isTyping ? "typing_start" : "typing_stop",
            "senderMyaowId": IdentityManager.shared.currentIdentity.myaowId,
            "senderDisplayName": IdentityManager.shared.currentIdentity.displayName,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        if let groupId = groupId {
            packet["groupId"] = groupId
        } else {
            packet["recipientMyaowId"] = recipientMyaowId
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: packet),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        webSocketTask?.send(.string(jsonString)) { _ in }
    }
    
    /// Envía confirmación de lectura (✓✓ azul) al remitente original
    public func sendReadReceipt(messageId: String, recipientMyaowId: String) {
        sendMutation(.init(action: .read, targetId: messageId, text: "", date: Date()), recipient: recipientMyaowId, completion: { _ in })
    }

    public func sendMessageDelete(messageId: String, recipientMyaowId: String, groupId: String? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        guard groupId == nil else {
            messagingError = "La eliminación en grupos todavía no está disponible."
            completion(false)
            return
        }
        sendMutation(.init(action: .delete, targetId: messageId, text: "", date: Date()), recipient: recipientMyaowId, completion: completion)
    }

    public func sendMessageEdit(messageId: String, newText: String, recipientMyaowId: String, completion: @escaping (Bool) -> Void = { _ in }) {
        sendMutation(.init(action: .edit, targetId: messageId, text: newText, date: Date()), recipient: recipientMyaowId, completion: completion)
    }

    private func sendMutation(_ mutation: SecureMessageMutation, recipient: String, completion: @escaping (Bool) -> Void) {
        do {
            try mutation.validate()
            let text = String(decoding: try JSONEncoder().encode(mutation), as: UTF8.self)
            sendOnlineMessage(conversationId: "", recipientMyaowId: recipient, plaintext: text, messageType: "control-v2", completion: completion)
        } catch {
            messagingError = "No pudimos preparar este cambio. El mensaje original se conserva."
            completion(false)
        }
    }

    private func startSupabase(_ base: URL) {
        guard supabaseTask == nil else { return }
        isIntentionalDisconnect = false
        let generation = UUID()
        supabaseGeneration = generation
        let owner = IdentityManager.shared.currentIdentity.myaowId
        supabaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled && self.supabaseGeneration == generation {
                if !self.canMaintainConnection {
                    self.stopSupabaseRealtime()
                    self.supabaseNextCollaborationRefresh = .distantPast
                    if self.supabaseFailures == 0, [.idle, .ended].contains(CallSessionService.shared.callState) { self.supabaseNextSync = .distantPast }
                } else {
                    if let token = self.sessionToken { self.startSupabaseRealtime(base, token: token, generation: generation) }
                    self.supabaseNextSync = SupabaseSyncPolicy.nextSync(current: self.supabaseNextSync,
                        now: Date(), failures: self.supabaseFailures,
                        wakePending: self.supabaseWakePending, negotiatingCall: self.isNegotiatingCall)
                    if UIApplication.shared.applicationState == .active && self.sessionToken != nil && (Date() >= self.supabaseNextCollaborationRefresh || (self.supabaseCollaborationPending && Date().timeIntervalSince(self.supabaseLastCollaborationRefresh) >= (self.hasActiveCall ? 15 : 2))) {
                        self.supabaseCollaborationPending = false
                        self.supabaseLastCollaborationRefresh = Date()
                        self.supabaseNextCollaborationRefresh = Date().addingTimeInterval(60)
                        self.collaborationRevision += 1
                    }
                }
                if self.canMaintainConnection && Date() >= self.supabaseNextSync {
                    do {
                        guard IdentityManager.shared.currentIdentity.myaowId == owner else { throw CancellationError() }
                        if self.sessionToken == nil {
                            self.status = .connecting
                            if IdentityManager.shared.isDirectoryRegistrationPending {
                                guard await UserDirectoryService.shared.registerIdentityOnServer(identity: IdentityManager.shared.currentIdentity) else {
                                    throw RelayRequestError(message: UserDirectoryService.shared.registrationError ?? "No pudimos registrar tu identidad.")
                                }
                                guard self.supabaseGeneration == generation else { throw CancellationError() }
                                IdentityManager.shared.isDirectoryRegistrationPending = false
                            }
                            let token = try await SupabaseClient.authenticate(base: base, id: owner, privateKeyHex: IdentityManager.shared.privateKeyHex)
                            guard self.supabaseGeneration == generation, IdentityManager.shared.currentIdentity.myaowId == owner else { throw CancellationError() }
                            self.sessionToken = token
                            self.authenticationError = nil
                            self.startSupabaseRealtime(base, token: token, generation: generation)
                            Task { await APNsNotificationManager.shared.refreshRegistration() }
                        }
                        self.status = .online
                        try await self.syncSupabase(base, generation: generation)
                        MyaowBackendEngine.shared.retryPendingMessages()
                    } catch {
                        if Task.isCancelled || self.supabaseGeneration != generation { break }
                        self.recordSupabaseError(error, generation: generation)
                    }
                }
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
            }
            if self.supabaseGeneration == generation { self.supabaseTask = nil }
        }
    }

    private func stopSupabaseRealtime() {
        supabaseRealtimeID = UUID()
        supabaseRealtimeTask?.cancel()
        supabaseRealtimeTask = nil
        isRealtimeActive = false
    }

    private func startSupabaseRealtime(_ base: URL, token: String, generation: UUID) {
        guard supabaseRealtimeTask == nil, Date() >= supabaseRealtimeNextAttempt else { return }
        let streamID = UUID()
        supabaseRealtimeID = streamID
        supabaseRealtimeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await SupabaseWakeupStream.run(base: base, token: token, onReady: { [weak self] in
                    await self?.supabaseDidWake(streamID: streamID, generation: generation, joined: true)
                }, onWake: { [weak self] in
                    await self?.supabaseDidWake(streamID: streamID, generation: generation, joined: false)
                })
            } catch { /* Reconciliation continues when Realtime is unavailable. */ }
            guard self.supabaseRealtimeID == streamID, self.supabaseGeneration == generation else { return }
            self.supabaseRealtimeTask = nil
            self.isRealtimeActive = false
            self.supabaseRealtimeFailures += 1
            self.supabaseRealtimeNextAttempt = Date().addingTimeInterval(SupabaseSyncPolicy.retryDelay(failures: self.supabaseRealtimeFailures, rateLimited: false) + Double.random(in: 0...2))
            if self.supabaseFailures == 0 { self.supabaseNextSync = min(self.supabaseNextSync, Date()) }
        }
    }

    private func supabaseDidWake(streamID: UUID, generation: UUID, joined: Bool) {
        guard supabaseRealtimeID == streamID, supabaseGeneration == generation,
              canMaintainConnection else { return }
        if joined { isRealtimeActive = true; supabaseRealtimeFailures = 0 }
        // Keep a hint received during an HTTP request for the next pass; never skip rate-limit backoff.
        supabaseWakePending = true
        supabaseCollaborationPending = true
        if hasActiveCall && supabaseFailures == 0 {
            supabaseNextSync = min(supabaseNextSync, Date())
            flushOutbox()
        }
    }

    private func recordSupabaseError(_ error: Error, generation: UUID) {
        guard supabaseGeneration == generation, !isIntentionalDisconnect else { return }
        if (error as? SupabaseHTTPError)?.status == 401 { sessionToken = nil; stopSupabaseRealtime() }
        status = .offline
        messagingError = error.localizedDescription
        if sessionToken == nil { authenticationError = error.localizedDescription }
        // Keep the same ciphertext in the durable outbox across outages/limits.
        supabaseFailures += 1
        supabaseNextSync = Date().addingTimeInterval(SupabaseSyncPolicy.retryDelay(failures: supabaseFailures, rateLimited: (error as? SupabaseHTTPError)?.status == 429))
    }

    private func syncSupabase(_ base: URL, generation: UUID) async throws {
        guard generation == supabaseGeneration, !supabaseSyncing, Date() >= supabaseNextSync,
              canMaintainConnection, let token = sessionToken else { return }
        supabaseSyncing = true
        supabaseWakePending = false
        supabaseNextSync = Date().addingTimeInterval(3)
        defer { if generation == supabaseGeneration { supabaseSyncing = false } }
        let owner = IdentityManager.shared.currentIdentity.myaowId
        func stillCurrent() throws {
            guard generation == supabaseGeneration, sessionToken == token,
                  IdentityManager.shared.currentIdentity.myaowId == owner,
                  RelayEndpoint(relayHost)?.supabaseAPIURL == base else { throw CancellationError() }
        }
        let pending = try outbox.pending(account: owner, limit: 1000).map { item -> (id: String, packet: String) in
            guard let packet = try JSONSerialization.jsonObject(with: Data(item.packet.utf8)) as? [String: Any], let id = packet["id"] as? String else { throw SecureMessageError.invalidEnvelope }
            return (id, item.packet)
        }
        // Rotate receipt checks so an offline recipient cannot starve new sends.
        let unconfirmed = pending.filter { !supabaseAccepted.contains($0.id) }
        let waiting = pending.filter { supabaseAccepted.contains($0.id) }
        let offset = waiting.isEmpty ? 0 : supabaseReceiptOffset % waiting.count
        let rotated = Array(waiting.dropFirst(offset)) + Array(waiting.prefix(offset))
        let groupWaiting = try groupReceipts.entries(owner: owner).flatMap { $0.packetIDs.subtracting($0.delivered).sorted() }
        let groupOffset = groupWaiting.isEmpty ? 0 : groupReceiptOffset % groupWaiting.count
        let groupChecked = Array((Array(groupWaiting.dropFirst(groupOffset)) + Array(groupWaiting.prefix(groupOffset))).prefix(40))
        groupReceiptOffset = groupOffset + 40
        let directLimit = 80 - groupChecked.count
        let checked = Array(unconfirmed.prefix(20)) + Array(rotated.prefix(directLimit))
        supabaseReceiptOffset = offset + directLimit
        let started = Date()
        let data = try await SupabaseClient.request(base: base, path: "messages/sync", body: ["ids": checked.map(\.id) + groupChecked, "activeCallId": CallSessionService.shared.currentCallUUID?.uuidString as Any? ?? NSNull()], token: token)
        try stillCurrent()
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let receipts = result["receipts"] as? [[String: Any]], let messages = result["messages"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        for signal in (result["callSignals"] as? [[String: Any]] ?? []) {
            CallSystemCoordinator.shared.receive(signal)
        }
        let known = Set(receipts.compactMap { $0["id"] as? String })
        let directIDs = Set(checked.map { $0.id.uppercased() })
        for receipt in receipts {
            guard let id = receipt["id"] as? String, directIDs.contains(id.uppercased()), let state = receipt["status"] as? String else { continue }
            supabaseAccepted.insert(id)
            if onDeliveryAckReceived?(id, state) == true, state == "delivered" {
                try outbox.acknowledge(account: owner, id: id)
                supabaseAccepted.remove(id)
            }
        }
        let deliveredGroupIDs = Set(receipts.compactMap { row -> String? in row["status"] as? String == "delivered" ? row["id"] as? String : nil })
        try groupReceipts.apply(deliveredGroupIDs, owner: owner) { onDeliveryAckReceived?($0, "delivered") == true }
        for item in unconfirmed.prefix(20).filter({ !known.contains($0.id) }).prefix(5) {
            guard let packet = try JSONSerialization.jsonObject(with: Data(item.packet.utf8)) as? [String: Any],
                  let encrypted = packet["encryptedPayload"] as? String,
                  let envelope = try JSONSerialization.jsonObject(with: Data(encrypted.utf8)) as? [String: Any] else { throw SecureMessageError.invalidEnvelope }
            let accepted = try await SupabaseClient.request(base: base, path: "messages/send", body: ["envelope": envelope], token: token)
            try stillCurrent()
            if let receipt = try JSONSerialization.jsonObject(with: accepted) as? [String: Any], let state = receipt["status"] as? String {
                supabaseAccepted.insert(item.id)
                if onDeliveryAckReceived?(item.id, state) == true, state == "delivered" {
                    try outbox.acknowledge(account: owner, id: item.id)
                    supabaseAccepted.remove(item.id)
                }
            }
        }
        let dates = ISO8601DateFormatter(); dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for row in messages.prefix(5) {
            guard let id = row["id"] as? String, let sender = row["sender"] as? String,
                  let envelope = row["envelope"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
            if supabaseSenderNames[sender] == nil {
                let profileData = try await SupabaseClient.request(base: base, path: "directory/lookup", body: ["username": sender], token: token)
                try stillCurrent()
                let profile = try JSONDecoder().decode(DirectoryUserResult.self, from: profileData)
                guard profile.myaowId == sender else { throw SecureMessageError.invalidEnvelope }
                supabaseSenderNames[sender] = profile.displayName
            }
            let encrypted = String(decoding: try JSONSerialization.data(withJSONObject: envelope), as: UTF8.self)
            onMessageReceived?(OnlineMessageEvent(id: id, conversationId: envelope["groupId"] as? String ?? sender,
                senderMyaowId: sender, senderDisplayName: supabaseSenderNames[sender] ?? sender, text: "Mensaje protegido",
                timestamp: (row["created_at"] as? String).flatMap { dates.date(from: $0) } ?? Date(),
                messageType: "secure-v2", encryptedPayloadJSON: encrypted))
        }
        supabaseFailures = 0
        supabaseNextSync = Date().addingTimeInterval(SupabaseSyncPolicy.interval(conversationVisible: !visibleConversations.isEmpty, hasBacklog: !messages.isEmpty || !pending.isEmpty, realtime: isRealtimeActive))
        if ![.idle, .ended].contains(CallSessionService.shared.callState) {
            supabaseNextSync = min(supabaseNextSync, Date().addingTimeInterval(CallSessionService.shared.callState == .connected ? 10 : 1))
        }
        latencyMs = Int(Date().timeIntervalSince(started) * 1000)
        status = .online
        authenticationError = nil
    }

    private func listenForIncomingMessages() {
        guard let listeningSocket = webSocketTask else { return }
        listeningSocket.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard self?.webSocketTask === listeningSocket else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self?.handleIncomingRawJSON(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self?.handleIncomingRawJSON(text)
                        }
                    @unknown default:
                        break
                    }
                    // Seguir escuchando el siguiente mensaje
                    self?.listenForIncomingMessages()
                    
                case .failure(let error):
                    print("⚠️ [WebSocket] Conexión interrumpida (\(error.localizedDescription)).")
                    self?.handleDisconnection()
                }
            }
        }
    }
    
    private func handleIncomingRawJSON(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "auth_challenge":
            guard json["protocol"] as? String == RelayAuthentication.protocolName,
                  let nonce = json["nonce"] as? String,
                  let serverPublicKeyHex = json["serverPublicKeyHex"] as? String else {
                authenticationError = "El servidor necesita actualizar su autenticación."
                stopConnection()
                return
            }
            handleAuthChallenge(nonce: nonce, serverPublicKeyHex: serverPublicKeyHex)

        case "auth_ack":
            self.authenticationError = nil
            self.status = .online
            self.isRealtimeActive = true
            self.reconnectAttempts = 0
            if let token = json["sessionId"] as? String {
                self.sessionToken = token
            }
            print("✅ [WebSocket] Sesión autenticada en el servidor Relay v2.")
            outboxInFlight.removeAll()
            flushOutbox()
            MyaowBackendEngine.shared.retryPendingMessages()
            Task { await APNsNotificationManager.shared.refreshRegistration() }
            if IdentityManager.shared.isDirectoryRegistrationPending {
                Task { @MainActor in
                    if await UserDirectoryService.shared.registerIdentityOnServer(identity: IdentityManager.shared.currentIdentity) {
                        IdentityManager.shared.isDirectoryRegistrationPending = false
                    }
                }
            }
            if IdentityManager.shared.hasCompletedOnboarding,
               IdentityManager.shared.profilePhotoUrl == nil {
                IdentityManager.shared.uploadProfilePhoto()
            }
            
        case "call_signal":
            CallSystemCoordinator.shared.receive(json)

        case "auth_error":
            let message = (json["message"] as? String) ?? "Error desconocido"
            authenticationError = message
            stopConnection()
            print("❌ [WebSocket] Error de autenticación: \(message)")
            
        case "typing_start", "typing_stop":
            if let senderMyaowId = json["senderMyaowId"] as? String {
                let displayName = (json["senderDisplayName"] as? String) ?? senderMyaowId
                let isTyping = (type == "typing_start")
                self.onTypingIndicatorReceived?(senderMyaowId, displayName, isTyping)
            }
            
        case "read_ack", "message_delete", "message_edit", "message_reaction":
            // Message state only changes through authenticated, persisted control envelopes.
            break

        case "task_update":
            GroupTasksService.shared.revision += 1

        case "call_offer", "call_answer", "call_hangup", "call_reaction", "webrtc_offer", "webrtc_answer", "webrtc_ice_candidate":
            break // Legacy raw signaling cannot control a call.

        case "walkie_audio":
            // Legacy unauthenticated Internet audio is not part of local Radio.
            break
            
        case "message", "nudge", "voice", "media", "image", "video":
            if let senderMyaowId = json["senderMyaowId"] as? String,
               let convId = json["conversationId"] as? String,
               let text = json["text"] as? String {
                let displayName = (json["senderDisplayName"] as? String) ?? "Contacto"
                let id = (json["id"] as? String) ?? UUID().uuidString
                let msgType = (json["messageType"] as? String) ?? (type == "message" ? "text" : type)
                let mediaBase64 = json["mediaBase64"] as? String
                let mediaUrl = json["mediaUrl"] as? String
                let encryptedPayload = json["encryptedPayload"] as? String
                let replyToId = json["replyToId"] as? String
                
                let event = OnlineMessageEvent(
                    id: id,
                    conversationId: convId,
                    senderMyaowId: senderMyaowId,
                    senderDisplayName: displayName,
                    text: text,
                    timestamp: (json["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date(),
                    messageType: msgType,
                    mediaBase64: mediaBase64,
                    mediaUrl: mediaUrl,
                    encryptedPayloadJSON: encryptedPayload,
                    replyToId: replyToId
                )
                self.onMessageReceived?(event)
            }
            
        case "delivery_ack":
            if let msgId = json["messageId"] as? String,
               let ackStatus = json["status"] as? String {
                guard ["queued_on_server", "delivered"].contains(ackStatus) else { return }
                guard self.onDeliveryAckReceived?(msgId, ackStatus) == true else { return }
                do { try outbox.acknowledge(account: IdentityManager.shared.currentIdentity.myaowId, id: msgId) }
                catch { messagingError = "No pudimos actualizar la cola de envío. Se reintentará sin duplicar el mensaje." }
                outboxInFlight.removeValue(forKey: msgId)
                flushOutbox()
            }
            
        case "message_error":
            if let id = json["messageId"] as? String { outboxInFlight.removeValue(forKey: id) }
            messagingError = "El servidor no aceptó un mensaje. Sigue pendiente en este dispositivo; revisa la conexión y el contacto."

        case "avatar_status_update":
            if let senderMyaowId = json["senderMyaowId"] as? String,
               let stateName = json["avatarStateName"] as? String {
                let displayName = (json["senderDisplayName"] as? String) ?? senderMyaowId
                let avatarUrl = json["avatarUrl"] as? String
                self.onAvatarStatusReceived?(senderMyaowId, displayName, stateName, avatarUrl)
            }
            
        case "pong":
            if let sent = lastPingAt { latencyMs = max(0, Int(Date().timeIntervalSince(sent) * 1000)) }
            lastPingAt = nil
            
        default:
            break
        }
    }
    
    private func handleDisconnection() {
        guard !isIntentionalDisconnect else { return }
        
        self.status = .offline
        self.isRealtimeActive = false
        self.webSocketTask = nil
        self.sessionToken = nil
        self.lastPingAt = nil
        pingTimer?.cancel()
        pingTimer = nil
        
        // Bounded exponential backoff with jitter; a long outage must not disable reconnection permanently.
        let delay = min(60.0, pow(1.7, Double(reconnectAttempts))) + Double.random(in: 0.5...2.5)
        reconnectAttempts = min(reconnectAttempts + 1, 12)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.status == .offline else { return }
            self?.startConnectionHeartbeat()
        }
    }
    
    private func startPingTimer() {
        pingTimer?.cancel()
        pingTimer = Timer.publish(every: 25.0, on: .main, in: .common)
        .autoconnect()
        .sink { [weak self] _ in
            guard let self, self.status == .online else { return }
            if let sent = self.lastPingAt, Date().timeIntervalSince(sent) > 45 {
                self.reconnect()
                return
            }
            self.flushOutbox()
            MyaowBackendEngine.shared.retryPendingMessages()
            Task { await APNsNotificationManager.shared.refreshRegistration() }
            guard self.lastPingAt == nil else { return }
            self.lastPingAt = Date()
            let ping: [String: String] = ["type": "ping"]
            if let data = try? JSONSerialization.data(withJSONObject: ping),
               let str = String(data: data, encoding: .utf8) {
                self.webSocketTask?.send(.string(str)) { _ in }
            }
        }
    }
}
