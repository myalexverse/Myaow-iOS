//
//  UserIdentity.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation

/// Representa la identidad descentralizada (Cero Números de Teléfono) de un usuario en la red Myaow
public struct UserIdentity: Codable, Equatable, Sendable {
    public var myaowId: String          // Ej: "MYAOW-7K2K"
    public var did: String              // Ej: "did:myaow:7k2k-98ab71c0"
    public var displayName: String      // Ej: "Alex Doven"
    public var customUsername: String?  // Ej: "alex"
    public var publicKeyHex: String     // Clave pública Curve25519 en hexadecimal
    public var createdAt: Date
    public var avatarStateName: String  // Nombre del estado de la mascota para el avatar
    public var avatarImageData: Data?   // Foto personalizada de la galería si la hay
    public var bioStatus: String?       // Estado público
    
    public init(
        myaowId: String = UserIdentity.generateMyaowId(),
        did: String? = nil,
        displayName: String = "Myaow User",
        customUsername: String? = nil,
        publicKeyHex: String,
        createdAt: Date = Date(),
        avatarStateName: String = "Neutro",
        avatarImageData: Data? = nil,
        bioStatus: String? = "Disponible en Myaow"
    ) {
        self.myaowId = myaowId
        self.did = did ?? "did:myaow:\(myaowId.lowercased().replacingOccurrences(of: "-", with: ""))-\(UUID().uuidString.prefix(8).lowercased())"
        self.displayName = displayName
        self.customUsername = customUsername
        self.publicKeyHex = publicKeyHex
        self.createdAt = createdAt
        self.avatarStateName = avatarStateName
        self.avatarImageData = avatarImageData
        self.bioStatus = bioStatus
    }
    
    /// Fresh accounts use UUID-sized identifiers; existing accounts keep their stored ID.
    /// Four base32 characters cannot safely identify a million accounts. Usernames remain the human-facing alias.
    public static func generateMyaowId() -> String {
        "MYAOW-" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }
    
    /// Serializa la identidad para ser compartida en código QR o Handshake
    public func toQRPayload() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    /// Reconstruye una identidad desde un payload QR
    public static func fromQRPayload(_ payload: String) -> UserIdentity? {
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(UserIdentity.self, from: data)
    }
}
