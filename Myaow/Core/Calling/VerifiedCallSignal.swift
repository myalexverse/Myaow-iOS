import Foundation

struct VerifiedCallSignal {
    let sender: String
    let callID: UUID
    let type: String
    let data: [String: Any]
    static func open(_ packet: [AnyHashable: Any], owner: String, privateKey: Data, peerKey: Data, now: Date = Date(), requiresOffer: Bool = false) throws -> Self {
        guard let sender = packet["senderMyaowId"] as? String,
              let messageID = packet["id"] as? String, let json = packet["encryptedPayload"] as? String,
              json.utf8.count <= 60000 else { throw SecureMessageError.invalidEnvelope }
        let envelope = try JSONDecoder().decode(SecureMessageEnvelope.self, from: Data(json.utf8))
        guard envelope.groupId == nil else { throw SecureMessageError.invalidEnvelope }
        let content = try envelope.open(messageId: messageID, senderId: sender, recipientId: owner,
            recipientPrivateKey: privateKey, trustedSenderPublicKey: peerKey)
        guard content.messageType == "call-signal-v2",
              let signal = try JSONSerialization.jsonObject(with: Data(content.text.utf8)) as? [String: Any],
              let type = signal["type"] as? String, type == packet["signalType"] as? String,
              ["call_offer","call_answer","call_hangup","webrtc_offer","webrtc_answer","webrtc_ice_candidate"].contains(type),
              signal["id"] as? String == messageID,
              let callID = signal["callId"] as? String, callID == packet["callId"] as? String,
              let uuid = UUID(uuidString: callID), let expiry = signal["expiresAt"] as? Double,
              expiry == packet["expiresAt"] as? Double,
              expiry > now.timeIntervalSince1970, expiry <= now.timeIntervalSince1970 + 95,
              !requiresOffer || type == "call_offer" else { throw SecureMessageError.invalidEnvelope }
        return Self(sender:sender,callID:uuid,type:type,data:signal)
    }
}
