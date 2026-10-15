import Foundation

@main
struct RegistrationInputChecks {
    static func main() {
        precondition(RegistrationInput.suggestedUsername("Álex Dovén 🐈") == "alexdoven")
        precondition(RegistrationInput.normalizedUsername("  ALEX_01\n") == "alex_01")
        for invalid in ["ab", "has space", "bad/name", "álex", String(repeating: "a", count: 31)] {
            precondition(!RegistrationInput.isValidUsername(invalid))
        }
        for valid in ["alex", "alex_01", "123", String(repeating: "a", count: 30)] {
            precondition(RegistrationInput.isValidUsername(valid))
        }
        let cases = [
            ("localhost:8080", "http://localhost:8080", "ws://localhost:8080/ws"),
            ("http://localhost:8080/ws", "http://localhost:8080", "ws://localhost:8080/ws"),
            ("wss://relay.example/ws", "https://relay.example", "wss://relay.example/ws"),
            ("https://relay.example", "https://relay.example", "wss://relay.example/ws"),
            (" ws://192.168.1.20:8080/ws ", "http://192.168.1.20:8080", "ws://192.168.1.20:8080/ws")
        ]
        for (input, http, socket) in cases {
            let endpoint = RelayEndpoint(input)
            #if !DEBUG
            if http.hasPrefix("http://") { precondition(endpoint == nil); continue }
            #endif
            precondition(endpoint?.httpURL.absoluteString == http)
            precondition(endpoint?.webSocketURL.absoluteString == socket)
        }
        for invalid in ["", "https://", "ftp://server", "http://user:password@example.com"] {
            precondition(RelayEndpoint(invalid) == nil)
        }
        print("PASS: username normalization, validation and environment-specific transport policy")
    }
}
