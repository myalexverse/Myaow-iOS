//
//  UserDirectoryService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import CryptoKit

public struct DirectoryUserResult: Codable, Identifiable, Sendable {
    public var id: String { myaowId }
    public let username: String
    public let myaowId: String
    public let displayName: String
    public let identityKeyHex: String?
    public let signedPrekeyHex: String?
    public let oneTimePrekeyHex: String?
    public let isOnline: Bool
}

@MainActor
@Observable
public final class UserDirectoryService {
    public static let shared = UserDirectoryService()
    
    public var serverBaseURL: String {
        RelayEndpoint(OnlineMessagingService.shared.relayHost)?.httpURL.absoluteString ?? ""
    }
    public private(set) var registrationError: String?

    public func usernameAvailability(_ username: String) async throws -> Bool {
        if let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL {
            let data = try await SupabaseClient.request(base: base, path: "directory/check-username", body: ["username": username])
            struct Availability: Decodable { let available: Bool }
            return try JSONDecoder().decode(Availability.self, from: data).available
        }
        guard let base = URL(string: serverBaseURL) else { throw URLError(.badURL) }
        let url = base.appendingPathComponent("api/v1/directory/check-username").appendingPathComponent(username)
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
        struct Availability: Decodable { let available: Bool }
        return try JSONDecoder().decode(Availability.self, from: data).available
    }

    public var isRegistering: Bool = false
    public var isSearching: Bool = false
    private var searchGeneration = UUID()
    public var searchResults: [DirectoryUserResult] = []
    
    public init() {}
    
    /// Registra la identidad del usuario y sus Prekeys X3DH en el directorio público del Relay
    public func registerIdentityOnServer(
        identity: UserIdentity,
        prekeysHex: [String] = [],
        apnsToken: String? = nil,
        betaInvite: String? = nil
    ) async -> Bool {
        guard !isRegistering else { return false }
        isRegistering = true
        registrationError = nil
        defer { isRegistering = false }
        if let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL {
            do {
                _ = try await SupabaseClient.request(base: base, path: "register", body: [
                    "username": identity.customUsername ?? identity.myaowId.lowercased(), "myaowId": identity.myaowId,
                    "displayName": identity.displayName, "identityKeyHex": identity.publicKeyHex,
                    "betaInvite": (betaInvite ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                ])
                return true
            } catch {
                registrationError = (error as? SupabaseHTTPError)?.status == 403 ? "La beta está cerrada o tu invitación ya no es válida. Tu perfil todavía no se ha registrado." : error.localizedDescription
                return false
            }
        }
        guard let url = URL(string: "\(serverBaseURL)/api/v1/directory/register") else {
            registrationError = "La dirección del servidor no es válida."
            return false
        }
        
        let username = identity.customUsername ?? identity.myaowId.lowercased()
        var bodyPayload: [String: Any] = [
            "username": username,
            "myaowId": identity.myaowId,
            "displayName": identity.displayName,
            "identityKeyHex": identity.publicKeyHex,
            "signedPrekeyHex": identity.publicKeyHex,
            "oneTimePrekeys": prekeysHex
        ]
        
        if let apnsToken { bodyPayload["apnsToken"] = apnsToken }
        if let betaInvite, !betaInvite.isEmpty { bodyPayload["betaInvite"] = betaInvite.trimmingCharacters(in: .whitespacesAndNewlines) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: bodyPayload)
        
        do {
            OnlineMessagingService.shared.authenticatedRequest(&request)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, (200...299).contains(httpRes.statusCode) {
                print("✅ [Directorio] Identidad registrada con éxito en el servidor Relay.")
                return true
            }
            let errorBody = try? JSONDecoder().decode(DirectoryError.self, from: data)
            registrationError = errorBody?.error ?? "No pudimos registrar tu perfil. Intenta de nuevo."
        } catch {
            registrationError = "No pudimos conectar con el servidor. Tu registro sigue aquí; revisa tu conexión e intenta de nuevo."
            print("⚠️ [Directorio] Servidor local no disponible o fuera de línea (\(error.localizedDescription)). Continuando en modo local/mesh.")
        }
        return false
    }
    
    private struct DirectoryError: Decodable { let error: String }

    /// Busca a un contacto por su `@username` exacto y descarga su paquete de Prekeys X3DH
    public func lookupUser(byUsername username: String) async -> DirectoryUserResult? {
        if let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL {
            do {
                let own = IdentityManager.shared.currentIdentity.myaowId
                try await OnlineMessagingService.shared.waitUntilAuthenticated()
                let data = try await SupabaseClient.request(base: base, path: "directory/lookup", body: ["username": username.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines)], token: OnlineMessagingService.shared.sessionToken)
                guard own == IdentityManager.shared.currentIdentity.myaowId else { return nil }
                return try JSONDecoder().decode(DirectoryUserResult.self, from: data)
            } catch { return nil }
        }
        let sanitized = username.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard var components = URLComponents(string: "\(serverBaseURL)/api/v1/directory/lookup") else { return nil }
        components.queryItems = [URLQueryItem(name: "username", value: sanitized)]
        guard let url = components.url else { return nil }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            OnlineMessagingService.shared.authenticatedRequest(&request)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                return try JSONDecoder().decode(DirectoryUserResult.self, from: data)
            }
        } catch {
            print("⚠️ [Directorio] Error al consultar usuario: \(error.localizedDescription)")
        }
        return nil
    }
    
    /// Búsqueda de contactos en vivo
    public func searchUsers(query: String) async {
        let generation = UUID()
        searchGeneration = generation
        searchResults = []
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.searchResults = []
            return
        }
        
        self.isSearching = true
        defer { if searchGeneration == generation { self.isSearching = false } }
        if RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL != nil {
            let found = await lookupUser(byUsername: query)
            if searchGeneration == generation { searchResults = found.map { [$0] } ?? [] }
            return
        }
        
        let sanitized = query.replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard var components = URLComponents(string: "\(serverBaseURL)/api/v1/directory/search") else { return }
        components.queryItems = [URLQueryItem(name: "q", value: sanitized)]
        guard let url = components.url else { return }
        
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 12
            OnlineMessagingService.shared.authenticatedRequest(&request)
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpRes = response as? HTTPURLResponse, httpRes.statusCode == 200 {
                struct SearchResponse: Codable {
                    let results: [DirectoryUserResult]
                }
                let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
                if searchGeneration == generation { self.searchResults = decoded.results }
            }
        } catch {
            if searchGeneration == generation { self.searchResults = [] }
        }
    }
}
