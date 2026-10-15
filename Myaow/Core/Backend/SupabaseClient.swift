import Foundation

struct SupabaseHTTPError: LocalizedError {
    let status: Int
    var errorDescription: String? {
        switch status {
        case 401: return "Conecta tu cuenta para continuar."
        case 403: return "Esta acción requiere una invitación válida o permisos del grupo."
        case 404: return "No encontramos ese contacto o elemento."
        case 409: return "El estado cambió. Actualiza e inténtalo de nuevo."
        case 413: return "Este archivo supera el tamaño admitido en la beta."
        case 429: return "Hay demasiadas solicitudes. Espera un momento e inténtalo de nuevo."
        case 501: return "Esta función todavía no está disponible en esta conexión de prueba."
        default: return "No pudimos confirmar los cambios. Se conservan tus datos; revisa la conexión."
        }
    }
}

/// No Supabase service key belongs on the device. The only credential here is
/// the revocable session obtained with the existing local identity key.
enum SupabaseClient {
    static func request(base: URL, path: String, body: [String: Any] = [:], token: String? = nil, session: URLSession = .shared) async throws -> Data {
        guard base.scheme == "https", !path.hasPrefix("/"), !path.contains(".."), !path.contains(":") else { throw URLError(.badURL) }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(http.statusCode) else { throw SupabaseHTTPError(status: http.statusCode) }
        return data
    }

    static func authenticate(base: URL, id: String, privateKeyHex: String) async throws -> String {
        let data = try await request(base: base, path: "auth/challenge", body: ["myaowId": id])
        struct Challenge: Decodable { let id: String; let nonce: String; let serverPublicKeyHex: String; let `protocol`: String }
        let challenge = try JSONDecoder().decode(Challenge.self, from: data)
        guard challenge.protocol == RelayAuthentication.protocolName else { throw URLError(.cannotParseResponse) }
        let proof = try RelayAuthentication.proof(myaowId: id, privateKeyHex: privateKeyHex, nonce: challenge.nonce, serverPublicKeyHex: challenge.serverPublicKeyHex)
        let result = try await request(base: base, path: "auth/proof", body: ["id": challenge.id, "myaowId": id, "proof": proof])
        struct Session: Decodable { let sessionId: String }
        let token = try JSONDecoder().decode(Session.self, from: result).sessionId
        guard token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw URLError(.cannotParseResponse) }
        return token
    }
}

/// Maps existing feature routes without dropping the Edge Function URL prefix.
/// Unsupported features fail explicitly instead of contacting another backend.
struct SupabaseRoute {
    let path: String
    let body: [String: Any]
    init(_ legacyPath: String, method: String, body input: [String: Any] = [:]) throws {
        let parts = legacyPath.split(separator: "/").map(String.init)
        guard parts.starts(with: ["api", "v1"]) else { throw SupabaseHTTPError(status: 501) }
        let route = Array(parts.dropFirst(2))
        var body = input
        switch (route, method) {
        case (["calls", "signal"], "POST"): path = "calls/signal"
        case (["calls", "contacts"], "PUT"): path = "calls/contacts"
        case (["webrtc", "ice-servers"], "GET"): path = "webrtc/ice-servers"
        case (["push", "device"], "PUT"): path = "push/device"
        case (["groups", "create"], "POST"): path = "groups/create"
        case (["scheduled-v2"], "POST"): path = "schedules/create"
        case (["scheduled-v2"], "GET"): path = "schedules/list"
        case (["messages-v2", "batch"], "POST"): path = "messages/batch"
        case (["groups", "invite", "accept"], "POST"):
            path = "groups/accept"; body = ["inviteId": input["token"] ?? ""]
        case (["contacts", "block"], "POST"), (["contacts", "unblock"], "POST"):
            path = "contacts/\(route[1])"; body = ["target": input["blockedId"] ?? ""]
        default:
            if route.count == 3, route[0] == "groups", route[1] == "my", method == "GET" {
                path = "groups/list"; body = [:]
            } else if route.count == 3, route[0] == "contacts", route[1] == "blocked", method == "GET" {
                path = "contacts/blocked"; body = [:]
            } else if route.count == 3, route[0] == "groups", UUID(uuidString: route[1]) != nil {
                let operation = route[2]
                if operation == "planned-tasks", method == "POST" { path = "tasks/create-planned" }
                else if operation == "project", method == "GET" || method == "PUT" { path = method == "GET" ? "projects/get" : "projects/save" }
                else if ["propose", "vote", "accept"].contains(operation), method == "POST" { path = "projects/\(operation)" }
                else if operation == "tasks", method == "GET" || method == "POST" { path = method == "GET" ? "tasks/list" : "tasks/create" }
                else if (operation == "members" && method == "GET") || (operation == "info" && method == "PUT") || (["leave", "kick", "promote", "demote"].contains(operation) && method == "POST") { path = "groups/\(operation)" }
                else { throw SupabaseHTTPError(status: 501) }
                body["groupId"] = route[1].lowercased()
                if let target = input["targetMyaowId"] { body["target"] = target }
            } else if route.count == 3, route[0] == "tasks", ["complete", "plan"].contains(route[2]), method == "PUT" {
                path = route[2] == "plan" ? "tasks/plan" : "tasks/update"; body["id"] = route[1]
            } else if route.count == 2, route[0] == "tasks", method == "DELETE" {
                path = "tasks/delete"; body["id"] = route[1]
            } else if route.count == 2, route[0] == "scheduled-v2", method == "DELETE" {
                path = "schedules/cancel"; body["id"] = route[1]
            } else { throw SupabaseHTTPError(status: 501) }
        }
        self.body = body
    }
}
