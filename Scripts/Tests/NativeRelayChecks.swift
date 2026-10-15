import Foundation
import CryptoKit

private final class TestPeer {
    let id: String
    let key = Curve25519.KeyAgreement.PrivateKey()
    let origin: URL
    var socket: URLSessionWebSocketTask!
    var token = ""
    init(_ id: String, origin: URL) { self.id = id; self.origin = origin }
    func register(_ username: String) async throws {
        var request = URLRequest(url: origin.appendingPathComponent("api/v1/directory/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["myaowId": id, "username": username,
            "displayName": username, "identityKeyHex": SecureHex.encode(key.publicKey.rawRepresentation),
            "signedPrekeyHex": SecureHex.encode(key.publicKey.rawRepresentation), "oneTimePrekeys": []])
        let (_, response) = try await URLSession.shared.data(for: request)
        precondition((response as? HTTPURLResponse)?.statusCode == 200)
    }
    func send(_ packet: [String: Any]) async throws {
        try await socket.send(.string(String(decoding: JSONSerialization.data(withJSONObject: packet), as: UTF8.self)))
    }
    func next(_ type: String) async throws -> [String: Any] {
        for _ in 0..<100 {
            let message = try await socket.receive()
            let bytes: Data
            switch message {
            case .data(let value): bytes = value
            case .string(let value): bytes = Data(value.utf8)
            @unknown default: continue
            }
            let packet = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            if packet["type"] as? String == type { return packet }
            if packet["type"] as? String == "message_error" { fatalError("Relay rejected test packet") }
        }
        fatalError("Expected packet not received")
    }
    func connect() async throws {
        var url = URLComponents(url: origin, resolvingAgainstBaseURL: false)!
        url.scheme = "ws"; url.path = "/ws"
        socket = URLSession.shared.webSocketTask(with: url.url!)
        socket.resume()
        try await send(["type": "auth", "myaowId": id])
        let challenge = try await next("auth_challenge")
        let proof = try RelayAuthentication.proof(myaowId: id, privateKeyHex: SecureHex.encode(key.rawRepresentation),
            nonce: challenge["nonce"] as! String, serverPublicKeyHex: challenge["serverPublicKeyHex"] as! String)
        try await send(["type": "auth_response", "myaowId": id, "proof": proof])
        token = try await next("auth_ack")["sessionId"] as! String
    }
    func request(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: origin.appendingPathComponent("api/v1/" + path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        precondition((response as? HTTPURLResponse)?.statusCode == 200, String(decoding: data, as: UTF8.self))
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    func packet(_ content: SecureMessageContent, to peer: TestPeer) throws -> [String: Any] {
        let messageId = UUID().uuidString
        let envelope = try SecureMessageEnvelope.seal(content, messageId: messageId, senderId: id, recipientId: peer.id,
            senderPrivateKey: key.rawRepresentation, recipientPublicKey: peer.key.publicKey.rawRepresentation)
        return ["type": "message", "id": messageId, "recipientMyaowId": peer.id,
            "encryptedPayload": String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self)]
    }
    func open(_ packet: [String: Any], from peer: TestPeer) throws -> SecureMessageContent {
        let envelope = try JSONDecoder().decode(SecureMessageEnvelope.self, from: Data((packet["encryptedPayload"] as! String).utf8))
        return try envelope.open(messageId: packet["id"] as! String, senderId: peer.id, recipientId: id,
            recipientPrivateKey: key.rawRepresentation, trustedSenderPublicKey: peer.key.publicKey.rawRepresentation)
    }
}

@main
struct NativeRelayChecks {
    static func main() async throws {
        let origin = URL(string: CommandLine.arguments[1])!
        precondition(origin.host == "127.0.0.1", "Test must use an isolated local relay")
        if CommandLine.arguments.contains("--ui-peer") {
            let index = CommandLine.arguments.firstIndex(of: "--ui-peer")!
            let peerId = CommandLine.arguments.count > index + 1 ? CommandLine.arguments[index + 1] : "MYAOW-DEMO02"
            let peer = TestPeer(peerId, origin: origin)
            try await peer.register("ui_peer_" + peerId.lowercased().suffix(6))
            try await peer.connect()
            print("READY: isolated fictional peer")
            while true {
                let incoming = try await peer.next("message")
                let sender = incoming["senderMyaowId"] as! String
                var lookup = URLComponents(url: origin.appendingPathComponent("api/v1/directory/lookup"), resolvingAgainstBaseURL: false)!
                lookup.queryItems = [.init(name: "username", value: sender)]
                var lookupRequest = URLRequest(url: lookup.url!)
                lookupRequest.setValue("Bearer \(peer.token)", forHTTPHeaderField: "Authorization")
                let (data, _) = try await URLSession.shared.data(for: lookupRequest)
                let record = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                let envelope = try JSONDecoder().decode(SecureMessageEnvelope.self, from: Data((incoming["encryptedPayload"] as! String).utf8))
                let content = try envelope.open(messageId: incoming["id"] as! String, senderId: sender, recipientId: peer.id,
                    recipientPrivateKey: peer.key.rawRepresentation,
                    trustedSenderPublicKey: SecureHex.decode(record["identityKeyHex"] as! String, bytes: 32))
                try await peer.send(["type": "message_received", "messageId": envelope.messageId, "originalSenderId": sender])
                print("VERIFIED: \(content.messageType), \(content.text.utf8.count) bytes")
                guard content.messageType != "control-v2" else { continue }
                let id = UUID().uuidString
                let response = try SecureMessageEnvelope.seal(.init(text: "Recibido: mensaje cifrado de prueba 🐾", messageType: "text"),
                    messageId: id, senderId: peer.id, recipientId: sender, senderPrivateKey: peer.key.rawRepresentation,
                    recipientPublicKey: SecureHex.decode(record["identityKeyHex"] as! String, bytes: 32))
                try await peer.send(["type": "message", "id": id, "recipientMyaowId": sender,
                    "encryptedPayload": String(decoding: try JSONEncoder().encode(response), as: UTF8.self)])
            }
        }
        let alice = TestPeer("MYAOW-NATIVE01", origin: origin)
        let bob = TestPeer("MYAOW-NATIVE02", origin: origin)
        try await alice.register("native_alice"); try await bob.register("native_bob")
        try await alice.connect()
        defer { alice.socket?.cancel(with: .normalClosure, reason: nil); bob.socket?.cancel(with: .normalClosure, reason: nil) }
        let content = SecureMessageContent(text: "Hola 🐈 — mensaje nativo sin Internet del receptor", messageType: "text")
        let packet = try alice.packet(content, to: bob)
        try await alice.send(packet)
        let acceptance = try await alice.next("delivery_ack")
        precondition(acceptance["status"] as? String == "queued_on_server")
        try await bob.connect()
        let first = try await bob.next("message")
        let decoded = try bob.open(first, from: alice)
        precondition(decoded == content)
        bob.socket.cancel(with: .normalClosure, reason: nil)
        try await bob.connect() // Simulates a process dying before local persistence/receipt.
        let retried = try await bob.next("message")
        precondition(retried["id"] as? String == packet["id"] as? String)
        try await bob.send(["type": "message_received", "messageId": retried["id"]!, "originalSenderId": alice.id])
        let delivered = try await alice.next("delivery_ack")
        precondition(delivered["status"] as? String == "delivered")

        let attachment = try EncryptedAttachment.seal(Data("audio/video bytes de prueba".utf8))
        var upload = URLRequest(url: origin.appendingPathComponent("api/v1/media/upload"))
        upload.httpMethod = "POST"; upload.httpBody = attachment.ciphertext
        upload.setValue("Bearer \(alice.token)", forHTTPHeaderField: "Authorization")
        upload.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        upload.setValue("attachment.bin", forHTTPHeaderField: "X-Filename")
        let (uploadData, uploadResponse) = try await URLSession.shared.data(for: upload)
        precondition((uploadResponse as? HTTPURLResponse)?.statusCode == 200)
        let result = try JSONSerialization.jsonObject(with: uploadData) as! [String: Any]
        let remoteURL = URL(string: result["mediaUrl"] as! String, relativeTo: origin)!.absoluteURL
        let mediaContent = SecureMessageContent(text: "Adjunto", messageType: "voice", mediaUrl: remoteURL.absoluteString + "#" + attachment.keyFragment)
        try await alice.send(alice.packet(mediaContent, to: bob))
        let mediaWire = try await bob.next("message")
        let media = try bob.open(mediaWire, from: alice)
        var parts = URLComponents(string: media.mediaUrl!)!
        let fragment = parts.fragment!; parts.fragment = nil
        let (download, _) = try await URLSession.shared.data(from: parts.url!)
        precondition(download == attachment.ciphertext)
        let clear = try EncryptedAttachment.open(download, keyFragment: fragment)
        precondition(clear == Data("audio/video bytes de prueba".utf8))

        for action in [SecureMessageMutation.Action.edit, .delete] {
            let mutation = SecureMessageMutation(action: action, targetId: packet["id"] as! String, text: action == .edit ? "Texto corregido" : "", date: Date())
            try mutation.validate()
            let control = SecureMessageContent(text: String(decoding: try JSONEncoder().encode(mutation), as: UTF8.self), messageType: "control-v2")
            try await alice.send(alice.packet(control, to: bob))
            let received = try await bob.next("message")
            let opened = try bob.open(received, from: alice)
            precondition(opened == control)
        }
        let reply = SecureMessageContent(text: "Recibido", messageType: "text")
        try await bob.send(bob.packet(reply, to: alice))
        let reverse = try await alice.next("message")
        let opened = try alice.open(reverse, from: bob)
        precondition(opened == reply)
        let group = try await alice.request("groups/create", body: ["name": "Grupo cifrado de prueba"])["groupId"] as! String
        let invitation = try await alice.request("groups/invite/create", body: ["groupId": group, "target": bob.id])["token"] as! String
        _ = try await bob.request("groups/invite/accept", body: ["token": invitation])
        let groupContent = SecureMessageContent(text: "Mensaje de grupo privado", messageType: "text", groupId: group)
        _ = try await alice.request("messages-v2/batch", body: ["packets": [try alice.packet(groupContent, to: bob)]])
        let groupWire = try await bob.next("message")
        let groupDecoded = try bob.open(groupWire, from: alice)
        precondition(groupDecoded == groupContent)
        let scheduledContent = SecureMessageContent(text: "Programado con cifrado nativo", messageType: "text", groupId: group)
        let schedule = try await alice.request("scheduled-v2", body: ["id": UUID().uuidString,
            "due": Int64(Date().timeIntervalSince1970 * 1000) + 1200,
            "preview": Data(repeating: 3, count: 64).base64EncodedString(), "packets": [try alice.packet(scheduledContent, to: bob)]])
        precondition(schedule["state"] as? String == "pending")
        let scheduledWire = try await bob.next("message")
        let scheduledDecoded = try bob.open(scheduledWire, from: alice)
        precondition(scheduledDecoded == scheduledContent)
        print("PASS: native CryptoKit + real relay: registration, key proof, offline delivery, reconnect replay, durable receipt, encrypted attachment, authenticated edits/deletion, reply, targeted invitation, encrypted group delivery and scheduled group delivery.")
    }
}
