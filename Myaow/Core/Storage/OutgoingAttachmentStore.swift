import Foundation
import SwiftData

struct OutgoingAttachment: Sendable {
    let data: Data
    let isVideo: Bool
    let caption: String
}

/// Commit the whole selection before starting any upload; every item retains its own retry identity.
@MainActor enum OutgoingAttachmentStore {
    enum Failure: Error { case invalidBatch }
    static func enqueue(_ items: [OutgoingAttachment], conversation: ConversationModel,
                        senderID: String, senderName: String, context: ModelContext) throws {
        guard (1...10).contains(items.count), items.allSatisfy({
            !$0.data.isEmpty && $0.data.count <= 10 * 1024 * 1024 && $0.caption.utf8.count <= 64 * 1024
        }), items.reduce(0, { $0 + $1.data.count }) <= 50 * 1024 * 1024 else { throw Failure.invalidBatch }
        let now = Date()
        do {
            if conversation.modelContext == nil { context.insert(conversation) }
            for (index, item) in items.enumerated() {
                let caption = item.caption.trimmingCharacters(in: .whitespacesAndNewlines)
                let text = caption.isEmpty ? (item.isVideo ? "Video" : "Fotografía") : caption
                let timestamp = now.addingTimeInterval(Double(index) / 1000)
                conversation.messages.append(MessageModel(conversationId: conversation.id, senderId: senderID,
                    senderName: senderName, isOutgoing: true, text: text, timestamp: timestamp,
                    deliveryStatusRaw: "queued", messageTypeRaw: item.isVideo ? "video" : "image",
                    mediaData: item.data, moderationStatusRaw: "approved"))
                conversation.lastMessageSnippet = text
                conversation.lastMessageTimestamp = timestamp
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
