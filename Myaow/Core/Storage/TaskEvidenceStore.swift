import Foundation
import SwiftData

/// Evidence uses the group's existing encrypted, durable message delivery.
/// The task reference is inside the ciphertext; attachments retain group access rules.
@MainActor enum TaskEvidenceStore {
    struct Item {
        let text: String
        let type: String
        var data: Data? = nil
    }
    static func reference(_ task: UUID) -> String { "task:" + task.uuidString.lowercased() }
    static func enqueue(_ items: [Item], task: UUID, conversation: ConversationModel,
                        actor: String, name: String, context: ModelContext) throws {
        guard conversation.isGroup, !items.isEmpty, items.count <= 10,
              items.allSatisfy({ ["text", "image", "video", "rawFile"].contains($0.type)
                  && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.utf8.count <= 8000
                  && ($0.type == "text" ? $0.data == nil : ($0.data?.isEmpty == false && $0.data!.count <= 10 * 1024 * 1024)) }),
              items.reduce(0, { $0 + ($1.data?.count ?? 0) }) <= 50 * 1024 * 1024 else { throw SecureMessageError.invalidEnvelope }
        if conversation.modelContext == nil { context.insert(conversation) }
        let now = Date()
        for (index, item) in items.enumerated() {
            let message = MessageModel(conversationId: conversation.id, senderId: actor, senderName: name,
                isOutgoing: true, text: item.text, timestamp: now.addingTimeInterval(Double(index) / 1000),
                deliveryStatusRaw: "queued", messageTypeRaw: item.type, mediaData: item.data,
                replyToId: reference(task))
            conversation.messages.append(message)
        }
        conversation.lastMessageSnippet = "Avance de tarea · " + items.last!.text
        conversation.lastMessageTimestamp = now
        do { try context.save() }
        catch { context.rollback(); throw error }
    }
}
