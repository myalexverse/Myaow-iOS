import Foundation
import SwiftData

@MainActor
enum MessageReactionStore {
    static func enqueue(message: MessageModel, emoji: String, conversation: ConversationModel,
                        actor: String, name: String, context: ModelContext) throws {
        guard message.messageTypeRaw != "deleted", message.messageTypeRaw != "control-v2" else { throw SecureMessageError.invalidEnvelope }
        let reference = conversation.isGroup ? message.groupMessageId : message.id
        guard let reference else { throw ReactionError.previousGroupMessage }
        let selected = message.parsedReactions?[emoji]?.contains(actor) == true ? "" : emoji
        let change = SecureMessageMutation(action: .react, targetId: reference, text: selected, date: Date())
        try change.validate()
        let control = MessageModel(conversationId: conversation.id, senderId: actor, senderName: name,
            isOutgoing: true, text: String(decoding: try JSONEncoder().encode(change), as: UTF8.self),
            timestamp: change.date, deliveryStatusRaw: "queued", messageTypeRaw: "control-v2", replyToId: reference)
        let prior = message.reactionsJSON
        message.reactionsJSON = try SecureMutationStore.reactionJSON(prior, actor: actor, emoji: selected)
        context.insert(control)
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
    enum ReactionError: LocalizedError {
        case previousGroupMessage
        var errorDescription: String? { "Las reacciones de grupo están disponibles en mensajes enviados con la nueva versión de Myaow." }
    }
}
