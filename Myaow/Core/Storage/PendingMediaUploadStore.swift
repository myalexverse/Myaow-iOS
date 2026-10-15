import Foundation
import CryptoKit

/// Saves upload identity/ciphertext before network work. Reopening the app reuses
/// the reservation instead of uploading duplicates and consuming the beta quota.
struct PendingMediaUploadStore {
    let root: URL
    let scope: String
    init(base: URL, owner: String, root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PendingMedia-v1")
        scope = SecureHex.encode(Data(SHA256.hash(data: Data((base.absoluteString + "\0" + owner).utf8))))
    }
    private func file(_ messageID: String) throws -> URL {
        guard let id = UUID(uuidString: messageID) else { throw SecureMessageError.invalidEnvelope }
        return root.appendingPathComponent(scope).appendingPathComponent(id.uuidString)
    }
    func prepare(data: Data, messageID: String, privateKey: Data) throws -> SupabaseMediaClient.Prepared {
        let path = try file(messageID)
        let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: privateKey), salt: Data(scope.utf8), info: Data("MYAOW-PENDING-MEDIA-V1".utf8), outputByteCount: 32)
        if FileManager.default.fileExists(atPath: path.path) {
            let bytes = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: Data(contentsOf: path)), using: key)
            let existing = try JSONDecoder().decode(SupabaseMediaClient.Prepared.self, from: bytes)
            guard existing.plaintextHash == SecureHex.encode(Data(SHA256.hash(data: data))) else { throw SecureMessageError.invalidEnvelope }
            return existing
        }
        let prepared = try SupabaseMediaClient.Prepared.create(data)
        let bytes = try ChaChaPoly.seal(JSONEncoder().encode(prepared), using: key).combined
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: path, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path.path)
        #endif
        return prepared
    }
    func remove(messageID: String) throws {
        let path = try file(messageID)
        if FileManager.default.fileExists(atPath: path.path) { try FileManager.default.removeItem(at: path) }
    }
}
