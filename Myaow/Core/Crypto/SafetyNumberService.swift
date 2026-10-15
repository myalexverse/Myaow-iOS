//
//  SafetyNumberService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation
import CryptoKit

public struct SafetyNumber: Sendable {
    public let fullString: String            // 60 dígitos continuos
    public let formattedBlocks: [String]      // 12 bloques de 5 dígitos
    public let qrPayload: String
    
    public init(fullString: String, formattedBlocks: [String], qrPayload: String) {
        self.fullString = fullString
        self.formattedBlocks = formattedBlocks
        self.qrPayload = qrPayload
    }
}

/// Generador de números de seguridad criptográficos (Safety Numbers) para verificación bilateral anti-MITM
public final class SafetyNumberService: Sendable {
    public static let shared = SafetyNumberService()
    
    private init() {}
    
    /// Genera la huella de 60 dígitos derivada de las claves públicas de ambos usuarios
    public func generateSafetyNumber(
        myIdentity: UserIdentity,
        peerPublicKeyHex: String,
        peerMyaowId: String
    ) -> SafetyNumber {
        // Ordenar lexicográficamente para asegurar que ambos dispositivos generen el mismo código
        let sortedIDs = [myIdentity.myaowId, peerMyaowId].sorted()
        let sortedKeys = [myIdentity.publicKeyHex, peerPublicKeyHex].sorted()
        
        let combinedString = "\(sortedIDs[0]):\(sortedKeys[0]):\(sortedIDs[1]):\(sortedKeys[1])"
        var hash = SHA512.hash(data: Data(combinedString.utf8))
        
        // Iteraciones KDF adicionales para robustez
        for _ in 0..<1000 {
            hash = SHA512.hash(data: Data(hash))
        }
        
        let hashBytes = Array(hash)
        var digits = ""
        
        // Extraer 60 dígitos
        for i in 0..<12 {
            let offset = i * 4
            let chunk = Array(hashBytes[offset..<offset+4])
            let num = chunk.reduce(0) { ($0 << 8) | UInt32($1) }
            let formattedChunk = String(format: "%05d", num % 100000)
            digits.append(formattedChunk)
        }
        
        // Dividir en 12 bloques de 5 dígitos
        var blocks: [String] = []
        for i in 0..<12 {
            let start = digits.index(digits.startIndex, offsetBy: i * 5)
            let end = digits.index(start, offsetBy: 5)
            blocks.append(String(digits[start..<end]))
        }
        
        let qrPayload = "myaow-sn:\(sortedIDs[0])-\(sortedIDs[1]):\(digits)"
        return SafetyNumber(fullString: digits, formattedBlocks: blocks, qrPayload: qrPayload)
    }
}
