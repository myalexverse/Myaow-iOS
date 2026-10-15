//
//  MyaowCoreTests.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation
import CryptoKit

public struct MyaowCoreTests {
    @MainActor
    public static func runSelfChecks() -> [String: Bool] {
        var results: [String: Bool] = [:]
        
        // 1. Test User Identity & QR Serialization
        let keys = CryptoService.shared.generateKeyPair()
        let identity = UserIdentity(
            myaowId: "MYAOW-7K2K",
            displayName: "Ana Serrano",
            publicKeyHex: keys.publicKeyHex,
            avatarStateName: "Amigable"
        )
        
        if let qr = identity.toQRPayload(),
           let decoded = UserIdentity.fromQRPayload(qr),
           decoded.myaowId == identity.myaowId && decoded.displayName == identity.displayName {
            results["UserIdentity_QR_Serialization"] = true
        } else {
            results["UserIdentity_QR_Serialization"] = false
        }
        
        // 2. Test End-to-End ChaChaPoly Encryption & Decryption
        do {
            let sessionKey = SymmetricKey(size: .bits256)
            let originalText = "Hola desde Myaow! Mensajería privada y local."
            let encrypted = try CryptoService.shared.encrypt(text: originalText, symmetricKey: sessionKey)
            let decrypted = try CryptoService.shared.decrypt(
                ciphertextWithTag: encrypted.ciphertext,
                nonceData: encrypted.nonce,
                symmetricKey: sessionKey
            )
            results["Crypto_ChaChaPoly_E2EE"] = (decrypted == originalText)
        } catch {
            results["Crypto_ChaChaPoly_E2EE"] = false
        }
        
        // 3. Test Local AI Moderation Engine
        let safeResult = LocalAIModerationService.shared.analyzeText("Hola, ¿cómo estás hoy?")
        let violenceResult = LocalAIModerationService.shared.analyzeText("Alerta de violencia extrema")
        results["LocalAI_SafeText_Approved"] = (safeResult.status == .approved)
        results["LocalAI_SensitiveText_Blurred"] = (violenceResult.status == .blurred && violenceResult.triggeredCategory == .violence)
        
        // 4. Test Walkie-Talkie Bilateral Security Guard
        let wtService = WalkieTalkieService.shared
        wtService.startTransmitting(targetContactId: "unverified_node", isTargetVerified: false)
        if case .unverifiedBlocked = wtService.state {
            results["WalkieTalkie_UnverifiedBlocked_Guard"] = true
        } else {
            results["WalkieTalkie_UnverifiedBlocked_Guard"] = false
        }
        wtService.stopTransmitting()
        
        // 5. Test Chat Wallpaper Manager
        ChatWallpaperManager.shared.currentWallpaper = .meshGrid
        results["ChatWallpaper_Manager_Switch"] = (ChatWallpaperManager.shared.currentWallpaper == .meshGrid)
        ChatWallpaperManager.shared.currentWallpaper = .myaowDoodles
        
        // 6. Authenticated HPKE uses the same envelope as production messaging.
        do {
            let alice = Curve25519.KeyAgreement.PrivateKey()
            let bob = Curve25519.KeyAgreement.PrivateKey()
            let id = UUID().uuidString
            let content = SecureMessageContent(text: "Mensaje de prueba", messageType: "text")
            let envelope = try SecureMessageEnvelope.seal(content, messageId: id, senderId: "alice", recipientId: "bob",
                senderPrivateKey: alice.rawRepresentation, recipientPublicKey: bob.publicKey.rawRepresentation)
            let result = try envelope.open(messageId: id, senderId: "alice", recipientId: "bob",
                recipientPrivateKey: bob.rawRepresentation, trustedSenderPublicKey: alice.publicKey.rawRepresentation)
            results["Authenticated_HPKE_RoundTrip"] = result == content
        } catch { results["Authenticated_HPKE_RoundTrip"] = false }

        // 7. Test Safety Numbers (60 Digits Fingerprint)
        let snAlice = SafetyNumberService.shared.generateSafetyNumber(
            myIdentity: identity,
            peerPublicKeyHex: keys.publicKeyHex,
            peerMyaowId: "MYAOW-BOB1"
        )
        results["Safety_Number_60Digits_Valid"] = (snAlice.fullString.count == 60 && snAlice.formattedBlocks.count == 12)
        
        // 8. Test Keychain storage
        let testSecret = Data("myaow-keychain-test".utf8)
        let savedKey = KeychainSecurityService.shared.saveSecret(key: "test_enclave_key", data: testSecret)
        let loadedSecret = KeychainSecurityService.shared.loadSecret(key: "test_enclave_key")
        KeychainSecurityService.shared.deleteSecret(key: "test_enclave_key")
        results["Keychain_Storage"] = (savedKey && loadedSecret == testSecret)
        
        // 9. Test Online Messaging Service Heartbeat
        let isOnlineActive = (OnlineMessagingService.shared.status == .online)
        results["Online_Messaging_Heartbeat_Active"] = isOnlineActive
        
        // 10. Test Pinned Messages
        let testConversation = ConversationModel(title: "Test Pin Conv")
        let pinMsg = MessageModel(conversationId: testConversation.id, senderId: "u1", senderName: "User", isOutgoing: false, text: "Pin 1", isPinned: true)
        testConversation.messages.append(pinMsg)
        results["Pinned_Messages_Retrieved_Correctly"] = (testConversation.pinnedMessages.count == 1 && testConversation.pinnedMessages.first?.text == "Pin 1")
        
        // 11. Test Delivery Status Labels & Mesh Relayed
        results["Delivery_Status_MeshRelayed_Valid"] = (MessageDeliveryStatus.meshRelayed.labelText == "Entregado vía Mesh Offline")
        
        return results
    }
}
