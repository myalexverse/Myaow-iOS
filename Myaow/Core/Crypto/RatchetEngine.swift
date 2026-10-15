//
//  RatchetEngine.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation
import CryptoKit

public struct RatchetMessageHeader: Codable, Sendable {
    public let ephemeralPublicKeyHex: String
    public let messageNumber: Int
    public let previousChainLength: Int
}

public struct RatchetEncryptedPayload: Codable, Sendable {
    public let header: RatchetMessageHeader
    public let ciphertextHex: String
    public let nonceHex: String
    public let tagHex: String
}

public enum RatchetError: Error {
    case invalidKey
    case derivationFailed
    case encryptionFailed
    case decryptionFailed
    case outOfOrderExceeded
}

/// Implementación del protocolo Double Ratchet (Signal Protocol / Curve25519 / ChaCha20-Poly1305) para Perfect Forward Secrecy
@available(*, unavailable, message: "Legacy experimental ratchet. Use SecureMessageEnvelope.")
public final class RatchetSession: @unchecked Sendable {
    public let peerId: String
    private var rootKey: SymmetricKey
    private var sendingChainKey: SymmetricKey?
    private var receivingChainKey: SymmetricKey?
    
    private var myDHKeyPair: Curve25519.KeyAgreement.PrivateKey
    private var peerDHPublicKey: Curve25519.KeyAgreement.PublicKey?
    
    private var sendSequenceNumber: Int = 0
    private var receiveSequenceNumber: Int = 0
    private var previousSendChainLength: Int = 0
    
    private let lock = NSLock()
    
    public init(
        peerId: String,
        sharedMasterSecret: SymmetricKey,
        initialMyDH: Curve25519.KeyAgreement.PrivateKey = Curve25519.KeyAgreement.PrivateKey(),
        initialPeerDHPublicKey: Curve25519.KeyAgreement.PublicKey? = nil
    ) {
        self.peerId = peerId
        self.rootKey = sharedMasterSecret
        self.myDHKeyPair = initialMyDH
        self.peerDHPublicKey = initialPeerDHPublicKey
        
        if let peerPubKey = initialPeerDHPublicKey {
            // Inicializar DH Ratchet de envío
            if let dhShared = try? initialMyDH.sharedSecretFromKeyAgreement(with: peerPubKey) {
                let (newRoot, sendChain) = Self.kdfRoot(rootKey: sharedMasterSecret, dhSecret: dhShared)
                self.rootKey = newRoot
                self.sendingChainKey = sendChain
            }
        }
    }
    
    // MARK: - Encryption with Forward Secrecy
    public func encrypt(plaintext: String) throws -> RatchetEncryptedPayload {
        lock.lock()
        defer { lock.unlock() }
        
        guard let data = plaintext.data(using: .utf8) else {
            throw RatchetError.encryptionFailed
        }
        
        if sendingChainKey == nil {
            // Generar nuevo par DH si no existe cadena de envío
            self.myDHKeyPair = Curve25519.KeyAgreement.PrivateKey()
            if let peerKey = peerDHPublicKey, let dhShared = try? myDHKeyPair.sharedSecretFromKeyAgreement(with: peerKey) {
                let (newRoot, sendChain) = Self.kdfRoot(rootKey: rootKey, dhSecret: dhShared)
                self.rootKey = newRoot
                self.sendingChainKey = sendChain
            }
        }
        
        guard let currentSendChain = sendingChainKey else {
            throw RatchetError.derivationFailed
        }
        
        // Ratchet simétrico: avanzar cadena de envío y obtener clave única de mensaje
        let (nextChain, messageKey) = Self.kdfChain(chainKey: currentSendChain)
        self.sendingChainKey = nextChain
        
        let header = RatchetMessageHeader(
            ephemeralPublicKeyHex: myDHKeyPair.publicKey.rawRepresentation.map { String(format: "%02hhx", $0) }.joined(),
            messageNumber: sendSequenceNumber,
            previousChainLength: previousSendChainLength
        )
        self.sendSequenceNumber += 1
        
        // Cifrado con ChaCha20-Poly1305
        let sealedBox = try ChaChaPoly.seal(data, using: messageKey)
        
        return RatchetEncryptedPayload(
            header: header,
            ciphertextHex: sealedBox.ciphertext.map { String(format: "%02hhx", $0) }.joined(),
            nonceHex: sealedBox.nonce.withUnsafeBytes { Data($0).map { String(format: "%02hhx", $0) }.joined() },
            tagHex: sealedBox.tag.map { String(format: "%02hhx", $0) }.joined()
        )
    }
    
    // MARK: - Decryption with Ratchet Advancement
    public func decrypt(payload: RatchetEncryptedPayload) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        
        // Verificar si el remitente avanzó su clave DH efímera
        if let peerKeyData = Data(hexString: payload.header.ephemeralPublicKeyHex),
           let incomingPeerDH = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerKeyData) {
            
            let isNewDH = peerDHPublicKey?.rawRepresentation != incomingPeerDH.rawRepresentation
            if isNewDH {
                // Completar el paso DH previo
                self.previousSendChainLength = sendSequenceNumber
                self.sendSequenceNumber = 0
                self.receiveSequenceNumber = 0
                self.peerDHPublicKey = incomingPeerDH
                
                // Ratchet de recepción
                if let dhReceive = try? myDHKeyPair.sharedSecretFromKeyAgreement(with: incomingPeerDH) {
                    let (newRoot, recvChain) = Self.kdfRoot(rootKey: rootKey, dhSecret: dhReceive)
                    self.rootKey = newRoot
                    self.receivingChainKey = recvChain
                }
                
                // Generar nuevo par propio para futuros envíos
                self.myDHKeyPair = Curve25519.KeyAgreement.PrivateKey()
                if let dhSend = try? myDHKeyPair.sharedSecretFromKeyAgreement(with: incomingPeerDH) {
                    let (newRoot, sendChain) = Self.kdfRoot(rootKey: rootKey, dhSecret: dhSend)
                    self.rootKey = newRoot
                    self.sendingChainKey = sendChain
                }
            }
        }
        
        guard let currentRecvChain = receivingChainKey else {
            throw RatchetError.derivationFailed
        }
        
        // Ratchet simétrico de recepción
        let (nextRecvChain, messageKey) = Self.kdfChain(chainKey: currentRecvChain)
        self.receivingChainKey = nextRecvChain
        self.receiveSequenceNumber += 1
        
        guard let ciphertextData = Data(hexString: payload.ciphertextHex),
              let nonceData = Data(hexString: payload.nonceHex),
              let tagData = Data(hexString: payload.tagHex) else {
            throw RatchetError.decryptionFailed
        }
        
        let nonce = try ChaChaPoly.Nonce(data: nonceData)
        let sealedBox = try ChaChaPoly.SealedBox(nonce: nonce, ciphertext: ciphertextData, tag: tagData)
        let decryptedData = try ChaChaPoly.open(sealedBox, using: messageKey)
        
        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw RatchetError.decryptionFailed
        }
        
        return decryptedString
    }
    
    // MARK: - KDF Functions (Key Derivation Function chains)
    private static func kdfRoot(rootKey: SymmetricKey, dhSecret: SharedSecret) -> (SymmetricKey, SymmetricKey) {
        let derived = dhSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: rootKey.withUnsafeBytes { Data($0) },
            sharedInfo: Data("myaow-double-ratchet-kdf-v1".utf8),
            outputByteCount: 64
        )
        let derivedData = derived.withUnsafeBytes { Data($0) }
        let newRoot = SymmetricKey(data: derivedData.prefix(32))
        let newChain = SymmetricKey(data: derivedData.suffix(32))
        return (newRoot, newChain)
    }
    
    private static func kdfChain(chainKey: SymmetricKey) -> (SymmetricKey, SymmetricKey) {
        let nextChainData = HMAC<SHA256>.authenticationCode(for: Data([0x01]), using: chainKey)
        let messageKeyData = HMAC<SHA256>.authenticationCode(for: Data([0x02]), using: chainKey)
        let nextKey = SymmetricKey(data: nextChainData)
        let msgKey = SymmetricKey(data: messageKeyData)
        return (nextKey, msgKey)
    }
    
    /// Borrado seguro de memoria RAM (Memory Zeroization) para mitigar volcados de memoria
    public static func secureZeroize(_ buffer: inout Data) {
        buffer.resetBytes(in: 0..<buffer.count)
    }
    
    // MARK: - Estado Serializable para Persistencia Segura (Keychain)
    public func exportSnapshot() -> RatchetSessionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        
        return RatchetSessionSnapshot(
            peerId: peerId,
            rootKeyHex: rootKey.withUnsafeBytes { Data($0).map { String(format: "%02hhx", $0) }.joined() },
            sendingChainKeyHex: sendingChainKey?.withUnsafeBytes { Data($0).map { String(format: "%02hhx", $0) }.joined() },
            receivingChainKeyHex: receivingChainKey?.withUnsafeBytes { Data($0).map { String(format: "%02hhx", $0) }.joined() },
            myDHPrivateKeyHex: myDHKeyPair.rawRepresentation.map { String(format: "%02hhx", $0) }.joined(),
            peerDHPublicKeyHex: peerDHPublicKey?.rawRepresentation.map { String(format: "%02hhx", $0) }.joined(),
            sendSequenceNumber: sendSequenceNumber,
            receiveSequenceNumber: receiveSequenceNumber,
            previousSendChainLength: previousSendChainLength
        )
    }
    
    public convenience init?(from snapshot: RatchetSessionSnapshot) {
        guard let rootData = Data(hexString: snapshot.rootKeyHex),
              let dhPrivData = Data(hexString: snapshot.myDHPrivateKeyHex),
              let dhPrivKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: dhPrivData) else {
            return nil
        }
        
        let peerPubKey = snapshot.peerDHPublicKeyHex.flatMap { Data(hexString: $0) }.flatMap { try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0) }
        
        self.init(
            peerId: snapshot.peerId,
            sharedMasterSecret: SymmetricKey(data: rootData),
            initialMyDH: dhPrivKey,
            initialPeerDHPublicKey: peerPubKey
        )
        
        if let sendHex = snapshot.sendingChainKeyHex, let sendData = Data(hexString: sendHex) {
            self.sendingChainKey = SymmetricKey(data: sendData)
        }
        if let recvHex = snapshot.receivingChainKeyHex, let recvData = Data(hexString: recvHex) {
            self.receivingChainKey = SymmetricKey(data: recvData)
        }
        self.sendSequenceNumber = snapshot.sendSequenceNumber
        self.receiveSequenceNumber = snapshot.receiveSequenceNumber
        self.previousSendChainLength = snapshot.previousSendChainLength
    }
}

public struct RatchetSessionSnapshot: Codable, Sendable {
    public let peerId: String
    public let rootKeyHex: String
    public let sendingChainKeyHex: String?
    public let receivingChainKeyHex: String?
    public let myDHPrivateKeyHex: String
    public let peerDHPublicKeyHex: String?
    public let sendSequenceNumber: Int
    public let receiveSequenceNumber: Int
    public let previousSendChainLength: Int
}

// MARK: - Hex String Extension
private extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var index = hexString.startIndex
        for _ in 0..<len {
            let nextIndex = hexString.index(index, offsetBy: 2)
            if let byte = UInt8(hexString[index..<nextIndex], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            index = nextIndex
        }
        self = data
    }
}
