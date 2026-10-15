import Foundation
import CryptoKit

/// Companion account for manual simulator journeys. Never exports credentials.
private struct JourneyPeer: Decodable { let id: String; let username: String; let privateHex: String }
@main struct SupabaseJourneyPeer {
 static func main() async throws {
  setbuf(stdout, nil)
  let args = CommandLine.arguments
  let peers = try JSONDecoder().decode([JourneyPeer].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
  let peer = peers[Int(args[2])!]
  precondition(peer.id.hasPrefix("MYAOW-TEST-"))
  let base = URL(string: "https://your-project-ref.supabase.co/functions/v1/myaow-api")!
  let token = try await SupabaseClient.authenticate(base: base, id: peer.id, privateKeyHex: peer.privateHex)
  do {
   let path = args[3]
   precondition(["push/device", "groups/create", "groups/invite", "groups/accept", "groups/list", "groups/members", "tasks/list", "tasks/update", "receive", "send"].contains(path))
   let input = try JSONSerialization.jsonObject(with: Data(args[4].utf8)) as! [String:Any]
   if path == "receive" {
    let data = try await SupabaseClient.request(base: base, path: "messages/pending", token: token)
    let rows = (try JSONSerialization.jsonObject(with: data) as! [String:Any])["messages"] as! [[String:Any]]
    for row in rows {
     let sender = row["sender"] as! String, mid = row["id"] as! String
     let profile = try await SupabaseClient.request(base: base, path: "directory/lookup", body: ["username":sender], token: token)
     let key = (try JSONSerialization.jsonObject(with: profile) as! [String:Any])["identityKeyHex"] as! String
     let envelope = try JSONDecoder().decode(SecureMessageEnvelope.self, from: JSONSerialization.data(withJSONObject: row["envelope"]!))
     let content = try envelope.open(messageId: mid, senderId: sender, recipientId: peer.id, recipientPrivateKey: SecureHex.decode(peer.privateHex,bytes:32), trustedSenderPublicKey: SecureHex.decode(key,bytes:32))
     print("RECEIVED:", content.text, "GROUP:", content.groupId ?? "direct")
     _ = try await SupabaseClient.request(base: base, path: "messages/acknowledge", body: ["senderId":sender,"id":mid],token:token)
    }
    print("Verified and acknowledged \(rows.count) messages")
   } else if path == "send" {
    let recipient = input["recipient"] as! String
    let profile = try await SupabaseClient.request(base:base,path:"directory/lookup",body:["username":recipient],token:token)
    let key = (try JSONSerialization.jsonObject(with:profile) as! [String:Any])["identityKeyHex"] as! String
    var content = SecureMessageContent(text: input["text"] as! String,messageType:"text")
    content.groupId = input["groupId"] as? String
    let envelope = try SecureMessageEnvelope.seal(content,messageId:UUID().uuidString,senderId:peer.id,recipientId:recipient,senderPrivateKey:SecureHex.decode(peer.privateHex,bytes:32),recipientPublicKey:SecureHex.decode(key,bytes:32))
    _ = try await SupabaseClient.request(base:base,path:"messages/send",body:["envelope":try JSONSerialization.jsonObject(with:JSONEncoder().encode(envelope))],token:token)
    print("Encrypted test message accepted")
   } else {
    let result = try await SupabaseClient.request(base:base,path:path,body:input,token:token)
    print(String(decoding:result,as:UTF8.self))
   }
  } catch {
   _ = try? await SupabaseClient.request(base:base,path:"logout",token:token)
   throw error
  }
  _ = try await SupabaseClient.request(base:base,path:"logout",token:token)
 }
}
