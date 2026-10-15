import Foundation
import CryptoKit

/// Only message identifiers; never text, envelopes or identity keys.
struct GroupReceiptStore {
    struct Entry: Codable {
        let localID: String
        let packetIDs: Set<String>
        var delivered: Set<String>
    }
    let root: URL
    private func path(_ owner: String) -> URL {
        root.appendingPathComponent(SecureHex.encode(Data(SHA256.hash(data: Data(owner.utf8)))) + ".json")
    }
    func entries(owner: String) throws -> [Entry] {
        let url = path(owner)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
    }
    func register(owner: String, localID: String, packetIDs: [String]) throws {
        guard UUID(uuidString: localID) != nil, !packetIDs.isEmpty, packetIDs.count <= 100, packetIDs.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw SecureMessageError.invalidEnvelope }
        let ids = Set(packetIDs.map { $0.uppercased() })
        var current = try entries(owner: owner)
        if let existing = current.first(where: { $0.localID == localID }) {
            guard existing.packetIDs == ids else { throw SecureMessageError.invalidEnvelope }
            return
        }
        guard current.count < 1000 else { throw SecureMessageError.invalidEnvelope }
        current.append(Entry(localID: localID, packetIDs: ids, delivered: []))
        try write(current, owner: owner)
    }
    func apply(_ deliveredIDs: Set<String>, owner: String, confirm: (String) -> Bool) throws {
        let received = Set(deliveredIDs.map { $0.uppercased() })
        var changed = false
        var remaining: [Entry] = []
        for var entry in try entries(owner: owner) {
            let before = entry.delivered
            entry.delivered.formUnion(entry.packetIDs.intersection(received))
            if entry.delivered == entry.packetIDs, confirm(entry.localID) {
                changed = true
            } else {
                remaining.append(entry)
                if entry.delivered != before { changed = true }
            }
        }
        if changed { try write(remaining, owner: owner) }
    }
    private func write(_ entries: [Entry], owner: String) throws {
        // Atomic replacement also preserves progress if the app stops between recipients.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: path(owner), options: .atomic)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: path(owner).path)
        #endif
    }
}
