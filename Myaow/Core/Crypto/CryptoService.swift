//
//  CryptoService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation
import CryptoKit

public enum CryptoError: Error {
    case keyGenerationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidKeyData
}

/// Servicio criptográfico para End-to-End Encryption (E2EE) y gestión de claves P256 / ChaChaPoly
public final class CryptoService: Sendable {
    public static let shared = CryptoService()
    
    private init() {}
    
    /// Genera un par de claves privadas/públicas Curve25519 para intercambio de claves y cifrado
    public func generateKeyPair() -> (privateKeyHex: String, publicKeyHex: String) {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey
        
        let privHex = privateKey.rawRepresentation.map { String(format: "%02hhx", $0) }.joined()
        let pubHex = publicKey.rawRepresentation.map { String(format: "%02hhx", $0) }.joined()
        
        return (privHex, pubHex)
    }
    
    /// Cifra un mensaje de texto con ChaChaPoly usando una clave simétrica compartida
    public func encrypt(text: String, symmetricKey: SymmetricKey) throws -> (ciphertext: Data, nonce: Data) {
        guard let data = text.data(using: .utf8) else {
            throw CryptoError.encryptionFailed
        }
        
        let sealedBox = try ChaChaPoly.seal(data, using: symmetricKey)
        return (sealedBox.ciphertext + sealedBox.tag, sealedBox.nonce.withUnsafeBytes { Data($0) })
    }
    
    /// Descifra un payload con ChaChaPoly
    public func decrypt(ciphertextWithTag: Data, nonceData: Data, symmetricKey: SymmetricKey) throws -> String {
        guard let nonce = try? ChaChaPoly.Nonce(data: nonceData) else {
            throw CryptoError.decryptionFailed
        }
        
        guard ciphertextWithTag.count >= 16 else {
            throw CryptoError.decryptionFailed
        }
        
        let tag = ciphertextWithTag.suffix(16)
        let ciphertext = ciphertextWithTag.prefix(ciphertextWithTag.count - 16)
        
        let sealedBox = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try ChaChaPoly.open(sealedBox, using: symmetricKey)
        
        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.decryptionFailed
        }
        
        return decryptedString
    }
    
}
