import Foundation
import SwiftData

@MainActor
enum SecureMutationStore {
    /// Caller has authenticated/decrypted the control envelope. Effect and replay receipt commit together.
    static func apply(_ change: SecureMessageMutation, controlId: String, senderId: String, context: ModelContext, groupId: String? = nil, groupMembers: Set<String>? = nil) throws -> Bool {
        try change.validate()
        guard UUID(uuidString: controlId) != nil else { return false }
        if let receipt = try context.fetch(FetchDescriptor<MessageModel>(predicate: #Predicate { $0.id == controlId })).first {
            return receipt.messageTypeRaw == "control-v2" && !receipt.isOutgoing && receipt.senderId == senderId
        }
        let targetId = change.targetId
        let target: MessageModel
        if let groupId {
            guard change.action == .react, groupMembers?.contains(senderId) == true else { return false }
            let matches = try context.fetch(FetchDescriptor<MessageModel>(predicate: #Predicate { $0.groupMessageId == targetId }))
                .filter { $0.conversationId.lowercased() == groupId.lowercased() && $0.messageTypeRaw != "control-v2" }
            guard matches.count == 1, let match = matches.first else { return false }
            target = match
        } else {
            guard let match = try context.fetch(FetchDescriptor<MessageModel>(predicate: #Predicate { $0.id == targetId })).first,
                  match.messageTypeRaw != "control-v2" else { return false }
            target = match
        }
        let conversationId = target.conversationId
        guard let conversation = try context.fetch(FetchDescriptor<ConversationModel>(predicate: #Predicate { $0.id == conversationId })).first else { return false }
        guard groupId != nil ? conversation.isGroup : (!conversation.isGroup && conversation.recipientMyaowId == senderId) else { return false }
        switch change.action {
        case .edit, .delete:
            guard !target.isOutgoing, target.senderId == senderId else { return false }
            let previous = try context.fetch(FetchDescriptor<MessageModel>(predicate: #Predicate {
                $0.messageTypeRaw == "control-v2" && $0.replyToId == targetId && $0.text == "edit"
            }))
            let newest = !previous.contains { $0.timestamp > change.date || ($0.timestamp == change.date && $0.id > controlId) }
            if target.messageTypeRaw != "deleted" && (change.action == .delete || newest) {
                if change.action == .delete {
                    target.text = "🚫 Este mensaje fue eliminado"
                    target.messageTypeRaw = "deleted"
                    target.mediaData = nil
                } else {
                    target.text = change.text
                    target.isEdited = true
                }
                if conversation.messages.max(by: { $0.timestamp < $1.timestamp })?.id == targetId {
                    conversation.lastMessageSnippet = target.text
                }
            }
        case .react:
            if target.messageTypeRaw == "deleted" { break }
            let previous = try context.fetch(FetchDescriptor<MessageModel>(predicate: #Predicate {
                $0.messageTypeRaw == "control-v2" && $0.replyToId == targetId && $0.text == "react" && $0.senderId == senderId
            }))
            if !previous.contains(where: { $0.timestamp > change.date || ($0.timestamp == change.date && $0.id > controlId) }) {
                target.reactionsJSON = try reactionJSON(target.reactionsJSON, actor: senderId, emoji: change.text)
            }
        case .read:
            guard target.isOutgoing else { return false }
            target.deliveryStatus = .read
        }
        context.insert(MessageModel(id: controlId, conversationId: conversationId, senderId: senderId,
            senderName: "", isOutgoing: false, text: change.action.rawValue, timestamp: change.date,
            messageTypeRaw: "control-v2", replyToId: targetId))
        try context.save()
        return true
    }
    /// One current reaction per person. Empty emoji explicitly removes it.
    static func reactionJSON(_ json: String?, actor: String, emoji: String) throws -> String {
        var reactions = json.flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        for key in Array(reactions.keys) {
            reactions[key]?.removeAll { $0 == actor }
            if reactions[key]?.isEmpty == true { reactions.removeValue(forKey: key) }
        }
        if !emoji.isEmpty { reactions[emoji, default: []].append(actor) }
        return String(decoding: try JSONEncoder().encode(reactions), as: UTF8.self)
    }

}
