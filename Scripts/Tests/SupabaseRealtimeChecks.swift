import Foundation
import CryptoKit
private struct Peer: Codable { let id: String; let username: String; let privateHex: String }
private actor Observer {
 var ready = false; var wakes = 0
 var rejected = false
 func denied() { rejected = true }
 func wasRejected() -> Bool { rejected }
 func joined() { ready = true }
 func woke() { wakes += 1 }
 func state() -> (Bool,Int) { (ready,wakes) }
}
@main struct SupabaseRealtimeChecks {
 static func main() async throws {
  setbuf(stdout, nil)
  let peers = try JSONDecoder().decode([Peer].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
  let base = URL(string:"https://your-project-ref.supabase.co/functions/v1/myaow-api")!
  let a = try await SupabaseClient.authenticate(base:base,id:peers[0].id,privateKeyHex:peers[0].privateHex)
  let b = try await SupabaseClient.authenticate(base:base,id:peers[1].id,privateKeyHex:peers[1].privateHex)
  let observer = Observer()
  let stream = Task {
   do { try await SupabaseWakeupStream.run(base:base,token:b,onReady:{ await observer.joined() },onWake:{ await observer.woke() }) }
   catch { if !Task.isCancelled { print("STREAM ERROR: \(error.localizedDescription)") } }
  }
  for _ in 0..<20 { if await observer.state().0 { break }; try await Task.sleep(for:.seconds(1)) }
  guard await observer.state().0 else { stream.cancel(); throw URLError(.timedOut) }
  print("PASS: private channel joined with Myaow session")
  let mid = UUID().uuidString
  let recipientKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation:SecureHex.decode(peers[1].privateHex,bytes:32)).publicKey.rawRepresentation
  let envelope = try SecureMessageEnvelope.seal(.init(text:"Realtime test",messageType:"text"),messageId:mid,senderId:peers[0].id,recipientId:peers[1].id,senderPrivateKey:SecureHex.decode(peers[0].privateHex,bytes:32),recipientPublicKey:recipientKey)
  let encoded = try JSONSerialization.jsonObject(with:JSONEncoder().encode(envelope))
  let started = Date()
  _ = try await SupabaseClient.request(base:base,path:"messages/send",body:["envelope":encoded],token:a)
  for _ in 0..<15 { if await observer.state().1 > 0 { break }; try await Task.sleep(for:.seconds(1)) }
  let finalState = await observer.state(); precondition(finalState.1 > 0)
  print("PASS: database wake received without polling in \(Int(Date().timeIntervalSince(started)*1000)) ms including send request")
  let wrong = Observer()
  let alien = Task {
   do { try await SupabaseWakeupStream.run(base:base,token:a,overrideTopic:SupabaseWakeupStream.topic(token:b),onReady:{ await wrong.joined() },onWake:{ await wrong.woke() }) }
   catch let error as SupabaseHTTPError where error.status == 403 { await wrong.denied() }
   catch { if !Task.isCancelled { print("Unexpected rejection error:", error.localizedDescription) } }
  }
  try await Task.sleep(for:.seconds(5)); alien.cancel(); await alien.value
  let wrongState = await wrong.state(); precondition(!wrongState.0 && wrongState.1 == 0)
  let explicitlyDenied = await wrong.wasRejected(); precondition(explicitlyDenied)
  print("PASS: another session's channel explicitly rejected (403)")
  _ = try await SupabaseClient.request(base:base,path:"logout",token:b)
  let beforeRevocation = await observer.state().1
  let nextID = UUID().uuidString
  let nextEnvelope = try SecureMessageEnvelope.seal(.init(text:"Revoked session must not receive this wake",messageType:"text"),messageId:nextID,senderId:peers[0].id,recipientId:peers[1].id,senderPrivateKey:SecureHex.decode(peers[0].privateHex,bytes:32),recipientPublicKey:recipientKey)
  _ = try await SupabaseClient.request(base:base,path:"messages/send",body:["envelope":try JSONSerialization.jsonObject(with:JSONEncoder().encode(nextEnvelope))],token:a)
  try await Task.sleep(for:.seconds(4))
  let afterRevocation = await observer.state().1; precondition(beforeRevocation == afterRevocation)
  print("PASS: an already-connected but revoked session receives no new wake")
  stream.cancel(); await stream.value
  _ = try await SupabaseClient.request(base:base,path:"logout",token:a)
 }
}
