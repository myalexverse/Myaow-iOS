import Foundation
import CryptoKit

private struct Fixture: Codable {
 let id: String
 let username: String
 let privateHex: String
 var privateBytes: Data { get throws { try SecureHex.decode(privateHex, bytes: 32) } }
 var publicBytes: Data { get throws { try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateBytes).publicKey.rawRepresentation } }
}
@main struct SupabaseNativeChecks {
 static let base = URL(string: "https://your-project-ref.supabase.co/functions/v1/myaow-api")!
 static func call(_ path: String, _ body: [String:Any] = [:], token: String? = nil, status: Int = 200) async throws -> [String:Any] {
  do {
   let data = try await SupabaseClient.request(base: base, path: path, body: body, token: token)
   precondition(status == 200, "Expected rejection for \(path)")
   return try JSONSerialization.jsonObject(with: data) as! [String:Any]
  } catch let error as SupabaseHTTPError {
   guard error.status == status else { throw error }
   return [:]
  }
 }
 private static func authenticate(_ peer: Fixture) async throws -> String {
  let challenge = try await call("auth/challenge", ["myaowId":peer.id])
  precondition(challenge["proofHash"] == nil)
  let proof = try RelayAuthentication.proof(myaowId: peer.id, privateKeyHex: peer.privateHex,
     nonce:challenge["nonce"] as! String, serverPublicKeyHex:challenge["serverPublicKeyHex"] as! String)
  let body: [String:Any] = ["myaowId":peer.id,"id":challenge["id"]!,"proof":proof]
  let result = try await call("auth/proof",body)
  _ = try await call("auth/proof",body,status:401)
  return result["sessionId"] as! String
 }
 static func main() async throws {
  let file = URL(fileURLWithPath:CommandLine.arguments[2])
  if CommandLine.arguments[1] == "--prepare" {
   precondition(!FileManager.default.fileExists(atPath:file.path))
   let peers = (0..<3).map { _ -> Fixture in
    let suffix=UUID().uuidString.lowercased()
    return Fixture(id:"MYAOW-TEST-"+suffix,username:"mt_"+suffix.replacingOccurrences(of:"-",with:"").prefix(20),
      privateHex:SecureHex.encode(Curve25519.KeyAgreement.PrivateKey().rawRepresentation))
   }
   try JSONEncoder().encode(peers).write(to:file,options:.atomic)
   try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
   let publicRecords = try peers.map { ["id":$0.id,"username":$0.username,"identityKeyHex":SecureHex.encode(try $0.publicBytes)] }
   print(String(decoding:try JSONSerialization.data(withJSONObject:publicRecords),as:UTF8.self))
   return
  }
  let peers=try JSONDecoder().decode([Fixture].self,from:Data(contentsOf:file))
  precondition(peers.count==3 && peers.allSatisfy{$0.id.hasPrefix("MYAOW-TEST-")})
  let a=peers[0],b=peers[1],c=peers[2]
  _ = try await call("messages/pending", status:401)
  let ta=try await authenticate(a)
  let appToken=try await SupabaseClient.authenticate(base:base,id:a.id,privateKeyHex:a.privateHex)
  let me=try await call("profile",token:appToken)
  precondition(me["myaowId"] as? String == a.id)
  _ = try await call("logout",token:appToken)
  let lookup=try await call("directory/lookup",["username":b.id.lowercased()],token:ta)
  precondition(lookup["myaowId"] as? String == b.id)
  let availability=try await call("directory/check-username",["username":a.username])
  precondition(availability["available"] as? Bool == false)
  let id=UUID().uuidString
  let original=SecureMessageContent(text:"Prueba cifrada nativa de Myaow 🐈",messageType:"text")
  let envelope=try SecureMessageEnvelope.seal(original,messageId:id,senderId:a.id,recipientId:b.id,
    senderPrivateKey:a.privateBytes,recipientPublicKey:b.publicBytes)
  let object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(envelope))
  let sent=try await call("messages/send",["envelope":object],token:ta)
  precondition(sent["status"] as? String == "queued_on_server" && sent["id"] as? String == id)
  _ = try await call("messages/send",["envelope":object],token:ta)
  let tc=try await authenticate(c)
  let foreign=try await call("messages/pending",token:tc)
  precondition((foreign["messages"] as! [Any]).isEmpty)
  let fakeAck=try await call("messages/acknowledge",["senderId":a.id,"id":id],token:tc)
  precondition(fakeAck["acknowledged"] as? Bool == false)
  _ = try await call("messages/send",["envelope":object],token:tc,status:400)
  let tb=try await authenticate(b)
  let pending=try await call("messages/pending",token:tb)
  let rows=pending["messages"] as! [[String:Any]]
  precondition(rows.count==1 && rows[0]["id"] as? String==id)
  let received=try JSONDecoder().decode(SecureMessageEnvelope.self,from:JSONSerialization.data(withJSONObject:rows[0]["envelope"]!))
  let opened=try received.open(messageId:id,senderId:a.id,recipientId:b.id,recipientPrivateKey:b.privateBytes,trustedSenderPublicKey:a.publicBytes)
  precondition(opened==original)
  let ack=try await call("messages/acknowledge",["senderId":a.id,"id":id],token:tb)
  precondition(ack["acknowledged"] as? Bool == true)
  let retry=try await call("messages/send",["envelope":object],token:ta)
  precondition(retry["status"] as? String == "delivered")
  let sync=try await call("messages/sync",["ids":[id]],token:ta)
  precondition((sync["receipts"] as! [[String:Any]]).first?["status"] as? String == "delivered")
  let foreignSync=try await call("messages/sync",["ids":[id]],token:tc)
  precondition((foreignSync["receipts"] as! [Any]).isEmpty)
  // Exercise deployed group/task permissions and the actual minute scheduler.
  let gid=UUID().uuidString.lowercased()
  _ = try await call("groups/create",["id":gid,"name":"Native fixture team"],token:ta)
  _ = try await call("groups/members",["groupId":gid],token:tb,status:403)
  for (peer,token) in [(b,tb),(c,tc)] {
   let invitation=try await call("groups/invite",["groupId":gid,"recipientId":peer.id],token:ta)
   if peer.id == b.id {
    _ = try await call("groups/accept",["inviteId":invitation["inviteId"]!],token:tc,status:403)
   }
   _ = try await call("groups/accept",["inviteId":invitation["inviteId"]!],token:token)
  }
  let taskID=UUID().uuidString
  _ = try await call("tasks/create",["id":taskID,"groupId":gid,"title":"Native fixture task","assigneeMyaowId":b.id],token:ta)
  _ = try await call("tasks/update",["id":taskID,"completed":true],token:tc,status:403)
  let task=try await call("tasks/update",["id":taskID,"state":"in_progress","progress":65],token:tb)
  precondition((task["task"] as! [String:Any])["progress"] as? Int == 65)
  var groupContent=SecureMessageContent(text:"Programado con sesión cerrada 🐈",messageType:"text")
  groupContent.groupId=gid
  let packets: [[String:Any]]=try [b,c].map { peer in
   let mid=UUID().uuidString
   let sealed=try SecureMessageEnvelope.seal(groupContent,messageId:mid,senderId:a.id,recipientId:peer.id,senderPrivateKey:a.privateBytes,recipientPublicKey:peer.publicBytes)
   return ["id":mid,"type":"message","senderMyaowId":a.id,"senderDisplayName":"Fixture","recipientMyaowId":peer.id,
    "encryptedPayload":String(decoding:try JSONEncoder().encode(sealed),as:UTF8.self)]
  }
  let scheduleID=UUID().uuidString
  let preview=try AES.GCM.seal(Data("Private preview".utf8),using:SymmetricKey(size:.bits256)).combined!.base64EncodedString()
  let schedule: [String:Any]=["id":scheduleID,"due":floor(Date().addingTimeInterval(5).timeIntervalSince1970*1000),"preview":preview,"packets":packets]
  _ = try await call("schedules/create",schedule,token:ta)
  _ = try await call("schedules/create",schedule,token:ta)
  _ = try await call("schedules/cancel",["id":scheduleID],token:tb,status:409)
  _ = try await call("logout",token:ta)
  _ = try await call("profile",token:ta,status:401)
  var delivered=false
  for _ in 0..<9 {
   try await Task.sleep(nanoseconds:10_000_000_000)
   let result=try await call("messages/pending",token:tb)
   if !(result["messages"] as! [Any]).isEmpty { delivered=true; break }
  }
  precondition(delivered,"Cron did not dispatch within 90 seconds")
  for (peer,token) in [(b,tb),(c,tc)] {
   let result=try await call("messages/pending",token:token)
   let messages=result["messages"] as! [[String:Any]]
   precondition(messages.count==1)
   let row=messages[0], mid=row["id"] as! String
   let sealed=try JSONDecoder().decode(SecureMessageEnvelope.self,from:JSONSerialization.data(withJSONObject:row["envelope"]!))
   let opened=try sealed.open(messageId:mid,senderId:a.id,recipientId:peer.id,recipientPrivateKey:peer.privateBytes,trustedSenderPublicKey:a.publicBytes)
   precondition(opened==groupContent)
   _ = try await call("messages/acknowledge",["senderId":a.id,"id":mid],token:token)
  }
  print("PASS: Swift/CryptoKit → deployed Supabase: identity proof and replay rejection, real HPKE direct/group messages, durable queue, UUID case preservation, deduplication, cross-account isolation, targeted invitations, task progress/permissions, encrypted schedules, autonomous cron dispatch after sender logout, acknowledgement and session revocation.")
 }
}
