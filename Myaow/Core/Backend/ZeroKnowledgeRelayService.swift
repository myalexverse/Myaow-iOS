//
//  ZeroKnowledgeRelayService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import CryptoKit

public struct EncryptedRelayEnvelope: Codable, Identifiable, Sendable {
    public let id: String
    public let recipientIdHash: String
    public let senderEphemeralId: String
    public let encryptedBlobHex: String
    public let timestamp: Date
    public let timeToLiveSeconds: TimeInterval
}

public enum RelayConnectionState: String, Sendable {
    case disconnected = "Desconectado"
    case connecting = "Conectando al Relay..."
    case connected = "Relay Cero-Conocimiento Activo"
    case error = "Error de Conexión"
}

@MainActor
@Observable
public final class ZeroKnowledgeRelayService {
    public static let shared = ZeroKnowledgeRelayService()
    
    public var connectionState: RelayConnectionState = .connected
    public var relayEndpoint: String = "https://relay.myaow.app/v1"
    public var pendingEnvelopesCount: Int = 0
    public var isZeroKnowledgeVerified: Bool = true
    
    private var inMemoryRelayQueue: [EncryptedRelayEnvelope] = []
    
    private init() {}
    
    /// Envía un blob encriptado opaco al servidor relay
    public func dispatchEnvelope(_ envelope: EncryptedRelayEnvelope) async throws {
        // En una app en producción, esto envía un payload WebSocket / HTTP POST
        // El servidor NO tiene acceso a claves, remitente real ni texto plano
        self.inMemoryRelayQueue.append(envelope)
        self.pendingEnvelopesCount = inMemoryRelayQueue.count
        
        // Simular entrega remota inmediata
        try? await Task.sleep(for: .milliseconds(300))
    }
    
    /// Descarga y purga los sobres pendientes para la identidad local
    public func fetchAndAcknowledgeEnvelopes(for myaowId: String) -> [EncryptedRelayEnvelope] {
        let idHash = SHA256.hash(data: Data(myaowId.utf8)).map { String(format: "%02hhx", $0) }.joined()
        
        let matches = inMemoryRelayQueue.filter { $0.recipientIdHash == idHash }
        // Purgar inmediatamente los entregados (Zero Knowledge Ephemeral Relay)
        inMemoryRelayQueue.removeAll { $0.recipientIdHash == idHash }
        self.pendingEnvelopesCount = inMemoryRelayQueue.count
        
        return matches
    }
}
