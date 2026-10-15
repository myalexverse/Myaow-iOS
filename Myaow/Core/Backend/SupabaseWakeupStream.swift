import Foundation
import CryptoKit

/// Private, session-bound hints only. Every message is still downloaded through the authenticated API.
enum SupabaseWakeupStream {
    private actor Liveness {
        let started = Date()
        var lastFrame = Date()
        var joined = false
        func received(join: Bool = false) { lastFrame = Date(); if join { joined = true } }
        func expired() -> Bool { Date().timeIntervalSince(joined ? lastFrame : started) > (joined ? 45 : 20) }
    }
    static let projectHost = "your-project-ref.supabase.co"
    // Public project identifier; grants no access to Myaow data without the session header.
    static let publicKey = "sb_publishable_V9TtL0H-PAGIhbBtJbP26g_x-sAo4Vb"
    static func topic(token: String) -> String {
        "myaow:" + SecureHex.encode(Data(SHA256.hash(data: Data(token.utf8))))
    }
    static func run(base: URL, token: String, overrideTopic: String? = nil,
                    onReady: @escaping @Sendable () async -> Void,
                    onWake: @escaping @Sendable () async -> Void) async throws {
        guard base.scheme == "https", base.host == projectHost,
              token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw URLError(.badURL) }
        var url = URLComponents()
        url.scheme = "wss"; url.host = base.host; url.path = "/realtime/v1/websocket"
        url.queryItems = [.init(name: "apikey", value: publicKey), .init(name: "vsn", value: "1.0.0")]
        var request = URLRequest(url: url.url!)
        request.setValue(token, forHTTPHeaderField: "x-myaow-session")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.maximumMessageSize = 16384
        let channel = "realtime:" + (overrideTopic ?? topic(token: token))
        let liveness = Liveness()
        socket.resume()
        let heartbeat = Task {
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(15))
                    guard await !liveness.expired() else { throw URLError(.timedOut) }
                    try await send(socket, topic: "phoenix", event: "heartbeat", payload: [:], ref: UUID().uuidString)
                }
            } catch { socket.cancel(with: .goingAway, reason: nil) }
        }
        defer { heartbeat.cancel(); socket.cancel(with: .goingAway, reason: nil) }
        try await withTaskCancellationHandler {
            try await send(socket, topic: channel, event: "phx_join",
                           payload: ["config": ["private": true, "broadcast": ["ack": false, "self": false], "presence": ["enabled": false], "postgres_changes": []]], ref: "join")
            while !Task.isCancelled {
                let message = try await socket.receive()
                let data: Data
                switch message { case .data(let bytes): data = bytes; case .string(let text): data = Data(text.utf8); @unknown default: continue }
                guard let item = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
                let event = item["event"] as? String
                await liveness.received()
                if event == "phx_error" || event == "phx_close" { throw URLError(.networkConnectionLost) }
                guard item["topic"] as? String == channel else { continue }
                let payload = item["payload"] as? [String: Any] ?? [:]
                if event == "phx_reply", item["ref"] as? String == "join" {
                    guard payload["status"] as? String == "ok" else { throw SupabaseHTTPError(status: 403) }
                    await liveness.received(join: true)
                    await onReady()
                } else if event == "broadcast", payload["event"] as? String == "wake" {
                    await onWake()
                }
            }
        } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
    }
    private static func send(_ socket: URLSessionWebSocketTask, topic: String, event: String, payload: [String: Any], ref: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["topic":topic,"event":event,"payload":payload,"ref":ref])
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
}
