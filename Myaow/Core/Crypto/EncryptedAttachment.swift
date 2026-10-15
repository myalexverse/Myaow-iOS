import Foundation
import CryptoKit

enum EncryptedAttachment {
    static let fragmentPrefix = "myaow-media-v2="
    static func seal(_ bytes: Data) throws -> (ciphertext: Data, keyFragment: String) {
        let key = SymmetricKey(size: .bits256)
        let sealed = try ChaChaPoly.seal(bytes, using: key, authenticating: Data("MYAOW-MEDIA-V2".utf8))
        return (sealed.combined, fragmentPrefix + SecureHex.encode(key.withUnsafeBytes { Data($0) }))
    }
    static func open(_ bytes: Data, keyFragment: String) throws -> Data {
        guard keyFragment.hasPrefix(fragmentPrefix) else { throw SecureMessageError.invalidEnvelope }
        let key = try SecureHex.decode(String(keyFragment.dropFirst(fragmentPrefix.count)), bytes: 32)
        return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: bytes), using: SymmetricKey(data: key),
                                   authenticating: Data("MYAOW-MEDIA-V2".utf8))
    }
}
