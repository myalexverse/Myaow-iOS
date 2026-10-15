import Foundation

@main struct CallSignalFailureChecks {
    static func main() {
        precondition(!CallSignalFailurePolicy.shouldEndCall(signal: "webrtc_ice_candidate", connected: true))
        precondition(CallSignalFailurePolicy.shouldEndCall(signal: "webrtc_ice_candidate", connected: false))
        for type in ["call_offer", "call_answer", "webrtc_offer", "webrtc_answer"] {
            precondition(CallSignalFailurePolicy.shouldEndCall(signal: type, connected: false))
        }
        precondition(!CallSignalFailurePolicy.shouldEndCall(signal: "call_hangup", connected: false))
        print("PASS: a late ICE send failure preserves connected media; negotiation failures remain visible.")
    }
}
