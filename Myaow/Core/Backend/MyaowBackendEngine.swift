//
//  MyaowBackendEngine.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData
import CryptoKit

@MainActor
@Observable
public final class MyaowBackendEngine {
    private var receivingMessageIDs = Set<String>()
    public static let shared = MyaowBackendEngine()
    
    public private(set) var activeSessionsCount: Int = 0
    public var isEngineRunning: Bool = false
    public var isOnlineMode: Bool = true
    
    private var isListenerConfigured: Bool = false
    private var messageContext: ModelContext?
    private var retryInProgress = false
    private var nextRetryPass = Date.distantPast
    
    private init() {
        startBackendEngine()
    }
    
    public func startBackendEngine() {
        guard !isEngineRunning else { return }
        self.isEngineRunning = true
        
        // Iniciar servicios de malla local y relay en línea
        MeshNetworkService.shared.startMeshServices()
        OnlineMessagingService.shared.startConnectionHeartbeat()
    }
    
    /// Configura el receptor global de mensajes en vivo conectado a la base de datos de SwiftData
    public func configureIncomingListener(context: ModelContext) {
        nonisolated(unsafe) let context = context
        guard !isListenerConfigured else { return }
        self.isListenerConfigured = true
        self.messageContext = context
        retryPendingMessages()
        
        ScheduledMessagesService.shared.onHistoryUpdate = { items in
            do {
                let owner = IdentityManager.shared.currentIdentity.myaowId
                var conversations = try context.fetch(FetchDescriptor<ConversationModel>())
                for item in items {
                    let messageId = item.id.uuidString
                    let existing = try context.fetch(FetchDescriptor<MessageModel>(predicate: #Predicate { $0.id == messageId })).first
                    if let existing {
                        guard existing.isOutgoing, existing.senderId == owner else { continue }
                        if item.state == "delivered", existing.deliveryStatus != .read { existing.deliveryStatus = .delivered }
                        continue
                    }
                    let conversation = conversations.first { $0.id == item.conversationId } ?? ConversationModel(
                        id: item.conversationId, title: item.recipientName, recipientMyaowId: item.recipientId ?? "", isGroup: item.groupId != nil)
                    if !conversations.contains(where: { $0.id == conversation.id }) { context.insert(conversation); conversations.append(conversation) }
                    conversation.messages.append(MessageModel(id: messageId, conversationId: conversation.id,
                        senderId: owner, senderName: "Yo", isOutgoing: true, text: item.text, timestamp: item.scheduledDate,
                        deliveryStatusRaw: item.state == "delivered" ? "delivered" : "sent"))
                    if item.scheduledDate >= conversation.lastMessageTimestamp || conversation.messages.count == 1 {
                        conversation.lastMessageSnippet = item.text; conversation.lastMessageTimestamp = item.scheduledDate
                    }
                }
                try context.save()
            } catch {
                context.rollback()
                OnlineMessagingService.shared.messagingError = "El mensaje sigue en el servidor, pero no pudimos actualizar el historial de este dispositivo."
            }
        }

        OnlineMessagingService.shared.onMessageReceived = { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                let key = event.senderMyaowId + ":" + event.id
                guard self.receivingMessageIDs.insert(key).inserted else { return }
                defer { self.receivingMessageIDs.remove(key) }
                if await self.handleIncomingMessageEvent(event, context: context) == true {
                    OnlineMessagingService.shared.acknowledgeStoredMessage(id: event.id, senderId: event.senderMyaowId)
                }
            }
        }
        
        OnlineMessagingService.shared.onAvatarStatusReceived = { [weak self] senderId, displayName, stateName, avatarUrl in
            Task { @MainActor in
                self?.updateContactAvatarState(myaowId: senderId, displayName: displayName, avatarState: stateName, avatarUrl: avatarUrl, context: context)
            }
        }
        
        // 📦 Delivery ACK Real: Actualizar estado del mensaje cuando el servidor confirma entrega
        OnlineMessagingService.shared.onDeliveryAckReceived = { messageId, status in
            do {
                let descriptor = FetchDescriptor<MessageModel>(predicate: #Predicate { $0.id == messageId })
                if let msg = try context.fetch(descriptor).first, msg.isOutgoing {
                    switch status {
                    case "delivered":
                        if msg.deliveryStatus != .read { msg.deliveryStatus = .delivered }
                    case "queued_on_server":
                        if ![.delivered, .read].contains(msg.deliveryStatus) { msg.deliveryStatus = .sent }
                    default: return false
                    }
                    try context.save()
                }
                return true
            } catch {
                context.rollback()
                OnlineMessagingService.shared.messagingError = "No pudimos guardar la confirmación. El mensaje se conserva para reintentar."
                return false
            }
        }

        NotificationCenter.default.addObserver(forName: .didReceiveMeshPacket, object: nil, queue: .main) { [weak self] notification in
            guard let packet = notification.object as? MeshDataPacket else { return }
            if packet.type == .message {
                let event = OnlineMessageEvent(
                    id: packet.id,
                    conversationId: "",
                    senderMyaowId: packet.senderMyaowId,
                    senderDisplayName: packet.senderMyaowId,
                    text: "",
                    timestamp: packet.timestamp,
                    messageType: "text",
                    mediaBase64: nil,
                    mediaUrl: nil,
                    encryptedPayloadJSON: packet.payload
                )
                Task { @MainActor [weak self] in
                    guard await self?.handleIncomingMessageEvent(event, context: context) == true else { return }
                    
                    // Send delivery ACK back via mesh
                    let ackPacket = MeshDataPacket(
                        id: UUID().uuidString,
                        type: .deliveryAck,
                        senderMyaowId: IdentityManager.shared.currentIdentity.myaowId,
                        recipientMyaowId: packet.senderMyaowId,
                        payload: packet.id,
                        timestamp: Date()
                    )
                    MeshNetworkService.shared.broadcastPacket(ackPacket)
                }
            }
        }
    }
    
    public func updateContactAvatarState(myaowId: String, displayName: String, avatarState: String, avatarUrl: String? = nil, context: ModelContext) {
        let descriptor = FetchDescriptor<ContactModel>()
        let contacts = (try? context.fetch(descriptor)) ?? []
        
        let matchingContacts = contacts.filter {
            !myaowId.isEmpty && $0.myaowId == myaowId
        }
        
        let _ = MyaowCatState(rawValue: avatarState) ?? .friendly
        
        if let contact = matchingContacts.first {
            contact.avatarCatState = avatarState
            if let newUrl = avatarUrl {
                contact.avatarUrl = newUrl
            }
            try? context.save()
            print("🐱 [BackendEngine] Estado de ánimo de \(contact.displayName) actualizado a \(avatarState)")
        }
    }
    
    private func handleIncomingMessageEvent(_ wireEvent: OnlineMessageEvent, context: ModelContext) async -> Bool {
        guard let encrypted = wireEvent.encryptedPayloadJSON else {
            OnlineMessagingService.shared.messagingError = "Se rechazó un mensaje sin protección. El contacto necesita actualizar Myaow."
            return false
        }
        let content: SecureMessageContent
        do {
            content = try await SecureMessagingService.shared.open(encrypted, messageId: wireEvent.id, senderId: wireEvent.senderMyaowId)
        } catch {
            OnlineMessagingService.shared.messagingError = "No pudimos verificar un mensaje recibido. No se modificó tu historial."
            return false
        }
        let event = OnlineMessageEvent(id: wireEvent.id, conversationId: wireEvent.conversationId,
            senderMyaowId: wireEvent.senderMyaowId, senderDisplayName: wireEvent.senderDisplayName,
            text: content.text, timestamp: wireEvent.timestamp, messageType: content.messageType,
            mediaBase64: content.mediaBase64, mediaUrl: content.mediaUrl, replyToId: content.replyToId)
        let eventText = event.text
        if content.messageType == "call-signal-v2", let data = eventText.data(using: .utf8),
           let signal = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = signal["type"] as? String, type.hasPrefix("call_") || type.hasPrefix("webrtc_") {
            CallSessionService.shared.handleSignalingEvent(type: type, senderMyaowId: event.senderMyaowId,
                                                         senderName: event.senderDisplayName, data: signal)
            return true
        }
        if content.messageType == "call-signal-v2" { return true }
        let messageId = event.id
        do {
            if let existing = try context.fetch(FetchDescriptor<MessageModel>(predicate: #Predicate { $0.id == messageId })).first {
                // Global model IDs must never let another sender replace existing content.
                return !existing.isOutgoing && existing.senderId == event.senderMyaowId
            }
        } catch { return false }
        var decoration: ChatDecorationEvent?
        if content.messageType == "theme-v1" {
            guard let decoded = ChatDecorationEvent.decode(content.decorationJSON), content.mediaUrl == nil, content.mediaBase64 == nil else { return true }
            do {
                try decoded.validate(sender: event.senderMyaowId, recipient: IdentityManager.shared.currentIdentity.myaowId, groupID: content.groupId)
            } catch { return true } // Authenticated but invalid events must not block the inbox.
            if let group = content.groupId {
                do {
                    let members = try await GroupDeliveryService.members(group)
                    let roles = Dictionary(members.map { ($0.myaow_id, $0.role) }, uniquingKeysWith: { first, _ in first })
                    guard ChatDecorationEvent.canEditGroup(actor: event.senderMyaowId, recipient: IdentityManager.shared.currentIdentity.myaowId, roles: roles) else { return true }
                } catch {
                    if (error as? SupabaseHTTPError)?.status == 403 { return true }
                    return false // Retry transient failures without trusting cached permissions.
                }
            }
            decoration = decoded
        }
        // Download before acknowledging: a receipt promises durable content, including attachments.
        var verifiedMedia = content.mediaBase64.flatMap { Data(base64Encoded: $0) }
        if let url = content.mediaUrl, verifiedMedia == nil {
            guard let downloaded = await MediaUploadService.shared.downloadMedia(from: url) else {
                OnlineMessagingService.shared.messagingError = "Un archivo sigue pendiente de descarga. Se volverá a recibir al reconectar."
                return false
            }
            verifiedMedia = downloaded
        }
        if content.messageType == "control-v2" {
            do {
                let change = try JSONDecoder().decode(SecureMessageMutation.self, from: Data(content.text.utf8))
                let members: Set<String>?
                if let group = content.groupId {
                    members = Set(try await GroupDeliveryService.members(group).map(\.myaow_id))
                } else { members = nil }
                return try SecureMutationStore.apply(change, controlId: event.id,
                    senderId: event.senderMyaowId, context: context, groupId: content.groupId, groupMembers: members)
            } catch {
                context.rollback()
                return false
            }
        }
        // 1. Buscar TODAS las conversaciones coincidentes con este contacto
        let descriptor = FetchDescriptor<ConversationModel>()
        let allConvs = (try? context.fetch(descriptor)) ?? []
        
        let matchingConvs = allConvs.filter { conv in
            content.groupId.map { conv.isGroup && conv.id.lowercased() == $0.lowercased() } ?? (!conv.isGroup && conv.recipientMyaowId == event.senderMyaowId)
        }
        
        var primaryConv: ConversationModel
        
        if matchingConvs.isEmpty {
            // Crear nueva conversación canónica
            let newConv = ConversationModel(
                id: content.groupId.flatMap { UUID(uuidString: $0)?.uuidString } ?? UUID().uuidString,
                title: content.groupId == nil ? event.senderDisplayName : "Grupo",
                recipientMyaowId: content.groupId ?? event.senderMyaowId,
                isGroup: content.groupId != nil,
                unreadCount: 0,
                lastMessageSnippet: eventText,
                lastMessageTimestamp: event.timestamp,
                isMeshConnected: false,
                nodeCount: 1,
                participantNames: [event.senderDisplayName]
            )
            context.insert(newConv)
            primaryConv = newConv
        } else {
            // Tomar la primera como canónica
            primaryConv = matchingConvs[0]
            if primaryConv.recipientMyaowId.isEmpty && !event.senderMyaowId.isEmpty {
                primaryConv.recipientMyaowId = event.senderMyaowId
            }
            if primaryConv.title.isEmpty || primaryConv.title == event.senderMyaowId {
                primaryConv.title = event.senderDisplayName
            }
            
        }
        
        // 2. Determinar tipo de mensaje y datos binarios
        let msgType = event.messageType

        let mediaData = verifiedMedia

        // 3. Crear el mensaje recibido
        let incomingMsg = MessageModel(
            id: event.id,
            conversationId: primaryConv.id,
            senderId: event.senderMyaowId,
            senderName: event.senderDisplayName,
            isOutgoing: false,
            text: eventText,
            timestamp: event.timestamp,
            deliveryStatusRaw: MessageDeliveryStatus.delivered.rawValue,
            messageTypeRaw: msgType,
            mediaData: mediaData,
            moderationStatusRaw: "approved",
            replyToId: event.replyToId
        )
        
            if let reference = content.groupMessageId, content.groupId != nil, UUID(uuidString: reference) != nil {
                incomingMsg.groupMessageId = reference
            }
            if let decoration {
                do {
                    try ChatDecorationStore.apply(decoration, to: primaryConv)
                    incomingMsg.decorationJSON = try decoration.json
                    incomingMsg.text = "Cambió la decoración a \(decoration.decoration.title)."
                } catch { context.rollback(); return false }
            }
            primaryConv.messages.append(incomingMsg)
            if event.timestamp >= primaryConv.lastMessageTimestamp {
                switch msgType {
                case "image": primaryConv.lastMessageSnippet = "📷 Fotografía"
                case "video": primaryConv.lastMessageSnippet = "🎥 Video"
                case "voice": primaryConv.lastMessageSnippet = "🎤 Nota de voz"
                case "rawFile": primaryConv.lastMessageSnippet = "Archivo: " + eventText
                case "theme-v1": primaryConv.lastMessageSnippet = incomingMsg.text
                default: primaryConv.lastMessageSnippet = eventText
                }
                primaryConv.lastMessageTimestamp = event.timestamp
            }
            primaryConv.unreadCount += 1
            do { try context.save() }
            catch {
                context.rollback()
                OnlineMessagingService.shared.messagingError = "No pudimos guardar el mensaje. No se confirmó su entrega; se volverá a intentar."
                return false
            }
            
            // Sonido de recepción discreto y háptico
            if msgType == "nudge" {
                MyaowNudgeService.shared.receive(senderName: event.senderDisplayName, text: eventText, timestamp: event.timestamp)
            } else if UIApplication.shared.applicationState == .active {
                MyaowSoundEffectsService.shared.playMessageReceivedEffect()
            }
            
        return true
    }
    
    /// Persists before dispatch; authenticated HPKE envelopes work independently across reconnects.
    @discardableResult
    public func dispatchSecureMessage(
        conversation: ConversationModel,
        text: String,
        context: ModelContext,
        recipientMyaowId: String,
        recipientPublicKeyHex: String = "",
        replyToId: String? = nil,
        replyToText: String? = nil,
        replyToSender: String? = nil,
        messageType: String = "text"
    ) -> Bool {
        nonisolated(unsafe) let context = context
        guard text.utf8.count <= 64 * 1024, !conversation.isGroup,
              messageType == "text" || (messageType == "sticker" && MyaowSticker.match(text) != nil) || (messageType == "nudge" && CatVocalSynthesizer.CatSoundType.from(message: text) != nil) else {
            OnlineMessagingService.shared.messagingError = conversation.isGroup ? "El envío protegido a grupos todavía no está disponible." : "Este mensaje es demasiado largo. Divídelo en mensajes más cortos."
            return false
        }
        let actualRecipientId = recipientMyaowId.isEmpty ? conversation.recipientMyaowId : recipientMyaowId
        // 2. Crear mensaje en SwiftData
        let message = MessageModel(
            conversationId: conversation.id,
            senderId: IdentityManager.shared.currentIdentity.myaowId,
            senderName: "Yo",
            isOutgoing: true,
            text: text,
            timestamp: Date(),
            deliveryStatusRaw: MessageDeliveryStatus.sending.rawValue,
            messageTypeRaw: messageType,
            moderationStatusRaw: "approved",
            replyToId: replyToId,
            replyToText: replyToText,
            replyToSender: replyToSender
        )
        
        conversation.messages.append(message)
        conversation.lastMessageSnippet = text
        conversation.lastMessageTimestamp = Date()
        do { try context.save() }
        catch {
            context.rollback()
            OnlineMessagingService.shared.messagingError = "No se pudo guardar el mensaje. Conserva el borrador e inténtalo nuevamente."
            return false
        }
        
        // Sonido de envío pop limpio
        if messageType != "nudge" { MyaowSoundEffectsService.shared.playMessageSentEffect() }
        
        Task { @MainActor in
            do {
                let encrypted = try await SecureMessagingService.shared.seal(
                    .init(text: text, messageType: messageType, replyToId: replyToId),
                    messageId: message.id, recipientId: actualRecipientId, suppliedKey: recipientPublicKeyHex)
                OnlineMessagingService.shared.sendOnlineMessage(messageId: message.id,
                    conversationId: conversation.id, recipientMyaowId: actualRecipientId,
                    plaintext: "", encryptedPayloadJSON: encrypted) { success in
                    if ![.sent, .delivered, .read].contains(message.deliveryStatus) { message.deliveryStatus = .queued }
                    if OnlineMessagingService.shared.status != .online {
                        if !MeshNetworkService.shared.connectedPeers.isEmpty {
                            MeshNetworkService.shared.broadcastPacket(MeshDataPacket(id: message.id, type: .message,
                                senderMyaowId: IdentityManager.shared.currentIdentity.myaowId,
                                recipientMyaowId: actualRecipientId, payload: encrypted, timestamp: Date()))
                        }
                    }
                    try? context.save()
                }
            } catch {
                message.deliveryStatus = .queued
                try? context.save()
                OnlineMessagingService.shared.messagingError = "No pudimos proteger el mensaje. Se guardó como pendiente; no se envió sin cifrar."
            }
        }
        return true
    }

    private func retryGroupMessage(_ message: MessageModel, conversation: ConversationModel,
                                   context: ModelContext, account: String, host: String) async {
        let outbox = GroupMessageOutbox()
        func isCurrent() -> Bool {
            account == IdentityManager.shared.currentIdentity.myaowId && host == OnlineMessagingService.shared.relayHost
        }
        do {
            let packets: [[String: Any]]
            if let saved = try outbox.load(owner: account, host: host, id: message.id) {
                packets = saved
            } else {
                var mediaUrl: String?
                var groupReaders: [String]?
                if let media = message.mediaData {
                    guard let upload = await MediaUploadService.shared.uploadMedia(data: media, filename: "attachment.bin",
                        contentType: "application/octet-stream", groupId: conversation.id, messageId: message.id) else { return }
                    mediaUrl = upload.mediaUrl
                    groupReaders = upload.groupReaders
                } else if ["image", "video", "voice", "rawFile"].contains(message.messageTypeRaw) { return }
                guard isCurrent() else { return }
                message.groupMessageId = message.id
                try context.save()
                packets = try await GroupDeliveryService.packets(text: message.text, recipientId: nil,
                    groupId: conversation.id, messageType: message.messageTypeRaw, mediaUrl: mediaUrl, recipientIDs: groupReaders, replyToId: message.replyToId, groupMessageId: message.groupMessageId, decorationJSON: message.decorationJSON)
                guard isCurrent() else { return }
                try outbox.save(packets, owner: account, host: host, id: message.id)
            }
            // Register before posting so a fast recipient cannot outrun receipt tracking.
            try OnlineMessagingService.shared.trackGroupDelivery(localID: message.id, packetIDs: packets.compactMap { $0["id"] as? String })
            _ = try await RelayAPI.request("/api/v1/messages-v2/batch", method: "POST", body: ["packets": packets])
            guard isCurrent() else { return }
            let priorStatus = message.deliveryStatus
            if ![.delivered, .read].contains(priorStatus) { message.deliveryStatus = .sent }
            do { try context.save() }
            catch { message.deliveryStatus = priorStatus; throw error }
            try outbox.remove(owner: account, host: host, id: message.id)
            MediaUploadService.shared.forgetPendingUpload(messageId: message.id, owner: account)
        } catch {
            guard isCurrent() else { return }
            OnlineMessagingService.shared.messagingError = "El mensaje del grupo sigue pendiente. " + error.localizedDescription
        }
    }

    public func retryPendingMessages(force: Bool = false) {
        guard let context = messageContext, OnlineMessagingService.shared.status == .online, !retryInProgress else { return }
        guard force || Date() >= nextRetryPass else { return }
        nextRetryPass = Date().addingTimeInterval(30)
        retryInProgress = true
        Task { @MainActor in
            defer { retryInProgress = false }
            let account = IdentityManager.shared.currentIdentity.myaowId
            let host = OnlineMessagingService.shared.relayHost
            let descriptor = FetchDescriptor<MessageModel>(predicate: #Predicate {
                $0.isOutgoing && $0.senderId == account && ($0.deliveryStatusRaw == "queued" || $0.deliveryStatusRaw == "sending")
            }, sortBy: [SortDescriptor(\.timestamp)])
            guard let messages = try? context.fetch(descriptor) else { return }
            for message in messages.prefix(50) {
                guard account == IdentityManager.shared.currentIdentity.myaowId, host == OnlineMessagingService.shared.relayHost else { break }
                let convId = message.conversationId
                guard let conversation = try? context.fetch(FetchDescriptor<ConversationModel>(predicate: #Predicate { $0.id == convId })).first,
                      conversation.isGroup || !conversation.recipientMyaowId.isEmpty else { continue }
                if conversation.isGroup {
                    await retryGroupMessage(message, conversation: conversation, context: context, account: account, host: host)
                    continue
                }
                if OnlineMessagingService.shared.hasQueuedPacket(messageId: message.id) { continue }
                var mediaUrl: String?
                if let media = message.mediaData {
                    guard let upload = await MediaUploadService.shared.uploadMedia(data: media, filename: "attachment.bin", contentType: "application/octet-stream", recipientMyaowId: conversation.recipientMyaowId, messageId: message.id) else { continue }
                    mediaUrl = upload.mediaUrl
                    guard account == IdentityManager.shared.currentIdentity.myaowId, host == OnlineMessagingService.shared.relayHost else { break }
                } else if ["image", "video", "voice", "rawFile"].contains(message.messageTypeRaw) { continue }
                // Hold the single-flight guard until the encrypted packet is durable.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    OnlineMessagingService.shared.sendOnlineMessage(messageId: message.id,
                        conversationId: conversation.id, recipientMyaowId: conversation.recipientMyaowId,
                        plaintext: message.text, messageType: message.messageTypeRaw, mediaUrl: mediaUrl, replyToId: message.replyToId, decorationJSON: message.decorationJSON) { _ in
                        if ![.sent, .delivered, .read].contains(message.deliveryStatus) { message.deliveryStatus = .queued }
                        try? context.save()
                        continuation.resume()
                    }
                }
            }
            OnlineMessagingService.shared.flushOutbox()
        }
    }

}

// MARK: - Hex String Extension
private extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        self = data
    }
}
