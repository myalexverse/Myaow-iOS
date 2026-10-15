import Foundation
import CryptoKit

// Exercise the production HTTP client with an interrupted response, not a second implementation.
final class InterruptedUpload: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var attempts = 0
    nonisolated(unsafe) static var ready = false
    nonisolated(unsafe) static var failBeforeCommit = false
    nonisolated(unsafe) static var ids = Set<String>()
    nonisolated(unsafe) static var group: String?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "retry.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-session")
        precondition(request.url?.fragment == nil)
        if request.url!.lastPathComponent == "prepare" {
            var bytes = request.httpBody ?? Data()
            if bytes.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    bytes.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = try! JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            if let group = Self.group { precondition(body["groupId"] as? String == group && body["recipient"] == nil) }
            else { precondition(body["recipient"] as? String == "B" && body["groupId"] == nil) }
            reply(try! JSONSerialization.data(withJSONObject: ["ready": Self.ready, "readers": ["B"]])); return
        }
        Self.ids.insert(request.url!.lastPathComponent)
        Self.attempts += 1
        if Self.attempts == 1 {
            Self.ready = !Self.failBeforeCommit
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        } else { Self.ready = true; reply(Data("{}".utf8)) }
    }
    private func reply(_ data: Data) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct AttachmentRetryChecks {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [InterruptedUpload.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let base = URL(string: "https://retry.test/functions/v1/myaow-api")!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for group in [nil, UUID().uuidString.lowercased()] as [String?] {
        InterruptedUpload.group = group
        for beforeCommit in [false, true] {
            InterruptedUpload.attempts = 0; InterruptedUpload.ready = false
            InterruptedUpload.failBeforeCommit = beforeCommit; InterruptedUpload.ids = []
            let mid = UUID().uuidString, bytes = Data("fictitious attachment".utf8), key = Data(repeating: 4, count: 32)
            let initial = try PendingMediaUploadStore(base: base, owner: "A", root: root).prepare(data: bytes, messageID: mid, privateKey: key)
            do {
                _ = try await SupabaseMediaClient.upload(base: base, token: "test-session", data: bytes, recipient: group == nil ? "B" : nil, groupID: group, prepared: initial, session: session)
                fatalError("Expected lost connection")
            } catch let error as URLError { precondition(error.code == .networkConnectionLost) }
            let resumed = try PendingMediaUploadStore(base: base, owner: "A", root: root).prepare(data: bytes, messageID: mid, privateKey: key)
            let result = try await SupabaseMediaClient.upload(base: base, token: "test-session", data: bytes, recipient: group == nil ? "B" : nil, groupID: group, prepared: resumed, session: session)
            precondition(result.mediaId == initial.id && resumed.ciphertext == initial.ciphertext)
            precondition(InterruptedUpload.ids == [initial.id])
            precondition(InterruptedUpload.attempts == (beforeCommit ? 2 : 1))
            print("PASS: \(group == nil ? "direct" : "group") restart after connection loss \(beforeCommit ? "before" : "after") server commit reuses the same encrypted object")
        }
        }
    }
}
