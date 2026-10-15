//
//  DataPreviewSample.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation
import SwiftData

@MainActor
public struct DataPreviewSample {
    
    /// Inicializa únicamente el mensaje de bienvenida oficial de Myaow Team en instalaciones limpias
    public static func ensureInitialState(context: ModelContext) {
        let descriptor = FetchDescriptor<ConversationModel>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        
        guard existingCount == 0 else { return }
        
        // Chat Oficial de Bienvenida de Myaow Team
        let teamChat = ConversationModel(
            title: "Myaow Team",
            isGroup: false,
            unreadCount: 0,
            lastMessageSnippet: "¡Bienvenido a Myaow!",
            lastMessageTimestamp: Date(),
            isMeshConnected: true,
            nodeCount: 1,
            participantNames: ["Myaow Team"]
        )
        
        let welcomeMsg = MessageModel(
            conversationId: teamChat.id,
            senderId: "myaow_official",
            senderName: "Myaow Team",
            isOutgoing: false,
            text: "¡Bienvenido a Myaow! Tu entorno de mensajería privada, local y descentralizada está listo. Conecta con tus contactos escaneando su código QR, acercando sus dispositivos cara a cara o por su Myaow ID.",
            timestamp: Date(),
            deliveryStatusRaw: "delivered"
        )
        
        teamChat.messages = [welcomeMsg]
        context.insert(teamChat)
        
        let officialContact = ContactModel(
            myaowId: "MYAOW-TEAM",
            did: "did:myaow:official-team",
            displayName: "Myaow Team",
            avatarCatState: "Amigable",
            isMeshNearby: true,
            isVerified: true
        )
        context.insert(officialContact)
        
        try? context.save()
    }
    
    /// Limpia todos los datos de prueba y deja la aplicación en estado de producción
    public static func purgeAllBetaData(context: ModelContext) {
        try? context.delete(model: MessageModel.self)
        try? context.delete(model: ConversationModel.self)
        try? context.delete(model: ContactModel.self)
        try? context.delete(model: MomentModel.self)
        try? context.save()
        
        ensureInitialState(context: context)
    }
}
