import Foundation
import CryptoKit

struct RadioContactCredential: Equatable, Sendable {
    let id: String
    let name: String
    let publicKey: Data
    var fingerprint: String { RadioContactSecurity.fingerprint(publicKey) }
}

/// No names or account IDs are broadcast. Only already-authorized, pinned contact keys are eligible.
nonisolated enum RadioContactSecurity {
    struct Invitation: Codable {
        let version: Int
        let fingerprint: String
        let nonce: Data
        let proof: Data
    }
    static func fingerprint(_ key: Data) -> String {
        SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
    }
    static func publicKey(_ privateKey: Data) throws -> Data {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey).publicKey.rawRepresentation
    }
    private static func key(privateKey: Data, contactKey: Data, sender: String, recipient: String, purpose: String) throws -> SymmetricKey {
        let own = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
        let peer = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: contactKey)
        let secret = try own.sharedSecretFromKeyAgreement(with: peer)
        let context = try JSONEncoder().encode(["MYAOW-CONTACT-RADIO-V2", purpose, sender, recipient])
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("Myaow private radio".utf8), sharedInfo: context, outputByteCount: 32)
    }
    static func invitation(privateKey: Data, contactKey: Data, sender: String, recipient: String) throws -> Data {
        let secret = try key(privateKey: privateKey, contactKey: contactKey, sender: sender, recipient: recipient, purpose: "invitation")
        let fingerprint = fingerprint(try publicKey(privateKey))
        let nonce = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        return try JSONEncoder().encode(Invitation(version: 2, fingerprint: fingerprint, nonce: nonce,
            proof: Data(HMAC<SHA256>.authenticationCode(for: Data(fingerprint.utf8) + nonce, using: secret))))
    }
    static func verifyInvitation(_ data: Data, privateKey: Data, contactKey: Data, sender: String, recipient: String) -> Bool {
        guard data.count <= 512, let value = try? JSONDecoder().decode(Invitation.self, from: data),
              value.version == 2, value.nonce.count == 16, value.fingerprint == fingerprint(contactKey),
              let secret = try? key(privateKey: privateKey, contactKey: contactKey, sender: sender, recipient: recipient, purpose: "invitation") else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(value.proof, authenticating: Data(value.fingerprint.utf8) + value.nonce, using: secret)
    }
    static func seal(_ data: Data, privateKey: Data, contactKey: Data, sender: String, recipient: String) throws -> Data {
        let secret = try key(privateKey: privateKey, contactKey: contactKey, sender: sender, recipient: recipient, purpose: "audio")
        return try ChaChaPoly.seal(data, using: secret, authenticating: Data("MYAOW-RADIO-V2".utf8)).combined
    }
    static func open(_ data: Data, privateKey: Data, contactKey: Data, sender: String, recipient: String) throws -> Data {
        let secret = try key(privateKey: privateKey, contactKey: contactKey, sender: sender, recipient: recipient, purpose: "audio")
        return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: secret, authenticating: Data("MYAOW-RADIO-V2".utf8))
    }
}

struct RadioPrivateMessage: Codable, Sendable {
    let sequence: UInt64
    let packet: RadioPacket
}

/// Allows modest datagram reordering, but never reopens an old replay window.
struct RadioReplayWindow {
    private var highest: UInt64 = 0
    private var seen: Set<UInt64> = []
    mutating func accept(_ sequence: UInt64) -> Bool {
        guard sequence > 0, sequence > highest || highest - sequence < 256,
              !seen.contains(sequence) else { return false }
        highest = max(highest, sequence)
        seen = seen.filter { highest - $0 < 256 }; seen.insert(sequence)
        return true
    }
}
