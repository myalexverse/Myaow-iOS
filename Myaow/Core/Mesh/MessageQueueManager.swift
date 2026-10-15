//
//  MessageQueueManager.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

@MainActor
@Observable
public final class MessageQueueManager {
    public static let shared = MessageQueueManager()
    
    public private(set) var queuedCount: Int = 0
    
    private init() {}
    
    /// Despacha un mensaje a través de la malla local o lo encola si no hay conectividad
    public func sendMessage(
        conversation: ConversationModel,
        text: String,
        context: ModelContext,
        mediaData: Data? = nil,
        messageType: String = "text"
    ) {
        guard mediaData == nil && messageType == "text" else {
            OnlineMessagingService.shared.messagingError = "Envía este archivo desde el botón de adjuntar del chat."
            return
        }
        MyaowBackendEngine.shared.dispatchSecureMessage(conversation: conversation, text: text,
            context: context, recipientMyaowId: conversation.recipientMyaowId)
    }
    
    /// Reintenta el envío de todos los mensajes en cola cuando la red vuelve a estar disponible
    public func flushQueuedMessages(context: ModelContext) {
        MyaowBackendEngine.shared.retryPendingMessages()
    }
}
