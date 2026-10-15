import Foundation
@main struct PortalSessionChecks {
    static func main() {
        var a = PortalSession(), b = PortalSession()
        precondition(a.send(.star, now: 0) == nil)
        let invitation = a.invite(now: 0)!
        precondition(a.invite(now: 1) == nil)
        _ = b.receive(invitation, now: 0)
        precondition(!a.connected && !b.connected)
        precondition(b.receive(PortalMessage(kind: .gift, invitation: invitation.invitation, gift: .fish), now: 1).gift == nil)
        let accept = b.answer(accept: true, now: 2)!
        _ = a.receive(accept, now: 2)
        precondition(a.connected && b.connected)
        let gift = a.send(.fish, now: 3)!
        precondition(b.receive(gift, now: 3).gift == .fish)
        precondition(b.receive(gift, now: 4).gift == nil, "Replay must not render twice")
        precondition(a.send(.cat, now: 3.1) == nil, "Rate limit sends")
        precondition(b.receive(PortalMessage(kind: .gift, invitation: UUID(), gift: .cat), now: 5).gift == nil)
        let cancel = a.cancel()!; _ = b.receive(cancel, now: 6)
        precondition(!a.connected && !b.connected)
        precondition(b.receive(gift, now: 7).gift == nil)
        let expired = a.invite(now: 10)!; _ = b.receive(expired, now: 10)
        precondition(b.answer(accept: true, now: 41)?.kind == .decline)
        precondition(a.expire(now: 41)?.kind == .cancel)
        _ = a.receive(PortalMessage(kind: .accept, invitation: expired.invitation), now: 42)
        precondition(!a.connected)
        let simultaneousA = a.invite(now: 50)!, simultaneousB = b.invite(now: 50)!
        precondition(a.receive(simultaneousB, now: 51).reply?.kind == .decline)
        precondition(b.receive(simultaneousA, now: 51).reply?.kind == .decline)
        precondition(PortalMessage.decode(gift.data!)?.gift == .fish)
        precondition(PortalMessage.decode(Data(repeating: 32, count: 513)) == nil)
        precondition(PortalMessage.decode(Data("{}".utf8)) == nil)
        precondition(PortalMessage.decode(PortalMessage(version: 2, kind: .invite, invitation: UUID()).data!) == nil)
        precondition(PortalMessage.decode(PortalMessage(kind: .gift, invitation: UUID()).data!) == nil)
        precondition(PortalMessage.decode(PortalMessage(kind: .accept, invitation: UUID(), gift: .cat).data!) == nil)
        print("PASS: consent, matching invitations, rejection, expiry, simultaneous invitations, replay protection, gift rate limits, invalid and oversized messages.")
    }
}
