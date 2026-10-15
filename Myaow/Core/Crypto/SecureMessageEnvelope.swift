import Foundation
import CryptoKit

enum SecureMessageError: Error { case invalidEnvelope, unsupportedVersion, identityChanged, keyUnavailable, insecureTransport }

struct SecureMessageContent: Codable, Equatable {
    let text: String
    let messageType: String
    var mediaBase64: String? = nil
    var mediaUrl: String? = nil
    var replyToId: String? = nil
    var groupId: String? = nil
    var groupMessageId: String? = nil
    var decorationJSON: String? = nil

    /// Public routing hint for APNs only; never carries message text or an arbitrary filename.
    var notificationSound: String? {
        guard messageType == "nudge" else { return nil }
        return Self.nudgeSoundIDs.first { text.hasPrefix("[NUDGE:\($0)]") }
    }
    static let nudgeSoundIDs = ["classic", "electric", "cosmic", "melodic", "claw", "lazy", "kiss", "giggle", "party", "question", "sleepy", "echo", "mentada", "admiration"]
}

/// RFC 9180 authenticated HPKE, implemented by CryptoKit. Each message has a fresh encapsulation.
/// This is not Signal's Double Ratchet and does not claim forward secrecy after recipient-key compromise.
struct SecureMessageEnvelope: Codable {
    let version: Int
    let messageId: String
    let senderId: String
    let recipientId: String
    let senderPublicKey: String
    let encapsulatedKey: Data
    let ciphertext: Data
    var groupId: String? = nil
    var notificationSound: String? = nil

    private static let suite = HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly

    static func seal(_ content: SecureMessageContent, messageId: String, senderId: String, recipientId: String,
                     senderPrivateKey: Data, recipientPublicKey: Data) throws -> Self {
        guard UUID(uuidString: messageId) != nil, senderId != recipientId,
              !senderId.isEmpty, !recipientId.isEmpty else { throw SecureMessageError.invalidEnvelope }
        let own = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: senderPrivateKey)
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKey)
        let context = try context(messageId: messageId, senderId: senderId, recipientId: recipientId, groupId: content.groupId)
        var sender = try HPKE.Sender(recipientKey: peer, ciphersuite: suite, info: context, authenticatedBy: own)
        let bytes = try JSONEncoder().encode(content)
        guard bytes.count <= 128 * 1024 else { throw SecureMessageError.invalidEnvelope }
        return Self(version: 2, messageId: messageId, senderId: senderId, recipientId: recipientId,
                    senderPublicKey: SecureHex.encode(own.publicKey.rawRepresentation), encapsulatedKey: sender.encapsulatedKey,
                    ciphertext: try sender.seal(bytes, authenticating: context), groupId: content.groupId,
                    notificationSound: content.notificationSound)
    }

    func open(messageId expectedId: String, senderId expectedSender: String, recipientId expectedRecipient: String,
              recipientPrivateKey: Data, trustedSenderPublicKey: Data) throws -> SecureMessageContent {
        guard version == 2 else { throw SecureMessageError.unsupportedVersion }
        guard messageId == expectedId, senderId == expectedSender, recipientId == expectedRecipient,
              UUID(uuidString: messageId) != nil, encapsulatedKey.count == 32,
              ciphertext.count >= 16, ciphertext.count <= 128 * 1024 + 16,
              try SecureHex.decode(senderPublicKey, bytes: 32) == trustedSenderPublicKey else { throw SecureMessageError.invalidEnvelope }
        let own = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: recipientPrivateKey)
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: trustedSenderPublicKey)
        let context = try Self.context(messageId: messageId, senderId: senderId, recipientId: recipientId, groupId: groupId)
        var recipient = try HPKE.Recipient(privateKey: own, ciphersuite: Self.suite, info: context,
                                            encapsulatedKey: encapsulatedKey, authenticatedBy: peer)
        let plaintext = try recipient.open(ciphertext, authenticating: context)
        let content = try JSONDecoder().decode(SecureMessageContent.self, from: plaintext)
        guard content.groupId == groupId else { throw SecureMessageError.invalidEnvelope }
        // Keep old envelopes without a hint readable; a supplied hint must match
        // the authenticated plaintext. V2 HPKE context stays compatible with old clients.
        if let notificationSound, notificationSound != content.notificationSound { throw SecureMessageError.invalidEnvelope }
        return content
    }

    private static func context(messageId: String, senderId: String, recipientId: String, groupId: String?) throws -> Data {
        // Length-delimited encoding; binds protocol, direction and message ID to the ciphertext.
        var fields = ["MYAOW-HPKE-AUTH-V2", messageId, senderId, recipientId]
        if let groupId { fields += ["group", groupId] }
        return try JSONEncoder().encode(fields)
    }
}
