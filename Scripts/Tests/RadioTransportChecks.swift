import Foundation
import CryptoKit
import MultipeerConnectivity

/// Two temporary radios in this process. Only invite the generated test peer IDs.
/// Does not open a microphone, contact real peers, or connect to the Internet.
@main struct RadioTransportChecks {
    @MainActor static func wait(_ label: String, until condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NSError(domain: "RadioTransportChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timeout: \(label)"])
    }
    @MainActor static func main() async {
        let first = LocalRadioTransport(); let second = LocalRadioTransport(); let stranger = LocalRadioTransport()
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey(), c = Curve25519.KeyAgreement.PrivateKey()
        let ca = RadioContactCredential(id: "A", name: "Saved A", publicKey: a.publicKey.rawRepresentation)
        let cb = RadioContactCredential(id: "B", name: "Saved B", publicKey: b.publicKey.rawRepresentation)
        first.configure(privateKey: a.rawRepresentation, contacts: [cb])
        second.configure(privateKey: b.rawRepresentation, contacts: [ca])
        stranger.configure(privateKey: c.rawRepresentation, contacts: [ca])
        defer { first.stop(); second.stop(); stranger.stop() }
        first.start(name: "Prueba Radio A"); second.start(name: "Prueba Radio B")
        do {
            stranger.start()
            try await wait("one-way contact discovery") { stranger.nearby.contains { $0.id == first.localPeer.displayName } }
            stranger.connect(contactID: "A")
            try await Task.sleep(for: .seconds(1))
            precondition(first.invitation == nil && first.connected.isEmpty && stranger.connected.isEmpty, "One-sided contact is rejected")
            precondition(!first.nearby.contains { $0.id == stranger.localPeer.displayName }, "Strangers hidden")
            stranger.stop()
            try await wait("local discovery") { first.nearby.contains { $0.id == second.localPeer.displayName } }
            first.invite(first.nearby.first { $0.id == second.localPeer.displayName }!)
            try await wait("explicit invitation") { second.invitation?.id == first.localPeer.displayName }
            precondition(first.connected.isEmpty && second.connected.isEmpty, "No audio link before acceptance")
            second.respond(true)
            try await wait("bilateral connection and channel exchange") {
                first.connected.first?.channel == 1 && second.connected.first?.channel == 1
            }
            var received: [RadioPacket] = []
            second.onPacket = { packet, peer in
                precondition(peer.id == first.localPeer.displayName, "Actual transport sender")
                received.append(packet)
            }
            let id = UUID()
            precondition(first.send(RadioPacket(.start, channel: 1, stream: id)))
            try await wait("reliable start") { received.contains { $0.kind == .start && $0.stream == id } }
            precondition(first.send(RadioPacket(.audio, channel: 1, stream: id, sequence: 1, pcm: Data([1, 2, 3, 4]))))
            try await wait("local PCM packet") { received.contains { $0.kind == .audio && $0.pcm == Data([1, 2, 3, 4]) } }
            second.channel = 2; second.announceChannel()
            try await wait("channel change") { first.connected.first?.channel == 2 }
            precondition(!first.send(RadioPacket(.audio, channel: 1, stream: id, sequence: 2, pcm: Data([1, 2]))), "No recipients on old channel")
            second.configure(privateKey: b.rawRepresentation, contacts: [])
            try await wait("revocation disconnect") { first.connected.isEmpty && !second.isActive }
            precondition(!first.send(RadioPacket(.start, channel: 1)), "Revoked contact cannot receive")
            print("PASS: real local Radio: one-sided contact rejected, strangers hidden, mutual saved keys, explicit consent, encrypted PCM, channel isolation, revocation disconnect")
        } catch {
            print("FAIL: \(error.localizedDescription); A: \(first.error ?? "none"); B: \(second.error ?? "none")")
            first.stop(); second.stop(); exit(1)
        }
    }
}
