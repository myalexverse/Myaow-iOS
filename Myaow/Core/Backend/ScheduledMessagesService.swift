import SwiftUI
import CryptoKit

public struct ScheduledMessageItem: Identifiable, Codable, Sendable {
    public let id: UUID
    public let conversationId: String
    public let recipientName: String
    public let text: String
    public let scheduledDate: Date
    public var recipientId: String? = nil
    public var groupId: String? = nil
    public var isSent = false
    public var state = "pending"
}

@MainActor @Observable
public final class ScheduledMessagesService {
    public static let shared = ScheduledMessagesService()
    public private(set) var pendingMessages: [ScheduledMessageItem] = []
    var onHistoryUpdate: (([ScheduledMessageItem]) -> Void)?
    public private(set) var isRefreshing = false
    public var lastError: String?
    private var loadedOwner = ""
    private struct ServerItem: Decodable { let id: UUID; let preview: String; let state: String }
    private struct ListResponse: Decodable { let messages: [ServerItem] }
    private init() {}

    private var owner: String { IdentityManager.shared.currentIdentity.myaowId }
    private var draftsKey: String { "myaow_secure_schedule_attempts_" + owner }
    private func previewKey() throws -> SymmetricKey {
        let bytes = try SecureHex.decode(IdentityManager.shared.privateKeyHex, bytes: 32)
        return HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes), salt: Data(owner.utf8), info: Data("MYAOW-SCHEDULE-PREVIEW-V1".utf8), outputByteCount: 32)
    }
    private func decode(_ row: ServerItem) throws -> ScheduledMessageItem {
        guard let bytes = Data(base64Encoded: row.preview) else { throw SecureMessageError.invalidEnvelope }
        let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: bytes), using: previewKey(), authenticating: Data(row.id.uuidString.utf8))
        var item = try JSONDecoder().decode(ScheduledMessageItem.self, from: plain)
        guard item.id == row.id else { throw SecureMessageError.invalidEnvelope }
        item.state = row.state; item.isSent = row.state == "queued" || row.state == "delivered"
        return item
    }
    public func scheduleMessage(conversationId: String, recipientName: String, text: String, date: Date,
                                recipientId: String? = nil, groupId: String? = nil) async throws {
        let own = owner
        if loadedOwner != own { pendingMessages = []; loadedOwner = own }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 64 * 1024,
              date > Date(), date.timeIntervalSinceNow <= 30 * 86400 else {
            throw RelayRequestError(message: "Elige una hora futura dentro de los próximos 30 días y escribe un mensaje.")
        }
        var attempts = UserDefaults.standard.dictionary(forKey: draftsKey) as? [String: Data] ?? [:]
        // Reuse the same ciphertext and ID after a lost HTTP response.
        let fingerprint = SHA256.hash(data: Data("\(conversationId)|\(date.timeIntervalSince1970)|\(text)".utf8)).map { String(format: "%02x", $0) }.joined()
        let body: [String: Any]
        if let bytes = attempts[fingerprint], let cached = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] {
            body = cached
        } else {
            let packets = try await GroupDeliveryService.packets(text: text, recipientId: recipientId, groupId: groupId)
            let messageID = groupId == nil ? (packets.first?["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID() : UUID()
            let item = ScheduledMessageItem(id: messageID, conversationId: conversationId, recipientName: recipientName, text: text, scheduledDate: date, recipientId: recipientId, groupId: groupId)
            guard owner == own else { throw SecureMessageError.keyUnavailable }
            let preview = try AES.GCM.seal(JSONEncoder().encode(item), using: previewKey(), authenticating: Data(item.id.uuidString.utf8)).combined!.base64EncodedString()
            body = ["id": item.id.uuidString, "due": Int64(date.timeIntervalSince1970 * 1000), "preview": preview, "packets": packets]
            attempts[fingerprint] = try JSONSerialization.data(withJSONObject: body)
            UserDefaults.standard.set(attempts, forKey: draftsKey)
        }
        let data = try await RelayAPI.request("/api/v1/scheduled-v2", method: "POST", body: body)
        guard owner == own else { throw SecureMessageError.keyUnavailable }
        let item = try decode(JSONDecoder().decode(ServerItem.self, from: data))
        pendingMessages.removeAll { $0.id == item.id }; pendingMessages.append(item)
        attempts.removeValue(forKey: fingerprint); UserDefaults.standard.set(attempts, forKey: draftsKey)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    public func cancelScheduledMessage(id: UUID) async throws {
        let own = owner
        if pendingMessages.first(where: { $0.id == id })?.state == "unconfirmed" {
            let data = try await RelayAPI.request("/api/v1/scheduled-v2")
            let rows = try JSONDecoder().decode(ListResponse.self, from: data).messages
            if rows.contains(where: { $0.id == id }) {
                _ = try await RelayAPI.request("/api/v1/scheduled-v2/\(id.uuidString)", method: "DELETE")
            }
        } else {
            _ = try await RelayAPI.request("/api/v1/scheduled-v2/\(id.uuidString)", method: "DELETE")
        }
        guard owner == own else { return }
        removeAttempt(id)
        pendingMessages.removeAll { $0.id == id }
    }
    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let own = owner
        if loadedOwner != own { pendingMessages = []; loadedOwner = own }
        do {
            let data = try await RelayAPI.request("/api/v1/scheduled-v2")
            guard owner == own else { return }
            let rows = try JSONDecoder().decode(ListResponse.self, from: data).messages
            pendingMessages = try rows.map(decode)
            let known = Set(rows.map(\.id))
            let attempts = UserDefaults.standard.dictionary(forKey: draftsKey) as? [String: Data] ?? [:]
            for bytes in attempts.values {
                guard let data = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let idText = data["id"] as? String, let id = UUID(uuidString: idText), let preview = data["preview"] as? String else { continue }
                if known.contains(id) { removeAttempt(id) }
                else { pendingMessages.append(try decode(ServerItem(id: id, preview: preview, state: "unconfirmed"))) }
            }
            onHistoryUpdate?(pendingMessages.filter { $0.state == "queued" || $0.state == "delivered" })
            lastError = nil
        } catch { lastError = error.localizedDescription }
    }
    private func removeAttempt(_ id: UUID) {
        var attempts = UserDefaults.standard.dictionary(forKey: draftsKey) as? [String: Data] ?? [:]
        attempts = attempts.filter { _, bytes in
            let item = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            return item?["id"] as? String != id.uuidString
        }
        UserDefaults.standard.set(attempts, forKey: draftsKey)
    }
    public func retryConfirmation(id: UUID) async throws {
        let attempts = UserDefaults.standard.dictionary(forKey: draftsKey) as? [String: Data] ?? [:]
        for bytes in attempts.values {
            guard let body = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], body["id"] as? String == id.uuidString else { continue }
            _ = try await RelayAPI.request("/api/v1/scheduled-v2", method: "POST", body: body)
            removeAttempt(id); await refresh(); return
        }
    }
    public func scheduledMessagesFor(conversationId: String) -> [ScheduledMessageItem] {
        guard loadedOwner.isEmpty || loadedOwner == owner else { return [] }
        return pendingMessages.filter { $0.conversationId == conversationId }.sorted { $0.scheduledDate < $1.scheduledDate }
    }
}

@MainActor
enum GroupDeliveryService {
    struct Member: Decodable {
        let myaow_id: String; let display_name: String?; let role: String
        var model: SpaceMemberModel { .init(displayName: display_name ?? myaow_id, myaowId: myaow_id, role: role == "admin" ? "Admin" : "Miembro", isOnline: false) }
    }
    static func members(_ group: String) async throws -> [Member] {
        struct Response: Decodable { let members: [Member] }
        let data = try await RelayAPI.request("/api/v1/groups/\(group.lowercased())/members")
        return try JSONDecoder().decode(Response.self, from: data).members
    }
    static func packets(text: String, recipientId: String?, groupId: String?, messageType: String = "text", mediaUrl: String? = nil, recipientIDs: [String]? = nil, replyToId: String? = nil, groupMessageId: String? = nil, decorationJSON: String? = nil) async throws -> [[String: Any]] {
        let own = IdentityManager.shared.currentIdentity
        let recipients: [String]
        if let groupId {
            let membership = try await members(groupId)
            if decorationJSON != nil {
                guard membership.contains(where: { $0.myaow_id == own.myaowId && ["admin", "owner"].contains($0.role) }) else { throw DecorationError.administratorRequired }
            }
            let currentMembers = membership.map(\.myaow_id).filter { $0 != own.myaowId }
            recipients = recipientIDs.map { original in currentMembers.filter { original.contains($0) } } ?? currentMembers
        } else { recipients = recipientId.map { [$0] } ?? [] }
        guard !recipients.isEmpty, recipients.count <= 100 else { throw RelayRequestError(message: "El grupo necesita al menos otra persona. Esta beta admite hasta 100 destinatarios por mensaje.") }
        var result: [[String: Any]] = []
        for recipient in recipients {
            let id = UUID().uuidString
            let cipher = try await SecureMessagingService.shared.seal(.init(text: text, messageType: messageType, mediaUrl: mediaUrl, replyToId: replyToId, groupId: groupId?.lowercased(), groupMessageId: groupMessageId, decorationJSON: decorationJSON), messageId: id, recipientId: recipient)
            guard IdentityManager.shared.currentIdentity.myaowId == own.myaowId else { throw SecureMessageError.identityChanged }
            result.append(["id": id, "type": "message", "senderMyaowId": own.myaowId, "senderDisplayName": own.displayName,
                "recipientMyaowId": recipient, "encryptedPayload": cipher])
        }
        return result
    }
}
