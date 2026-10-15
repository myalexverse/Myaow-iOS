import Foundation

/// HTTP reconciliation survives missed socket events; it is not background push delivery.
enum SupabaseSyncPolicy {
    static func interval(conversationVisible: Bool, hasBacklog: Bool, realtime: Bool = false) -> TimeInterval {
        if realtime && !hasBacklog { return 60 }
        return conversationVisible || hasBacklog ? 3 : 15
    }
    static func keepsConnection(applicationActive: Bool, callActive: Bool) -> Bool {
        applicationActive || callActive
    }

    /// A call must not inherit a chat's idle delay. Server backoff still wins.
    static func nextSync(current: Date, now: Date, failures: Int, wakePending: Bool,
                         negotiatingCall: Bool) -> Date {
        guard failures == 0 else { return current }
        if wakePending { return min(current, now) }
        if negotiatingCall { return min(current, now.addingTimeInterval(1)) }
        return current
    }

    static func retryDelay(failures: Int, rateLimited: Bool) -> TimeInterval {
        rateLimited ? 60 : min(60, 5 * pow(2, Double(min(max(failures - 1, 0), 4))))
    }
}
