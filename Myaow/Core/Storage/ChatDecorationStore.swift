import Foundation
import SwiftData

@MainActor enum ChatDecorationStore {
    static func enqueue(_ decoration: ChatDecoration, conversation: ConversationModel,
                        actor: String, name: String, context: ModelContext) throws {
        guard !actor.isEmpty, conversation.isGroup || (!conversation.recipientMyaowId.isEmpty && conversation.recipientMyaowId != actor) else { throw DecorationError.unavailable }
        let previous = ChatDecorationEvent.decode(conversation.sharedDecorationJSON)
        let event = ChatDecorationEvent(version: 1, id: UUID().uuidString,
            revision: (previous?.revision ?? 0) + 1, decoration: decoration, actor: actor,
            participants: conversation.isGroup ? nil : [actor, conversation.recipientMyaowId].sorted(),
            group: conversation.isGroup ? conversation.id.lowercased() : nil)
        // Group authorization is checked against the server before enqueue and again on delivery.
        guard event.revision < 1_000_000_000 else { throw DecorationError.invalid }
        let json = try event.json
        let message = MessageModel(conversationId: conversation.id, senderId: actor, senderName: name,
            isOutgoing: true, text: "Cambió la decoración a \(decoration.title).", deliveryStatusRaw: "queued", messageTypeRaw: "theme-v1")
        message.decorationJSON = json
        conversation.sharedDecorationJSON = json
        conversation.localDecorationRaw = nil
        conversation.messages.append(message)
        conversation.lastMessageSnippet = message.text
        conversation.lastMessageTimestamp = message.timestamp
        do { try context.save() } catch { context.rollback(); throw error }
    }

    /// Called after envelope authentication and scope/role validation, in the same transaction as the message.
    static func apply(_ event: ChatDecorationEvent, to conversation: ConversationModel) throws {
        if event.supersedes(ChatDecorationEvent.decode(conversation.sharedDecorationJSON)) {
            conversation.sharedDecorationJSON = try event.json
        }
    }
}
