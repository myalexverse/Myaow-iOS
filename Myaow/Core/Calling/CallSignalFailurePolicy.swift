import Foundation

enum CallSignalFailurePolicy {
    static func shouldEndCall(signal: String, connected: Bool) -> Bool {
        signal != "call_hangup" && !(connected && signal == "webrtc_ice_candidate")
    }
}
