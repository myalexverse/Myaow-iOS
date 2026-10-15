import Foundation
struct CallICEConfiguration: Decodable, Sendable {
    struct Server: Decodable, Sendable { let urls: [String]; let username: String; let credential: String }
    let iceServers: [Server]
    let expiresAt: Double
    let iceTransportPolicy: String
    @MainActor static func fetch() async throws -> Self {
        let data = try await RelayAPI.request("/api/v1/webrtc/ice-servers")
        let config = try JSONDecoder().decode(Self.self, from: data)
        guard config.expiresAt > Date().timeIntervalSince1970 + 60, config.iceTransportPolicy == "relay",
              !config.iceServers.isEmpty, config.iceServers.allSatisfy({ !$0.urls.isEmpty && !$0.username.isEmpty && !$0.credential.isEmpty && $0.urls.allSatisfy { $0.hasPrefix("turn:") || $0.hasPrefix("turns:") } }) else {
            throw RelayRequestError(message: "El servicio de llamadas todavía no está configurado.")
        }
        return config
    }
}
