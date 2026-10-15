import Foundation
import SwiftData

@main
struct PersistenceChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myaow-persistence-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outbox = MessageOutbox(root: root.appendingPathComponent("outbox"))
        let id = UUID().uuidString
        try outbox.enqueue("encrypted-packet", account: "alice", id: id)
        try outbox.enqueue("encrypted-packet", account: "alice", id: id)
        let reopened = MessageOutbox(root: root.appendingPathComponent("outbox"))
        let queued = try reopened.pending(account: "alice")
        precondition(queued.count == 1 && queued[0].packet == "encrypted-packet")
        let other = try reopened.pending(account: "bob")
        precondition(other.isEmpty)
        do { try outbox.enqueue("replacement", account: "alice", id: id); fatalError("Identifier overwritten") } catch {}
        do { try outbox.enqueue("bad", account: "alice", id: "../escape"); fatalError("Path escaped") } catch {}
        try outbox.acknowledge(account: "alice", id: id)
        try outbox.acknowledge(account: "alice", id: id)
        let empty = try reopened.pending(account: "alice")
        precondition(empty.isEmpty)

        let schema = Schema(versionedSchema: MyaowSchemaV1.self)
        let config = ModelConfiguration(schema: schema, url: root.appendingPathComponent("history.store"), cloudKitDatabase: .none)
        let conversationID = UUID().uuidString
        let messageID = UUID().uuidString
        func writeHistory() throws {
            let store = MyaowStorageController(configuration: config)
            guard let container = store.container else { fatalError("Cannot open test store") }
            let context = ModelContext(container)
            let conversation = ConversationModel(id: conversationID, title: "Prueba", recipientMyaowId: "bob")
            conversation.messages.append(MessageModel(id: messageID, conversationId: conversationID, senderId: "alice", senderName: "Alice",
                isOutgoing: true, text: "No perder", deliveryStatusRaw: "queued", mediaData: Data([1, 2, 3])))
            context.insert(conversation)
            let contact = ContactModel(myaowId: "bob", did: "did:bob", displayName: "Bob")
            precondition(!contact.allowsLocalRadio && contact.radioAuthorizationOwnerId.isEmpty, "Existing and new contacts default to no radio permission")
            contact.allowsLocalRadio = true; contact.radioAuthorizationOwnerId = "alice"
            context.insert(contact)
            try context.save()
        }
        try writeHistory()
        let reopenedStore = MyaowStorageController(configuration: config)
        let context = ModelContext(reopenedStore.container!)
        let radioContact = try context.fetch(FetchDescriptor<ContactModel>()).first!
        precondition(radioContact.allowsLocalRadio && radioContact.radioAuthorizationOwnerId == "alice", "Radio consent survives restart and retains its owner")
        precondition(radioContact.radioAuthorizationOwnerId != "mallory", "Different account cannot inherit consent")
        radioContact.allowsLocalRadio = false; radioContact.radioAuthorizationOwnerId = ""
        try context.save()
        let consentReopened = ModelContext(reopenedStore.container!)
        let revoked = try consentReopened.fetch(FetchDescriptor<ContactModel>()).first!
        precondition(!revoked.allowsLocalRadio, "Revocation persists")
        let messages = try context.fetch(FetchDescriptor<MessageModel>())
        precondition(messages.count == 1 && messages[0].id == messageID && messages[0].text == "No perder" && messages[0].mediaData == Data([1, 2, 3]))
        precondition(messages[0].deliveryStatus == .queued)

        let conversation = try context.fetch(FetchDescriptor<ConversationModel>()).first!
        let incomingID = UUID().uuidString
        let incoming = MessageModel(id: incomingID, conversationId: conversationID, senderId: "bob", senderName: "Bob",
            isOutgoing: false, text: "Original", mediaData: Data([9]))
        conversation.messages.append(incoming)
        try context.save()
        func change(_ action: SecureMessageMutation.Action, target: String = incomingID, text: String = "Cambio", date: Date = Date(), sender: String = "bob", control: String = UUID().uuidString) throws -> Bool {
            try SecureMutationStore.apply(.init(action: action, targetId: target, text: text, date: date),
                controlId: control, senderId: sender, context: context)
        }
        let unauthorized = try change(.edit, sender: "mallory")
        precondition(!unauthorized && incoming.text == "Original")
        let editOwnMessage = try change(.edit, target: messageID)
        precondition(!editOwnMessage && messages[0].text == "No perder")
        let latest = Date()
        let control = UUID().uuidString
        let edited = try change(.edit, text: "Última edición", date: latest, control: control)
        precondition(edited && incoming.text == "Última edición")
        let duplicateEdit = try change(.edit, text: "Última edición", date: latest, control: control)
        precondition(duplicateEdit && incoming.text == "Última edición")
        let stale = try change(.edit, text: "Edición antigua", date: latest.addingTimeInterval(-60))
        precondition(stale && incoming.text == "Última edición")
        let deleted = try change(.delete, text: "", date: latest.addingTimeInterval(-120))
        precondition(deleted && incoming.messageTypeRaw == "deleted" && incoming.mediaData == nil)
        _ = try change(.edit, text: "No resucitar", date: latest.addingTimeInterval(120))
        precondition(incoming.messageTypeRaw == "deleted")
        let reacted = try change(.react, target: messageID, text: "🐾")
        precondition(reacted && messages[0].reactionsJSON?.contains("bob") == true)
        let reactionTime = Date().addingTimeInterval(10)
        _ = try change(.react, target: messageID, text: "🔥", date: reactionTime)
        precondition(messages[0].parsedReactions?["🔥"] == ["bob"] && messages[0].parsedReactions?["🐾"] == nil)
        _ = try change(.react, target: messageID, text: "❤️", date: reactionTime.addingTimeInterval(-1))
        precondition(messages[0].parsedReactions?["🔥"] == ["bob"], "Late older reaction cannot replace current reaction")
        let removalID = UUID().uuidString
        _ = try change(.react, target: messageID, text: "", date: reactionTime.addingTimeInterval(1), control: removalID)
        _ = try change(.react, target: messageID, text: "", date: reactionTime.addingTimeInterval(1), control: removalID)
        precondition(messages[0].parsedReactions?.isEmpty == true, "Removal is idempotent")
        try MessageReactionStore.enqueue(message: messages[0], emoji: "😻", conversation: conversation, actor: "alice", name: "Alice", context: context)
        try MessageReactionStore.enqueue(message: messages[0], emoji: "😻", conversation: conversation, actor: "alice", name: "Alice", context: context)
        precondition(messages[0].parsedReactions?.isEmpty == true, "Selecting own reaction twice removes it durably")

        let group = ConversationModel(title: "Evidence", isGroup: true)
        let groupTarget = MessageModel(conversationId: group.id, senderId: "alice", senderName: "Alice", isOutgoing: true, text: "Group target")
        groupTarget.groupMessageId = UUID().uuidString
        group.messages.append(groupTarget); context.insert(group); try context.save()
        let groupChange = SecureMessageMutation(action: .react, targetId: groupTarget.groupMessageId!, text: "👏", date: Date())
        let rejected = try SecureMutationStore.apply(groupChange, controlId: UUID().uuidString, senderId: "mallory", context: context, groupId: group.id, groupMembers: ["alice", "bob"])
        precondition(!rejected && groupTarget.reactionsJSON == nil, "Nonmember cannot react")
        let wrongGroup = try SecureMutationStore.apply(groupChange, controlId: UUID().uuidString, senderId: "bob", context: context, groupId: UUID().uuidString, groupMembers: ["alice", "bob"])
        precondition(!wrongGroup, "A reaction cannot escape its authenticated group")
        let acceptedReaction = try SecureMutationStore.apply(groupChange, controlId: UUID().uuidString, senderId: "bob", context: context, groupId: group.id, groupMembers: ["alice", "bob"])
        precondition(acceptedReaction && groupTarget.parsedReactions?["👏"] == ["bob"])
        let taskID = UUID()
        try TaskEvidenceStore.enqueue([.init(text: "Entrega", type: "text"), .init(text: "evidencia.txt", type: "rawFile", data: Data([1,2,3]))], task: taskID, conversation: group, actor: "alice", name: "Alice", context: context)
        let evidenceContext = ModelContext(reopenedStore.container!)
        let savedEvidence = try evidenceContext.fetch(ChatHistoryQuery.descriptor(conversationID: group.id)).filter { $0.replyToId == TaskEvidenceStore.reference(taskID) }
        precondition(savedEvidence.count == 2 && savedEvidence.allSatisfy { $0.deliveryStatus == .queued }, "Evidence survives restart with pending delivery")
        precondition(savedEvidence.last?.mediaData == Data([1,2,3]))
        do {
            try TaskEvidenceStore.enqueue([.init(text: "valid", type: "text"), .init(text: "empty", type: "rawFile", data: Data())], task: taskID, conversation: group, actor: "alice", name: "Alice", context: context)
            fatalError("Invalid evidence accepted")
        } catch {}
        precondition(group.messages.count == 3, "Invalid batch must not partially save evidence")
        let read = try change(.read, target: messageID, text: "")
        precondition(read && messages[0].deliveryStatus == .read)
        precondition(conversation.messages.count == 2, "Control receipts leaked into visible history")

        // A whole photo selection is committed before any network request, for direct chats and groups.
        for group in [false, true] {
            let chat = ConversationModel(title: "Batch fixture", recipientMyaowId: "bob", isGroup: group)
            let items = [
                OutgoingAttachment(data: Data([1, 2]), isVideo: false, caption: "Primera"),
                OutgoingAttachment(data: Data([3, 4]), isVideo: true, caption: ""),
                OutgoingAttachment(data: Data([5, 6]), isVideo: false, caption: "")
            ]
            try OutgoingAttachmentStore.enqueue(items, conversation: chat, senderID: "alice", senderName: "Alice", context: context)
            let ordered = chat.messages.sorted { $0.timestamp < $1.timestamp }
            let ids = ordered.map(\.id)
            precondition(Set(ids).count == 3 && ordered.map(\.messageTypeRaw) == ["image", "video", "image"])
            precondition(ordered.allSatisfy { $0.deliveryStatus == .queued })
            precondition(ordered.map(\.text) == ["Primera", "Video", "Fotografía"])
            let reopenedContext = ModelContext(reopenedStore.container!)
            let chatID = chat.id
            let recovered = try reopenedContext.fetch(FetchDescriptor<ConversationModel>(predicate: #Predicate { $0.id == chatID })).first!
            let recoveredMessages = recovered.messages.sorted { $0.timestamp < $1.timestamp }
            precondition(recoveredMessages.map(\.id) == ids && recoveredMessages.map(\.mediaData) == items.map { Optional($0.data) }, "Restart must preserve every item and retry identifier")
            let invalid = [items[0], OutgoingAttachment(data: Data(), isVideo: false, caption: "invalid")]
            do { try OutgoingAttachmentStore.enqueue(invalid, conversation: chat, senderID: "alice", senderName: "Alice", context: context); fatalError("Partial batch accepted") } catch {}
            precondition(chat.messages.count == 3, "Rejecting one item must not enqueue the others")
            do { try OutgoingAttachmentStore.enqueue(Array(repeating: items[0], count: 11), conversation: chat, senderID: "alice", senderName: "Alice", context: context); fatalError("Unbounded batch accepted") } catch {}
            precondition(chat.messages.count == 3)
        }
        let sticker = MyaowSticker.all[0]
        let stickerMessage = MessageModel(conversationId: conversationID, senderId: "alice", senderName: "Alice",
            isOutgoing: true, text: sticker.wireText, deliveryStatusRaw: "queued", messageTypeRaw: "sticker")
        conversation.messages.append(stickerMessage)
        try context.save()
        let stickerID = stickerMessage.id
        let restoredSticker = try ModelContext(reopenedStore.container!).fetch(FetchDescriptor<MessageModel>(predicate: #Predicate { $0.id == stickerID })).first!
        precondition(restoredSticker.messageTypeRaw == "sticker" && MyaowSticker.match(restoredSticker.text)?.id == sticker.id)
        precondition(MyaowSticker.match("unrecognized future sticker") == nil, "Unknown stickers must fall back to ordinary text")

        // Reopening a chat must read its saved history with no network and no visible control rows.
        let historyID = UUID().uuidString
        let oldTime = Date(timeIntervalSince1970: 1_800_000_000)
        for index in (0..<120).reversed() {
            context.insert(MessageModel(conversationId: index % 2 == 0 ? historyID : historyID.lowercased(),
                senderId: "bob", senderName: "Bob", isOutgoing: false, text: "Saved \(index)",
                timestamp: oldTime.addingTimeInterval(Double(index)), messageTypeRaw: index == 50 ? "control-v2" : "text"))
        }
        try context.save()
        for _ in 0..<3 {
            let freshContext = ModelContext(reopenedStore.container!)
            let history = try freshContext.fetch(ChatHistoryQuery.descriptor(conversationID: historyID))
            precondition(history.count == 119 && history.first?.text == "Saved 0" && history.last?.text == "Saved 119", "All local history must be available immediately, ordered and isolated to the chat")
            precondition(!history.contains { $0.messageTypeRaw == "control-v2" })
        }

        // A file where a directory is needed deterministically makes the store inaccessible.
        let blocked = root.appendingPathComponent("blocked")
        try Data("preserve-existing-data".utf8).write(to: blocked)
        let invalid = ModelConfiguration(schema: schema, url: blocked.appendingPathComponent("history.store"), cloudKitDatabase: .none)
        let failed = MyaowStorageController(configuration: invalid)
        precondition(failed.container == nil && failed.errorMessage != nil)
        let retained = try Data(contentsOf: blocked)
        precondition(retained == Data("preserve-existing-data".utf8))
        print("PASS: atomic direct/group media batches, restart/retry identities, invalid batch rejection, compatible sticker persistence; durable outbox, restart, account isolation, identifier protection, SwiftData history/media recovery non-destructive store failure, mutation ownership/replay/order, deletion, reactions and read receipts.")
    }
}
