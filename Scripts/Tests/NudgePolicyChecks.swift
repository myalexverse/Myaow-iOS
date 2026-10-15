import Foundation
@main struct NudgePolicyChecks {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = now.addingTimeInterval(-60)
        precondition(MyaowNudgePolicy.shouldPresent(sentAt: now, now: now, lastPresentedAt: old))
        precondition(!MyaowNudgePolicy.shouldPresent(sentAt: old, now: now, lastPresentedAt: old))
        precondition(!MyaowNudgePolicy.shouldPresent(sentAt: now.addingTimeInterval(-8), now: now, lastPresentedAt: old))
        precondition(!MyaowNudgePolicy.shouldPresent(sentAt: now, now: now, lastPresentedAt: now.addingTimeInterval(-1)))
        precondition(MyaowNudgePolicy.shouldPresent(sentAt: now, now: now, lastPresentedAt: now.addingTimeInterval(-5)))
        precondition(!MyaowNudgePolicy.shouldPresent(sentAt: now.addingTimeInterval(100), now: now, lastPresentedAt: old))
        print("Nudge policy: live arrivals, old history, burst suppression and clock boundaries passed.")
    }
}
