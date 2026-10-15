import Foundation
import CryptoKit

private final class MemorySecrets: SecretStore {
    var values: [String: Data] = [:]
    var failRead = false
    var failWrite = false
    func read(key: String) throws -> Data? {
        if failRead { throw IdentityVaultError.verificationFailed }
        return values[key]
    }
    func write(key: String, data: Data) throws {
        if failWrite { throw IdentityVaultError.verificationFailed }
        values[key] = data
    }
}

@main
struct CriticalSecurityChecks {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), name); checks += 1
    }
    static func rejects(_ name: String, _ block: () throws -> Void) {
        do { try block(); fatalError("Accepted: \(name)") } catch { checks += 1 }
    }
    static func main() throws {
        let newIDs = (0..<10000).map { _ in UserIdentity.generateMyaowId() }
        check(Set(newIDs).count == newIDs.count, "Fresh account IDs do not collide in the test sample")
        check(newIDs.allSatisfy { $0.hasPrefix("MYAOW-") && $0.count == 38 }, "Fresh accounts use full UUID-sized identifiers")
        let alice = Curve25519.KeyAgreement.PrivateKey()
        let bob = Curve25519.KeyAgreement.PrivateKey()
        let mallory = Curve25519.KeyAgreement.PrivateKey()
        let content = SecureMessageContent(text: "Prueba privada: café 🐈", messageType: "text", replyToId: UUID().uuidString)
        var envelopes: [SecureMessageEnvelope] = []
        for _ in 0..<12 {
            let id = UUID().uuidString
            envelopes.append(try .seal(content, messageId: id, senderId: "ALICE", recipientId: "BOB",
                senderPrivateKey: alice.rawRepresentation, recipientPublicKey: bob.publicKey.rawRepresentation))
        }
        // Fresh recipient contexts: simultaneous starts, out-of-order delivery and process restart do not share ratchet state.
        for envelope in envelopes.reversed() {
            let recovered = try JSONDecoder().decode(SecureMessageEnvelope.self, from: JSONEncoder().encode(envelope))
            let plaintext = try recovered.open(messageId: recovered.messageId, senderId: "ALICE", recipientId: "BOB",
                recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation)
            check(plaintext == content, "Round trip and metadata")
        }
        check(Set(envelopes.map(\.encapsulatedKey)).count == 12, "Fresh ephemeral encapsulations")
        let envelope = envelopes[0]
        check(envelope.notificationSound == nil, "Ordinary messages reveal no sound type")
        for sound in SecureMessageContent.nudgeSoundIDs {
            let nudge = SecureMessageContent(text: "[NUDGE:\(sound)] private label", messageType: "nudge")
            var sealed = try SecureMessageEnvelope.seal(nudge, messageId: UUID().uuidString, senderId: "ALICE", recipientId: "BOB", senderPrivateKey: alice.rawRepresentation, recipientPublicKey: bob.publicKey.rawRepresentation)
            check(sealed.notificationSound == sound, "Nudge sound routing")
            let opened = try sealed.open(messageId: sealed.messageId, senderId: "ALICE", recipientId: "BOB", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation)
            check(opened == nudge, "Sound hint preserves encrypted content")
            sealed.notificationSound = "invalid"
            rejects("mismatched sound hint") { _ = try sealed.open(messageId: sealed.messageId, senderId: "ALICE", recipientId: "BOB", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation) }
            sealed.notificationSound = nil
            _ = try sealed.open(messageId: sealed.messageId, senderId: "ALICE", recipientId: "BOB", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation)
        }
        check(SecureMessageContent(text: "[NUDGE:mentada] copied text", messageType: "text").notificationSound == nil, "Text cannot masquerade as nudge")
        check(SecureMessageContent(text: "[NUDGE:../../private]", messageType: "nudge").notificationSound == nil, "No arbitrary sound path")
        rejects("wrong recipient key") { _ = try envelope.open(messageId: envelope.messageId, senderId: "ALICE", recipientId: "BOB", recipientPrivateKey: mallory.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation) }
        rejects("sender impersonation") { _ = try envelope.open(messageId: envelope.messageId, senderId: "ALICE", recipientId: "BOB", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: mallory.publicKey.rawRepresentation) }
        rejects("message ID substitution") { _ = try envelope.open(messageId: UUID().uuidString, senderId: "ALICE", recipientId: "BOB", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation) }
        rejects("routing substitution") { _ = try envelope.open(messageId: envelope.messageId, senderId: "MALLORY", recipientId: "BOB", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation) }
        var corrupt = envelope.ciphertext; corrupt[corrupt.startIndex] ^= 1
        let tampered = SecureMessageEnvelope(version: 2, messageId: envelope.messageId, senderId: "ALICE", recipientId: "BOB", senderPublicKey: envelope.senderPublicKey, encapsulatedKey: envelope.encapsulatedKey, ciphertext: corrupt)
        rejects("tampered ciphertext") { _ = try tampered.open(messageId: envelope.messageId, senderId: "ALICE", recipientId: "BOB", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation) }
        let reply = try SecureMessageEnvelope.seal(content, messageId: UUID().uuidString, senderId: "BOB", recipientId: "ALICE", senderPrivateKey: bob.rawRepresentation, recipientPublicKey: alice.publicKey.rawRepresentation)
        let decodedReply = try reply.open(messageId: reply.messageId, senderId: "BOB", recipientId: "ALICE", recipientPrivateKey: alice.rawRepresentation, trustedSenderPublicKey: bob.publicKey.rawRepresentation)
        check(decodedReply == content, "Reverse direction")
        let encoded = String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
        check(!encoded.contains(content.text), "No plaintext in wire envelope")
        let groupContent = SecureMessageContent(text: "Grupo privado", messageType: "text", groupId: UUID().uuidString)
        var groupEnvelope = try SecureMessageEnvelope.seal(groupContent, messageId: UUID().uuidString, senderId: "ALICE", recipientId: "BOB", senderPrivateKey: alice.rawRepresentation, recipientPublicKey: bob.publicKey.rawRepresentation)
        let groupRoundTrip = try groupEnvelope.open(messageId: groupEnvelope.messageId, senderId: "ALICE", recipientId: "BOB", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation)
        check(groupRoundTrip == groupContent, "Group identity authenticated with ciphertext")
        groupEnvelope.groupId = UUID().uuidString
        rejects("group routing substitution") { _ = try groupEnvelope.open(messageId: groupEnvelope.messageId, senderId: "ALICE", recipientId: "BOB", recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation) }
        let bytes = Data(repeating: 0xAB, count: 4096)
        let attachment = try EncryptedAttachment.seal(bytes)
        let decodedAttachment = try EncryptedAttachment.open(attachment.ciphertext, keyFragment: attachment.keyFragment)
        check(decodedAttachment == bytes && attachment.ciphertext != bytes, "Encrypted attachment round trip")
        rejects("wrong attachment key") { _ = try EncryptedAttachment.open(attachment.ciphertext, keyFragment: EncryptedAttachment.fragmentPrefix + String(repeating: "00", count: 32)) }
        rejects("odd-length key") { _ = try SecureHex.decode("abc", bytes: 2) }

        let suiteName = "Myaow.CriticalChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MemorySecrets()
        let vault = IdentityVault(defaults: defaults, secrets: store)
        let original = UserIdentity(myaowId: "MYAOW-TEST", displayName: "Persona de prueba", publicKeyHex: SecureHex.encode(alice.publicKey.rawRepresentation))
        defaults.set(try JSONEncoder().encode(original), forKey: "myaow_local_identity")
        defaults.set(SecureHex.encode(alice.rawRepresentation), forKey: "myaow_private_key")
        store.failWrite = true
        rejects("migration write failure") { _ = try vault.loadOrCreate() }
        check(defaults.string(forKey: "myaow_private_key") != nil, "Legacy secret retained until safe commit")
        store.failWrite = false
        let migrated = try vault.loadOrCreate()
        check(migrated.identity == original && migrated.privateKey == alice.rawRepresentation, "Identity and key preserved")
        check(defaults.object(forKey: "myaow_private_key") == nil, "Legacy secret removed after verification")
        let reopened = try vault.loadOrCreate()
        check(reopened == migrated, "Restart preserves identity")
        store.failRead = true
        rejects("locked keychain") { _ = try vault.loadOrCreate() }
        store.failRead = false
        store.values[vault.key] = Data("invalid".utf8)
        rejects("corrupt secure record") { _ = try vault.loadOrCreate() }
        store.values.removeAll()
        rejects("existing identity without key") { _ = try vault.loadOrCreate() }
        let retainedIdentity = try JSONDecoder().decode(UserIdentity.self, from: defaults.data(forKey: "myaow_local_identity")!)
        check(retainedIdentity == original, "Failed recovery does not replace identity")
        print("PASS: \(checks) checks — authenticated encryption, wrong keys, tampering, out-of-order delivery, attachments and non-destructive identity migration.")
    }
}
