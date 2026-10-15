import Foundation
import CryptoKit

enum IdentityVaultError: Error { case missingKey, inconsistentIdentity, invalidBackup, verificationFailed }

/// The complete identity record is committed atomically in Keychain before deleting legacy secrets.
struct IdentityVault {
    struct Record: Codable, Equatable {
        var identity: UserIdentity
        let privateKey: Data
    }
    let defaults: UserDefaults
    let secrets: any SecretStore
    let key = "identity_record_v2"

    func loadOrCreate() throws -> Record {
        if let data = try secrets.read(key: key) {
            let record = try JSONDecoder().decode(Record.self, from: data)
            try validate(record)
            // A previous migration may have committed before the defaults cleanup.
            defaults.removeObject(forKey: "myaow_private_key")
            defaults.set(try JSONEncoder().encode(record.identity), forKey: "myaow_local_identity")
            return record
        }
        let record: Record
        if let legacyData = defaults.data(forKey: "myaow_local_identity") {
            let identity = try JSONDecoder().decode(UserIdentity.self, from: legacyData)
            guard let legacyHex = defaults.string(forKey: "myaow_private_key") else { throw IdentityVaultError.missingKey }
            record = Record(identity: identity, privateKey: try SecureHex.decode(legacyHex, bytes: 32))
        } else {
            // Never silently replace an existing but incomplete identity.
            guard defaults.object(forKey: "myaow_private_key") == nil,
                  !defaults.bool(forKey: "myaow_has_completed_onboarding") else { throw IdentityVaultError.invalidBackup }
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            record = Record(identity: UserIdentity(publicKeyHex: SecureHex.encode(privateKey.publicKey.rawRepresentation)),
                            privateKey: privateKey.rawRepresentation)
        }
        try save(record)
        return record
    }

    func save(_ record: Record) throws {
        try validate(record)
        let data = try JSONEncoder().encode(record)
        try secrets.write(key: key, data: data)
        guard try secrets.read(key: key) == data else { throw IdentityVaultError.verificationFailed }
        defaults.set(try JSONEncoder().encode(record.identity), forKey: "myaow_local_identity")
        defaults.removeObject(forKey: "myaow_private_key")
    }

    private func validate(_ record: Record) throws {
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: record.privateKey)
        guard key.publicKey.rawRepresentation == (try SecureHex.decode(record.identity.publicKeyHex, bytes: 32)),
              !record.identity.myaowId.isEmpty else { throw IdentityVaultError.inconsistentIdentity }
    }
}

enum SecureHex {
    static func decode(_ value: String, bytes: Int) throws -> Data {
        let characters = Array(value.utf8)
        guard characters.count == bytes * 2 else { throw CryptoError.invalidKeyData }
        var result = Data(capacity: bytes)
        func nibble(_ c: UInt8) throws -> UInt8 {
            switch c {
            case 48...57: return c - 48
            case 65...70: return c - 55
            case 97...102: return c - 87
            default: throw CryptoError.invalidKeyData
            }
        }
        for i in stride(from: 0, to: characters.count, by: 2) {
            result.append(try nibble(characters[i]) * 16 + nibble(characters[i + 1]))
        }
        return result
    }
    static func encode(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
}
