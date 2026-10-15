import Foundation

@main struct SupabaseSyncChecks {
 static func main() {
  precondition(SupabaseSyncPolicy.interval(conversationVisible: true, hasBacklog: false, realtime: true) == 60)
  precondition(SupabaseSyncPolicy.interval(conversationVisible: true, hasBacklog: false, realtime: false) == 3)
  precondition(SupabaseSyncPolicy.interval(conversationVisible: false, hasBacklog: true, realtime: true) == 3)
  precondition(SupabaseSyncPolicy.interval(conversationVisible: false, hasBacklog: false) == 15)
  precondition(SupabaseSyncPolicy.retryDelay(failures: 1, rateLimited: true) == 60)
  precondition(SupabaseSyncPolicy.retryDelay(failures: 30, rateLimited: false) == 60)
  let now = Date(timeIntervalSince1970: 1_900_000_000)
  let idleDeadline = now.addingTimeInterval(60)
  precondition(SupabaseSyncPolicy.keepsConnection(applicationActive: false, callActive: true), "Locking a phone during a call must preserve signaling")
  precondition(!SupabaseSyncPolicy.keepsConnection(applicationActive: false, callActive: false), "An idle background app must not poll")
  precondition(SupabaseSyncPolicy.keepsConnection(applicationActive: true, callActive: false))
  precondition(SupabaseSyncPolicy.nextSync(current: idleDeadline, now: now, failures: 0, wakePending: false, negotiatingCall: true) == now.addingTimeInterval(1), "Call setup cannot inherit a 60-second chat delay")
  precondition(SupabaseSyncPolicy.nextSync(current: idleDeadline, now: now, failures: 0, wakePending: true, negotiatingCall: true) == now, "Realtime call signals must be fetched immediately")
  precondition(SupabaseSyncPolicy.nextSync(current: idleDeadline, now: now, failures: 1, wakePending: true, negotiatingCall: true) == idleDeadline, "A call cannot bypass network or rate-limit backoff")
  precondition(SupabaseSyncPolicy.nextSync(current: idleDeadline, now: now, failures: 0, wakePending: false, negotiatingCall: false) == idleDeadline, "Idle chat traffic must remain unchanged")
  precondition(SupabaseSyncPolicy.nextSync(current: now, now: now, failures: 0, wakePending: false, negotiatingCall: true) == now, "Never postpone an already-due reconciliation")
  print("PASS: call signaling while locked, immediate wakeup, bounded negotiation fallback, preserved backoff; realtime reconciliation, HTTP fallback, backlog draining and bounded failure/rate-limit backoff")
 }
}
