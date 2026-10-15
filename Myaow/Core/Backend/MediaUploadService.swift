import Foundation

/// Servicio de subida de media por HTTP al servidor Relay (reemplaza Base64 por WebSocket)
@MainActor
public final class MediaUploadService {
    public static let shared = MediaUploadService()
    private init() {}
    private var uploadsInFlight = Set<String>()
    
    /// Sube un archivo multimedia al servidor y retorna la URL del media
    public func uploadMedia(
        data: Data,
        filename: String = "media.jpg",
        contentType: String = "image/jpeg",
        recipientMyaowId: String? = nil, groupId: String? = nil, messageId: String? = nil
    ) async -> (mediaId: String, mediaUrl: String, groupReaders: [String]?)? {
        guard let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.httpURL else {
            print("❌ [MediaUpload] URL inválida")
            return nil
        }
        
        if let api = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL {
            do {
                let owner = IdentityManager.shared.currentIdentity.myaowId
                let operation = api.absoluteString + owner + (messageId ?? UUID().uuidString)
                guard uploadsInFlight.insert(operation).inserted else { return nil }
                defer { uploadsInFlight.remove(operation) }
                guard !data.isEmpty, data.count <= SupabaseMediaClient.maximumPlaintextBytes else { throw SupabaseHTTPError(status: 413) }
                let prepared = try messageId.map { try PendingMediaUploadStore(base: api, owner: owner).prepare(data: data, messageID: $0, privateKey: SecureHex.decode(IdentityManager.shared.privateKeyHex, bytes: 32)) }
                try await OnlineMessagingService.shared.waitUntilAuthenticated()
                guard owner == IdentityManager.shared.currentIdentity.myaowId, RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL == api else { throw CancellationError() }
                guard let token = OnlineMessagingService.shared.sessionToken else { throw SupabaseHTTPError(status: 401) }
                let result = try await SupabaseMediaClient.upload(base: api, token: token, data: data, recipient: recipientMyaowId, groupID: groupId, prepared: prepared)
                guard owner == IdentityManager.shared.currentIdentity.myaowId, RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL == api else { throw CancellationError() }
                return result
            } catch {
                OnlineMessagingService.shared.messagingError = error.localizedDescription
                return nil
            }
        }
        let url = base.appendingPathComponent("api/v1/media/upload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        guard let sealed = try? EncryptedAttachment.seal(data) else { return nil }
        request.httpBody = sealed.ciphertext
        request.setValue(IdentityManager.shared.currentIdentity.myaowId, forHTTPHeaderField: "X-Myaow-Id")
        request.setValue("application/octet-stream", forHTTPHeaderField: "X-Content-Type")
        request.setValue("attachment.bin", forHTTPHeaderField: "X-Filename")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        do {
            OnlineMessagingService.shared.authenticatedRequest(&request)
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                print("⚠️ [MediaUpload] Error del servidor")
                return nil
            }
            
            if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
               let mediaId = json["mediaId"] as? String,
               let mediaUrl = json["mediaUrl"] as? String {
                let fullUrl: String
                if mediaUrl.hasPrefix("http://") || mediaUrl.hasPrefix("https://") {
                    fullUrl = mediaUrl
                } else {
                    fullUrl = URL(string: mediaUrl, relativeTo: base)?.absoluteURL.absoluteString ?? mediaUrl
                }
                guard var protectedURL = URLComponents(string: fullUrl) else { return nil }
                protectedURL.fragment = sealed.keyFragment
                guard let value = protectedURL.url?.absoluteString else { return nil }
                return (mediaId, value, nil)
            }
            return nil
        } catch {
            print("❌ [MediaUpload] Error: \(error.localizedDescription)")
            return nil
        }
    }
    
    func forgetPendingUpload(messageId: String, owner: String) {
        guard let api = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL else { return }
        try? PendingMediaUploadStore(base: api, owner: owner).remove(messageID: messageId)
    }

    /// Descarga media desde una URL del servidor o CDN R2
    public func downloadMedia(from urlString: String) async -> Data? {
        if let api = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL {
            do {
                guard let url = URL(string: urlString) else { throw URLError(.badURL) }
                _ = try SupabaseMediaClient.objectID(from: url, base: api)
                try await OnlineMessagingService.shared.waitUntilAuthenticated()
                guard let token = OnlineMessagingService.shared.sessionToken else { throw SupabaseHTTPError(status: 401) }
                return try await SupabaseMediaClient.download(base: api, token: token, url: url)
            } catch { return nil }
        }
        let fullUrlString: String
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            fullUrlString = urlString
        } else {
            guard let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.httpURL,
                  let resolved = URL(string: urlString, relativeTo: base)?.absoluteURL else { return nil }
            fullUrlString = resolved.absoluteString
        }
        
        guard var parts = URLComponents(string: fullUrlString),
              ["http", "https"].contains(parts.scheme ?? ""),
              let keyFragment = parts.fragment, keyFragment.hasPrefix(EncryptedAttachment.fragmentPrefix) else { return nil }
        #if !DEBUG
        guard parts.scheme == "https" else { return nil }
        #endif
        parts.fragment = nil // The decryption key must never enter an HTTP request or log.
        guard let url = parts.url else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return try EncryptedAttachment.open(data, keyFragment: keyFragment)
        } catch {
            print("❌ [MediaDownload] Error: \(error.localizedDescription)")
            return nil
        }
    }
}
