import Foundation

@main struct GroupReceiptChecks {
 static func main() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent("myaow-group-receipts-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = GroupReceiptStore(root: root)
  let local = UUID().uuidString, first = UUID().uuidString, second = UUID().uuidString
  try store.register(owner: "fixture-a", localID: local, packetIDs: [first, second])
  try store.apply([first.lowercased()], owner: "fixture-a") { _ in preconditionFailure("Partial delivery was marked complete") }
  let restarted = GroupReceiptStore(root: root)
  let other = try restarted.entries(owner: "fixture-b"); precondition(other.isEmpty)
  try restarted.register(owner: "fixture-a", localID: local, packetIDs: [first, second])
  let partial = try restarted.entries(owner: "fixture-a"); precondition(partial.count == 1 && partial[0].delivered == [first])
  try restarted.apply([second], owner: "fixture-a") { _ in false }
  let retained = try restarted.entries(owner: "fixture-a"); precondition(retained.count == 1 && retained[0].delivered.count == 2)
  var confirmed = false
  try restarted.apply([], owner: "fixture-a") { id in precondition(id == local); confirmed = true; return true }
  let final = try restarted.entries(owner: "fixture-a"); precondition(final.isEmpty && confirmed)
  print("PASS: group delivery waits for all recipients, survives restart, retains partial progress, isolates accounts and waits for durable local confirmation")
 }
}
