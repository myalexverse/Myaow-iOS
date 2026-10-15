import Foundation

enum RegistrationInput {
    static func suggestedUsername(_ name: String) -> String {
        let folded = name.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX")).lowercased()
        return String(folded.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(30))
    }

    static func normalizedUsername(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isValidUsername(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9_]{3,30}$", options: .regularExpression) != nil
    }
}

/// One origin for HTTP and WebSocket, including secure and explicit /ws addresses.
struct RelayEndpoint {
    let httpURL: URL
    let webSocketURL: URL
    let supabaseAPIURL: URL?

    init?(_ host: String) {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var parts = URLComponents(string: value.contains("://") ? value : "http://\(value)"),
              let hostname = parts.host, !hostname.isEmpty,
              parts.user == nil, parts.password == nil,
              ["http", "https", "ws", "wss"].contains(parts.scheme ?? "") else { return nil }
        let secure = parts.scheme == "https" || parts.scheme == "wss"
        #if !DEBUG
        guard secure else { return nil }
        #endif
        let isSupabase = hostname.hasSuffix(".supabase.co") && parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "functions/v1/myaow-api"
        if isSupabase && parts.scheme != "https" { return nil }
        parts.scheme = secure ? "https" : "http"
        parts.query = nil
        parts.fragment = nil
        if isSupabase {
            parts.path = "/functions/v1/myaow-api"
            supabaseAPIURL = parts.url
        } else { supabaseAPIURL = nil }
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        guard let http = parts.url else { return nil }
        parts.scheme = secure ? "wss" : "ws"
        parts.path = "/ws"
        guard let socket = parts.url else { return nil }
        httpURL = supabaseAPIURL ?? http
        webSocketURL = socket
    }
}
