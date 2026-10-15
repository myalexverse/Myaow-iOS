import Foundation
import CryptoKit

/// Proof of possession of the existing X25519 identity key for relay authentication.
/// This authenticates the socket; it does not establish or certify end-to-end message encryption.
enum RelayAuthentication {
    static let protocolName = "myaow-x25519-hkdf-sha256-v2"
    enum Failure: Error { case invalidChallenge }

    static func proof(myaowId: String, privateKeyHex: String, nonce: String, serverPublicKeyHex: String) throws -> String {
        func decode(_ hex: String) throws -> Data {
            guard hex.count == 64, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw Failure.invalidChallenge }
            var data = Data()
            var index = hex.startIndex
            while index < hex.endIndex {
                let end = hex.index(index, offsetBy: 2)
                guard let byte = UInt8(hex[index..<end], radix: 16) else { throw Failure.invalidChallenge }
                data.append(byte)
                index = end
            }
            return data
        }
        _ = try decode(nonce)
        let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: decode(privateKeyHex))
        let serverKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: decode(serverPublicKeyHex))
        let publicHex = privateKey.publicKey.rawRepresentation.map { String(format: "%02x", $0) }.joined()
        let context = Data(["MYAOW-AUTH-V2", myaowId, nonce, serverPublicKeyHex, publicHex].joined(separator: "\0").utf8)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: serverKey)
        let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(nonce.utf8), sharedInfo: context, outputByteCount: 32)
        return HMAC<SHA256>.authenticationCode(for: context, using: key).map { String(format: "%02x", $0) }.joined()
    }
}
