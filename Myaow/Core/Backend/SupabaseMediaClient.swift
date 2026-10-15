import Foundation
import CryptoKit

/// Encrypted objects are private. URLs identify an object; they grant no access.
enum SupabaseMediaClient {
    static let maximumPlaintextBytes = 10 * 1024 * 1024
    struct Prepared: Codable {
        let id: String
        let ciphertext: Data
        let keyFragment: String
        let plaintextHash: String
        static func create(_ data: Data) throws -> Self {
            let sealed = try EncryptedAttachment.seal(data)
            return Self(id: UUID().uuidString.lowercased(), ciphertext: sealed.ciphertext, keyFragment: sealed.keyFragment,
                        plaintextHash: SecureHex.encode(Data(SHA256.hash(data: data))))
        }
    }
    static func upload(base: URL, token: String, data: Data, recipient: String?, groupID: String? = nil, prepared: Prepared? = nil, session: URLSession = .shared) async throws -> (mediaId: String, mediaUrl: String, groupReaders: [String]?) {
        guard !data.isEmpty, data.count <= maximumPlaintextBytes else { throw SupabaseHTTPError(status: 413) }
        guard recipient != nil || groupID != nil else { throw SupabaseHTTPError(status: 501) }
        let sealed = try prepared ?? Prepared.create(data)
        guard sealed.plaintextHash == SecureHex.encode(Data(SHA256.hash(data: data))) else { throw SecureMessageError.invalidEnvelope }
        let id = sealed.id
        var body: [String: Any] = ["id": id, "bytes": sealed.ciphertext.count,
            "sha256": SecureHex.encode(Data(SHA256.hash(data: sealed.ciphertext)))]
        if let groupID { body["groupId"] = groupID.lowercased() } else { body["recipient"] = recipient }
        let reservation = try await SupabaseClient.request(base: base, path: "media/prepare", body: body, token: token, session: session)
        let reserved = try JSONSerialization.jsonObject(with: reservation) as? [String: Any]
        let ready = reserved?["ready"] as? Bool == true
        let readers = reserved?["readers"] as? [String]
        if groupID != nil {
            guard let readers, !readers.isEmpty, readers.count <= 100 else { throw SupabaseHTTPError(status: 403) }
        }
        var request = URLRequest(url: base.appendingPathComponent("media/upload/\(id)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = sealed.ciphertext
        if !ready {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            guard http.statusCode == 200 else { throw SupabaseHTTPError(status: http.statusCode) }
        }
        var url = URLComponents(url: base.appendingPathComponent("media/\(id)"), resolvingAgainstBaseURL: false)!
        url.fragment = sealed.keyFragment
        return (id, url.url!.absoluteString, groupID == nil ? nil : readers)
    }

    static func objectID(from url: URL, base: URL) throws -> String {
        guard url.scheme == "https", url.host == base.host, url.port == base.port,
              url.user == nil, url.password == nil, url.query == nil,
              url.deletingLastPathComponent().path == base.appendingPathComponent("media").path,
              UUID(uuidString: url.lastPathComponent) != nil else { throw URLError(.badURL) }
        return url.lastPathComponent.lowercased()
    }

    static func download(base: URL, token: String, url: URL) async throws -> Data {
        let id = try objectID(from: url, base: base)
        guard let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else { throw SecureMessageError.invalidEnvelope }
        // Only the opaque ID enters HTTP. The decryption key never leaves this process.
        let bytes = try await SupabaseClient.request(base: base, path: "media/download", body: ["id": id], token: token)
        guard bytes.count <= maximumPlaintextBytes + 28 else { throw SupabaseHTTPError(status: 413) }
        return try EncryptedAttachment.open(bytes, keyFragment: key)
    }
}
