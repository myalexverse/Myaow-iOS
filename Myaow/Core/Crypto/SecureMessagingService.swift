import Foundation

@MainActor
final class SecureMessagingService {
    static let shared = SecureMessagingService()
    private let secrets = KeychainSecurityService.shared

    func cachedPeerKey(for id: String) throws -> Data? {
        let owner = IdentityManager.shared.currentIdentity.myaowId
        return try secrets.read(key: "peer_identity_v2_\(owner)_\(id)")
    }

    func peerKey(for id: String, suppliedKey: String? = nil) async throws -> Data {
        let owner = IdentityManager.shared.currentIdentity.myaowId
        let pinKey = "peer_identity_v2_\(owner)_\(id)"
        let pinned = try secrets.read(key: pinKey)
        if let suppliedKey, !suppliedKey.isEmpty {
            let candidate = try SecureHex.decode(suppliedKey, bytes: 32)
            if let pinned, pinned != candidate { throw SecureMessageError.identityChanged }
            if pinned == nil { try secrets.write(key: pinKey, data: candidate) }
            return candidate
        }
        if let pinned { return pinned }
        guard let endpoint = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.httpURL else { throw SecureMessageError.keyUnavailable }
        #if !DEBUG
        guard endpoint.scheme == "https" else { throw SecureMessageError.insecureTransport }
        #endif
        guard let record = await UserDirectoryService.shared.lookupUser(byUsername: id),
              record.myaowId == id, let publicHex = record.identityKeyHex else { throw SecureMessageError.keyUnavailable }
        let candidate = try SecureHex.decode(publicHex, bytes: 32)
        // Recheck after suspension so two concurrent first-contact requests cannot replace a pin.
        if let current = try secrets.read(key: pinKey), current != candidate { throw SecureMessageError.identityChanged }
        try secrets.write(key: pinKey, data: candidate)
        return candidate
    }

    func seal(_ content: SecureMessageContent, messageId: String, recipientId: String, suppliedKey: String? = nil) async throws -> String {
        let identity = IdentityManager.shared
        guard identity.isInitialized else { throw SecureMessageError.keyUnavailable }
        let ownId = identity.currentIdentity.myaowId
        let privateKey = try SecureHex.decode(identity.privateKeyHex, bytes: 32)
        let peer = try await peerKey(for: recipientId, suppliedKey: suppliedKey)
        guard identity.isInitialized, identity.currentIdentity.myaowId == ownId else { throw SecureMessageError.keyUnavailable }
        let envelope = try SecureMessageEnvelope.seal(content, messageId: messageId, senderId: ownId, recipientId: recipientId,
                                                      senderPrivateKey: privateKey, recipientPublicKey: peer)
        return String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)
    }

    func open(_ json: String, messageId: String, senderId: String) async throws -> SecureMessageContent {
        guard json.utf8.count <= 24 * 1024 * 1024, IdentityManager.shared.isInitialized else { throw SecureMessageError.invalidEnvelope }
        let envelope = try JSONDecoder().decode(SecureMessageEnvelope.self, from: Data(json.utf8))
        let peer = try await peerKey(for: senderId)
        let identity = IdentityManager.shared
        return try envelope.open(messageId: messageId, senderId: senderId, recipientId: identity.currentIdentity.myaowId,
                                 recipientPrivateKey: SecureHex.decode(identity.privateKeyHex, bytes: 32), trustedSenderPublicKey: peer)
    }
}
