import Foundation
import SwiftData

/// Read the persisted timeline directly. Control receipts are bookkeeping, never chat rows.
enum ChatHistoryQuery {
    static func descriptor(conversationID: String) -> FetchDescriptor<MessageModel> {
        let upper = UUID(uuidString: conversationID)?.uuidString ?? conversationID
        let lower = UUID(uuidString: conversationID)?.uuidString.lowercased() ?? conversationID
        return FetchDescriptor<MessageModel>(predicate: #Predicate {
            ($0.conversationId == conversationID || $0.conversationId == upper || $0.conversationId == lower)
                && $0.messageTypeRaw != "control-v2" && $0.messageTypeRaw != "call-signal-v2"
        }, sortBy: [SortDescriptor(\.timestamp), SortDescriptor(\.id)])
    }
}
