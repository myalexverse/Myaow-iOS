import Foundation
import CryptoKit

/// A stable encrypted batch per local message. Retrying after a lost response
/// or app restart must use exactly the same recipient IDs and ciphertext.
struct GroupMessageOutbox {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GroupOutbox-v2", isDirectory: true)
    }
    private func path(owner: String, host: String, id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id) else { throw SecureMessageError.invalidEnvelope }
        let scope = SecureHex.encode(Data(SHA256.hash(data: Data((host + "\u{0000}" + owner).utf8))))
        return root.appendingPathComponent(scope, isDirectory: true).appendingPathComponent(uuid.uuidString + ".json")
    }
    func load(owner: String, host: String, id: String) throws -> [[String: Any]]? {
        let url = try path(owner: owner, host: host, id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= 4_400_000,
              let packets = try JSONSerialization.jsonObject(with: bytes) as? [[String: Any]] else { throw SecureMessageError.invalidEnvelope }
        return packets
    }
    func save(_ packets: [[String: Any]], owner: String, host: String, id: String) throws {
        guard !packets.isEmpty, packets.count <= 100, packets.allSatisfy({
            Set($0.keys) == ["id", "type", "senderMyaowId", "senderDisplayName", "recipientMyaowId", "encryptedPayload"] &&
            ($0["id"] as? String).flatMap(UUID.init(uuidString:)) != nil &&
            $0["senderMyaowId"] as? String == owner && $0["encryptedPayload"] is String
        }) else { throw SecureMessageError.invalidEnvelope }
        let bytes = try JSONSerialization.data(withJSONObject: packets, options: .sortedKeys)
        guard bytes.count <= 4_400_000 else { throw SecureMessageError.invalidEnvelope }
        let url = try path(owner: owner, host: host, id: id)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try Data(contentsOf: url) == bytes else { throw SecureMessageError.invalidEnvelope }
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
    func remove(owner: String, host: String, id: String) throws {
        let url = try path(owner: owner, host: host, id: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
