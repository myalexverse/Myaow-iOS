import Foundation
import CryptoKit

/// One atomic file per encrypted packet, scoped to the account. No plaintext or private keys.
struct MessageOutbox {
    let root: URL

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SecureOutbox-v2", isDirectory: true)
    }

    private func directory(account: String) -> URL {
        let digest = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(digest, isDirectory: true)
    }

    private func path(account: String, id: String) throws -> URL {
        guard let uuid = UUID(uuidString: id) else { throw SecureMessageError.invalidEnvelope }
        return directory(account: account).appendingPathComponent(uuid.uuidString + ".json")
    }

    func packet(account: String, id: String) throws -> String? {
        let url = try path(account: account, id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    func enqueue(_ packet: String, account: String, id: String) throws {
        guard packet.utf8.count <= 256 * 1024 else { throw SecureMessageError.invalidEnvelope }
        let dir = directory(account: account)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = try path(account: account, id: id)
        if let existing = try self.packet(account: account, id: id) {
            guard existing == packet else { throw SecureMessageError.invalidEnvelope }
            return
        }
        try Data(packet.utf8).write(to: url, options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }

    func pending(account: String, limit: Int = 50) throws -> [(id: String, packet: String)] {
        let dir = directory(account: account)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "json" }
            .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) < ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
        return try urls.prefix(limit).map { ($0.deletingPathExtension().lastPathComponent, String(decoding: try Data(contentsOf: $0), as: UTF8.self)) }
    }

    func acknowledge(account: String, id: String) throws {
        let url = try path(account: account, id: id)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
