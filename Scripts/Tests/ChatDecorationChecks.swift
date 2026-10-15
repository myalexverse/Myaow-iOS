import Foundation
import SwiftData
import CryptoKit

@main struct ChatDecorationChecks {
    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("myaow-decoration-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func container(_ name: String) throws -> ModelContainer {
            try ModelContainer(for: ConversationModel.self, MessageModel.self, configurations: ModelConfiguration(url: root.appendingPathComponent(name + ".store")))
        }
        let aStore = try container("alice"), bStore = try container("bob")
        let a = ModelContext(aStore), b = ModelContext(bStore)
        let alice = Curve25519.KeyAgreement.PrivateKey(), bob = Curve25519.KeyAgreement.PrivateKey()
        let chatA = ConversationModel(title: "Bob", recipientMyaowId: "bob")
        let chatB = ConversationModel(title: "Alice", recipientMyaowId: "alice")
        let unrelated = ConversationModel(title: "Other", recipientMyaowId: "other")
        a.insert(chatA); b.insert(chatB); b.insert(unrelated)
        try ChatDecorationStore.enqueue(.water, conversation: chatA, actor: "alice", name: "Alice", context: a)
        let queued = chatA.messages[0]
        precondition(queued.deliveryStatusRaw == "queued" && queued.decorationJSON != nil)
        let cipher = try SecureMessageEnvelope.seal(.init(text: queued.text, messageType: queued.messageTypeRaw, decorationJSON: queued.decorationJSON), messageId: queued.id, senderId: "alice", recipientId: "bob", senderPrivateKey: alice.rawRepresentation, recipientPublicKey: bob.publicKey.rawRepresentation)
        let packets = MessageOutbox(root: root.appendingPathComponent("outbox"))
        try packets.enqueue(String(decoding: JSONEncoder().encode(cipher), as: UTF8.self), account: "alice", id: queued.id)
        let afterRestart = try MessageOutbox(root: root.appendingPathComponent("outbox")).pending(account: "alice")
        precondition(afterRestart.count == 1)
        let restored = try JSONDecoder().decode(SecureMessageEnvelope.self, from: Data(afterRestart[0].packet.utf8))
        let clear = try restored.open(messageId: queued.id, senderId: "alice", recipientId: "bob", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation)
        let event = ChatDecorationEvent.decode(clear.decorationJSON)!
        try event.validate(sender: "alice", recipient: "bob", groupID: nil)
        try ChatDecorationStore.apply(event, to: chatB); try b.save()
        precondition(chatA.sharedDecorationJSON == chatB.sharedDecorationJSON && unrelated.sharedDecorationJSON == nil)
        try ChatDecorationStore.apply(event, to: chatB) // Duplicate does not change state.
        try packets.acknowledge(account: "alice", id: queued.id)
        let acknowledged = try packets.pending(account: "alice")
        precondition(acknowledged.isEmpty)
        print("PASS: encrypted delivery after durable outbox reopen; only intended conversation changes")

        // Two offline edits from the same revision converge regardless of delivery order.
        try ChatDecorationStore.enqueue(.lavaTeal, conversation: chatA, actor: "alice", name: "Alice", context: a)
        try ChatDecorationStore.enqueue(.waves, conversation: chatB, actor: "bob", name: "Bob", context: b)
        let aEdit = ChatDecorationEvent.decode(chatA.sharedDecorationJSON)!, bEdit = ChatDecorationEvent.decode(chatB.sharedDecorationJSON)!
        try aEdit.validate(sender: "alice", recipient: "bob", groupID: nil)
        try bEdit.validate(sender: "bob", recipient: "alice", groupID: nil)
        try ChatDecorationStore.apply(aEdit, to: chatB); try ChatDecorationStore.apply(bEdit, to: chatA)
        precondition(chatA.sharedDecorationJSON == chatB.sharedDecorationJSON)
        try ChatDecorationStore.apply(event, to: chatB)
        precondition(chatA.sharedDecorationJSON == chatB.sharedDecorationJSON)
        chatB.localDecorationRaw = ChatDecoration.classic.rawValue
        try ChatDecorationStore.enqueue(.silk, conversation: chatA, actor: "alice", name: "Alice", context: a)
        try ChatDecorationStore.apply(ChatDecorationEvent.decode(chatA.sharedDecorationJSON)!, to: chatB)
        precondition(chatB.localDecorationRaw == "classic")
        try b.save()
        let reopenedStore = try container("bob")
        let reopened = try ModelContext(reopenedStore).fetch(FetchDescriptor<ConversationModel>()).first { $0.recipientMyaowId == "alice" }!
        precondition(reopened.sharedDecorationJSON == chatA.sharedDecorationJSON && reopened.localDecorationRaw == "classic")
        print("PASS: concurrent changes converge, stale events ignored, local preference and shared state persist")

        func rejects(_ run: () throws -> Void) { do { try run(); fatalError("Invalid event accepted") } catch {} }
        rejects { try event.validate(sender: "mallory", recipient: "bob", groupID: nil) }
        rejects { try event.validate(sender: "alice", recipient: "other", groupID: nil) }
        rejects { try event.validate(sender: "alice", recipient: "bob", groupID: UUID().uuidString) }
        let group = UUID().uuidString.lowercased()
        let g = ChatDecorationEvent(version: 1, id: UUID().uuidString, revision: 1, decoration: .lava, actor: "alice", participants: nil, group: group)
        try g.validate(sender: "alice", recipient: "bob", groupID: group)
        rejects { try g.validate(sender: "alice", recipient: "bob", groupID: UUID().uuidString) }
        precondition(ChatDecorationEvent.canEditGroup(actor: "alice", recipient: "bob", roles: ["alice":"admin", "bob":"member"]))
        precondition(!ChatDecorationEvent.canEditGroup(actor: "alice", recipient: "bob", roles: ["alice":"member", "bob":"member"]))
        precondition(!ChatDecorationEvent.canEditGroup(actor: "alice", recipient: "bob", roles: ["alice":"admin"]))
        precondition(ChatDecorationEvent.decode(String(repeating: "a", count: 2049)) == nil)
        let unknown = try event.json.replacingOccurrences(of: "\"water\"", with: "\"../../private\"")
        precondition(ChatDecorationEvent.decode(unknown) == nil)
        let legacy = Data("{\"text\":\"Hola\",\"messageType\":\"text\"}".utf8)
        let legacyMessage = try JSONDecoder().decode(SecureMessageContent.self, from: legacy)
        precondition(legacyMessage.decorationJSON == nil)
        print("PASS: actor/chat/group isolation, group roles, payload bounds, unknown assets and old messages")
        // A real group envelope is separately encrypted to each current recipient.
        let groupA = ConversationModel(id: group.uppercased(), title: "Team", isGroup: true)
        let groupB = ConversationModel(id: group.uppercased(), title: "Team", isGroup: true)
        a.insert(groupA); b.insert(groupB)
        try ChatDecorationStore.enqueue(.waves, conversation: groupA, actor: "alice", name: "Alice", context: a)
        let groupMessage = groupA.messages[0]
        let groupEnvelope = try SecureMessageEnvelope.seal(.init(text: groupMessage.text, messageType: "theme-v1", groupId: group, decorationJSON: groupMessage.decorationJSON), messageId: groupMessage.id, senderId: "alice", recipientId: "bob", senderPrivateKey: alice.rawRepresentation, recipientPublicKey: bob.publicKey.rawRepresentation)
        let groupContent = try groupEnvelope.open(messageId: groupMessage.id, senderId: "alice", recipientId: "bob", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation)
        let groupEvent = ChatDecorationEvent.decode(groupContent.decorationJSON)!
        try groupEvent.validate(sender: "alice", recipient: "bob", groupID: groupContent.groupId)
        try ChatDecorationStore.apply(groupEvent, to: groupB); try b.save()
        precondition(groupA.sharedDecorationJSON == groupB.sharedDecorationJSON)
        precondition(chatB.sharedDecorationJSON != groupB.sharedDecorationJSON)
        // Deleting the visible notice does not erase the conversation decoration.
        a.delete(groupMessage); try a.save()
        precondition(ChatDecorationEvent.decode(groupA.sharedDecorationJSON)?.decoration == .waves)
        print("PASS: group encrypted round-trip, independent direct/group state, appearance survives notice deletion")
    }
}
