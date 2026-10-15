import Foundation

struct SecureMessageMutation: Codable {
    enum Action: String, Codable { case edit, delete, react, read }
    let action: Action
    let targetId: String
    let text: String
    let date: Date

    func validate() throws {
        guard UUID(uuidString: targetId) != nil, text.utf8.count <= 64 * 1024,
              date.timeIntervalSince1970.isFinite,
              action != .react || text.utf8.count <= 32,
              action != .edit || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SecureMessageError.invalidEnvelope
        }
    }
}
