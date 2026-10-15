import Foundation
import CryptoKit

@main struct RadioPrivacyChecks {
    static func main() throws {
        let a = Curve25519.KeyAgreement.PrivateKey(), b = Curve25519.KeyAgreement.PrivateKey(), stranger = Curve25519.KeyAgreement.PrivateKey()
        let ar = a.rawRepresentation, br = b.rawRepresentation, ap = a.publicKey.rawRepresentation, bp = b.publicKey.rawRepresentation
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) { precondition(value(), label); count += 1 }
        let invite = try RadioContactSecurity.invitation(privateKey: ar, contactKey: bp, sender: "A-session", recipient: "B-session")
        check(RadioContactSecurity.verifyInvitation(invite, privateKey: br, contactKey: ap, sender: "A-session", recipient: "B-session"), "Known contact proves possession")
        check(!RadioContactSecurity.verifyInvitation(invite, privateKey: br, contactKey: stranger.publicKey.rawRepresentation, sender: "A-session", recipient: "B-session"), "Unknown key cannot become saved contact")
        check(!RadioContactSecurity.verifyInvitation(invite, privateKey: br, contactKey: ap, sender: "spoofed", recipient: "B-session"), "Bind actual MPC sender")
        check(!RadioContactSecurity.verifyInvitation(invite, privateKey: br, contactKey: ap, sender: "A-session", recipient: "B-restarted"), "Old session proof rejected")
        let secondInvite = try RadioContactSecurity.invitation(privateKey: ar, contactKey: bp, sender: "A-session", recipient: "B-session")
        let one = try JSONDecoder().decode(RadioContactSecurity.Invitation.self, from: invite)
        let two = try JSONDecoder().decode(RadioContactSecurity.Invitation.self, from: secondInvite)
        check(one.nonce != two.nonce, "Each invitation is fresh")
        let forgedNonce = try JSONEncoder().encode(RadioContactSecurity.Invitation(version: 2, fingerprint: one.fingerprint, nonce: two.nonce, proof: one.proof))
        check(!RadioContactSecurity.verifyInvitation(forgedNonce, privateKey: br, contactKey: ap, sender: "A-session", recipient: "B-session"), "Nonce substitution rejected")
        let forged = try RadioContactSecurity.invitation(privateKey: stranger.rawRepresentation, contactKey: bp, sender: "A-session", recipient: "B-session")
        check(!RadioContactSecurity.verifyInvitation(forged, privateKey: br, contactKey: ap, sender: "A-session", recipient: "B-session"), "Copying a display name cannot impersonate A")
        let content = Data("private radio frame".utf8)
        let sealed = try RadioContactSecurity.seal(content, privateKey: ar, contactKey: bp, sender: "A-session", recipient: "B-session")
        check(try! RadioContactSecurity.open(sealed, privateKey: br, contactKey: ap, sender: "A-session", recipient: "B-session") == content, "Authenticated audio round trip")
        check((try? RadioContactSecurity.open(sealed, privateKey: stranger.rawRepresentation, contactKey: ap, sender: "A-session", recipient: "B-session")) == nil, "Stranger cannot decrypt")
        check((try? RadioContactSecurity.open(sealed, privateKey: ar, contactKey: bp, sender: "B-session", recipient: "A-session")) == nil, "Reflection rejected")
        var tampered = sealed; tampered[tampered.count - 1] ^= 1
        check((try? RadioContactSecurity.open(tampered, privateKey: br, contactKey: ap, sender: "A-session", recipient: "B-session")) == nil, "Tampering rejected")
        check((try? RadioContactSecurity.open(sealed, privateKey: br, contactKey: ap, sender: "A-session", recipient: "B-new")) == nil, "Audio from old activation rejected")
        var window = RadioReplayWindow()
        check(!window.accept(0), "Counter zero rejected")
        check(window.accept(10), "First counter")
        check(window.accept(9), "Allow reordered datagram")
        check(!window.accept(9), "Duplicate rejected")
        check(window.accept(300), "Advance window")
        check(!window.accept(10), "Old counter never reopened")
        check(!window.accept(44), "Window boundary rejected")
        check(window.accept(45), "Oldest allowable new counter")
        check(window.accept(UInt64.max), "Counter arithmetic does not overflow")
        check(!window.accept(45), "Stale frame rejected at maximum counter")
        print("PASS: \(count) private Radio cryptographic identity, tamper, session binding and replay checks")
    }
}
