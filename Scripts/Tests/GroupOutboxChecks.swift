import Foundation

@main struct GroupOutboxChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = GroupMessageOutbox(root: root), id = UUID().uuidString
        let packets: [[String: Any]] = [["id": UUID().uuidString, "type": "message", "senderMyaowId": "MYAOW-ONE", "senderDisplayName": "Prueba", "recipientMyaowId": "MYAOW-TWO", "encryptedPayload": "ciphertext"]]
        try store.save(packets, owner: "MYAOW-ONE", host: "https://one.invalid", id: id)
        let restored = try GroupMessageOutbox(root: root).load(owner: "MYAOW-ONE", host: "https://one.invalid", id: id)!
        precondition(NSDictionary(dictionary: restored[0]).isEqual(to: packets[0]))
        try store.save(restored, owner: "MYAOW-ONE", host: "https://one.invalid", id: id)
        let otherOwner = try store.load(owner: "MYAOW-TWO", host: "https://one.invalid", id: id); precondition(otherOwner == nil)
        let otherHost = try store.load(owner: "MYAOW-ONE", host: "https://other.invalid", id: id); precondition(otherHost == nil)
        var changed = packets; changed[0]["encryptedPayload"] = "different"
        do { try store.save(changed, owner: "MYAOW-ONE", host: "https://one.invalid", id: id); fatalError("Replaced a live retry") } catch {}
        changed = packets; changed[0]["text"] = "private text"
        do { try store.save(changed, owner: "MYAOW-ONE", host: "https://one.invalid", id: UUID().uuidString); fatalError("Stored plaintext") } catch {}
        do { _ = try store.load(owner: "MYAOW-ONE", host: "https://one.invalid", id: "../foreign"); fatalError("Invalid path") } catch {}
        try store.remove(owner: "MYAOW-ONE", host: "https://one.invalid", id: id)
        let cleared = try store.load(owner: "MYAOW-ONE", host: "https://one.invalid", id: id)
        precondition(cleared == nil)
        print("PASS: group retry survives restart, preserves exact ciphertext and IDs, isolates accounts/servers, rejects plaintext and path traversal.")
    }
}
