import Foundation

@main struct RadioTurnChecks {
    static func main() {
        var caller = RadioTurnState(isAuthority: true), receiver = RadioTurnState(isAuthority: false)
        assert(!caller.transmitting && !receiver.transmitting)
        // Receiver waits for a grant; releasing before its arrival cannot reopen the microphone.
        let request = receiver.request(now: 0)[0]
        assert(!receiver.transmitting)
        let grant = caller.receive(request, now: 0)[0]
        let release = receiver.stop()[0]
        assert(!receiver.transmitting)
        let staleRelease = receiver.receive(grant, now: 1)[0]
        _ = caller.receive(release, now: 1)
        _ = caller.receive(staleRelease, now: 1)
        assert(!caller.receiving && !receiver.transmitting)
        // Simultaneous presses resolve to the authority's existing turn.
        let followerRequest = receiver.request(now: 2)[0]
        let remote = caller.request(now: 2)[0]
        let busy = caller.receive(followerRequest, now: 2)[0]
        let cancelled = receiver.receive(remote, now: 2)
        _ = receiver.receive(busy, now: 2)
        for message in cancelled { _ = caller.receive(message, now: 2) }
        assert(caller.transmitting && receiver.receiving && !receiver.transmitting)
        assert(receiver.request(now: 3).isEmpty)
        for message in caller.stop() { _ = receiver.receive(message, now: 3) }
        assert(!receiver.receiving)
        // A valid receiver turn is granted, then both sides close on the 60-second lease.
        let next = receiver.request(now: 4)[0]
        for message in caller.receive(next, now: 4) { _ = receiver.receive(message, now: 4) }
        assert(receiver.transmitting && caller.receiving && !caller.transmitting)
        _ = caller.receive(release, now: 5) // previous UUID must not revoke this turn
        assert(caller.receiving)
        assert(caller.expire(now: 63).isEmpty)
        for message in caller.expire(now: 64) { _ = receiver.receive(message, now: 64) }
        assert(!caller.receiving && !receiver.transmitting)
        // Lost grant / closed transport stays muted; pending request times out.
        _ = receiver.request(now: 70)
        assert(!receiver.expire(now: 75).isEmpty)
        assert(!receiver.transmitting && receiver.requestID == nil)
        _ = receiver.receive("grant|not-a-uuid", now: 76)
        assert(!receiver.transmitting)
        caller.reset(); receiver.reset()
        print("PASS: muted by default, grant consent, release before grant, simultaneous presses, stale release, lease limit, request timeout and malformed control")
    }
}
