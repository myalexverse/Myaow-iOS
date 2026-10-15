import Foundation
import CryptoKit
private struct Peer: Codable { let id: String; let username: String; let privateHex: String }
@main struct SupabaseMediaChecks {
 static let base = URL(string: "https://your-project-ref.supabase.co/functions/v1/myaow-api")!
 static func main() async throws {
  let file=URL(fileURLWithPath:CommandLine.arguments[2])
  if CommandLine.arguments[1] == "--prepare" {
   let peers=(0..<3).map { _ in Peer(id:"MYAOW-TEST-"+UUID().uuidString,username:"media_"+UUID().uuidString.replacingOccurrences(of:"-",with:"").prefix(16).lowercased(),privateHex:SecureHex.encode(Curve25519.KeyAgreement.PrivateKey().rawRepresentation)) }
   guard !FileManager.default.fileExists(atPath:file.path) else { throw URLError(.cannotCreateFile) }
   try JSONEncoder().encode(peers).write(to:file,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
   let records=try peers.map { p in ["id":p.id,"username":p.username,"key":SecureHex.encode(try Curve25519.KeyAgreement.PrivateKey(rawRepresentation:SecureHex.decode(p.privateHex,bytes:32)).publicKey.rawRepresentation)] }
   print(String(decoding:try JSONSerialization.data(withJSONObject:records),as:UTF8.self));return
  }
  let peers=try JSONDecoder().decode([Peer].self,from:Data(contentsOf:file));var tokens=[String]()
  for p in peers { tokens.append(try await SupabaseClient.authenticate(base:base,id:p.id,privateKeyHex:p.privateHex)) }
  if ["--chat", "--ping", "--listen"].contains(CommandLine.arguments[1]) {
   let lookup = try await SupabaseClient.request(base:base,path:"directory/lookup",body:["username":CommandLine.arguments[3]],token:tokens[0])
   let contact = try JSONSerialization.jsonObject(with:lookup) as! [String:Any]
   let recipient=contact["myaowId"] as! String
   let recipientKey=try SecureHex.decode(contact["identityKeyHex"] as! String,bytes:32)
   let files:[(String,String,String?)]=[("text","Hola desde Supabase. Prueba real de mensajería.",nil),
     ("image","Foto de prueba cifrada","Myaow/Assets.xcassets/MyaowLogo.imageset/myaow_logo.png"),
     ("voice","Audio de prueba (0:01)","/private/tmp/myaow-test-tone.wav"),
     ("rawFile","Prueba-Myaow.txt","/private/tmp/myaow-test-document.txt")]
   for (kind,text,path) in (CommandLine.arguments[1] == "--listen" ? [] : CommandLine.arguments[1] == "--ping" ? Array(files.prefix(1)) : files) {
    var content=SecureMessageContent(text:text,messageType:kind)
    if let path {
     let upload=try await SupabaseMediaClient.upload(base:base,token:tokens[0],data:Data(contentsOf:URL(fileURLWithPath:path)),recipient:recipient)
     content.mediaUrl=upload.mediaUrl
    }
    let mid=UUID().uuidString
    let envelope=try SecureMessageEnvelope.seal(content,messageId:mid,senderId:peers[0].id,recipientId:recipient,senderPrivateKey:SecureHex.decode(peers[0].privateHex,bytes:32),recipientPublicKey:recipientKey)
    let object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(envelope))
    _ = try await SupabaseClient.request(base:base,path:"messages/send",body:["envelope":object],token:tokens[0])
    print("SENT \(kind) encrypted fixture")
   }
   for _ in 0..<(CommandLine.arguments[1] == "--ping" ? 2 : CommandLine.arguments[1] == "--listen" ? 120 : 24) {
    try await Task.sleep(for:.seconds(5))
    let data=try await SupabaseClient.request(base:base,path:"messages/pending",token:tokens[0])
    let rows=(try JSONSerialization.jsonObject(with:data) as! [String:Any])["messages"] as! [[String:Any]]
    for row in rows {
     let envelope=try JSONDecoder().decode(SecureMessageEnvelope.self,from:JSONSerialization.data(withJSONObject:row["envelope"]!))
     let content=try envelope.open(messageId:row["id"] as! String,senderId:recipient,recipientId:peers[0].id,recipientPrivateKey:SecureHex.decode(peers[0].privateHex,bytes:32),trustedSenderPublicKey:recipientKey)
     if let url=content.mediaUrl {
      let received = try await SupabaseMediaClient.download(base:base,token:tokens[0],url:URL(string:url)!)
      precondition(!received.isEmpty)
      print("DECRYPTED attachment bytes=\(received.count), message=\(envelope.messageId)")
     }
     _ = try await SupabaseClient.request(base:base,path:"messages/acknowledge",body:["id":row["id"]!,"senderId":recipient],token:tokens[0])
     print("RECEIVED from simulator: \(content.messageType)")
    }
   }
   for token in tokens { _ = try await SupabaseClient.request(base:base,path:"logout",token:token) }
   return
  }
  let samples:[Data]=[
   Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9y0AAAAASUVORK5CYII=")!,
   Data("RIFFtestWAVEfmt audio fixture".utf8), Data("%PDF-1.4\nMyaow encrypted document fixture\n%%EOF".utf8)]
  for (i,bytes) in samples.enumerated() {
   let prepared=try SupabaseMediaClient.Prepared.create(bytes)
   let uploaded=try await SupabaseMediaClient.upload(base:base,token:tokens[0],data:bytes,recipient:peers[1].id,prepared:prepared)
   let retried=try await SupabaseMediaClient.upload(base:base,token:tokens[0],data:bytes,recipient:peers[1].id,prepared:prepared)
   precondition(uploaded.mediaId==retried.mediaId && uploaded.mediaUrl==retried.mediaUrl)
   let url=URL(string:uploaded.mediaUrl)!
   let decrypted=try await SupabaseMediaClient.download(base:base,token:tokens[1],url:url)
   precondition(decrypted==bytes)
   do { _ = try await SupabaseMediaClient.download(base:base,token:tokens[2],url:url);fatalError("Foreign download") } catch let e as SupabaseHTTPError { precondition(e.status==403) }
   _ = try await SupabaseClient.request(base:base,path:"contacts/block",body:["target":peers[0].id],token:tokens[1])
   do { _ = try await SupabaseMediaClient.download(base:base,token:tokens[1],url:url);fatalError("Blocked download") } catch let e as SupabaseHTTPError { precondition(e.status==403) }
   _ = try await SupabaseClient.request(base:base,path:"contacts/unblock",body:["target":peers[0].id],token:tokens[1])
   // The shared media URL itself grants no public download.
   var plain=URLComponents(url:url,resolvingAgainstBaseURL:false)!;plain.fragment=nil
   let (_,response)=try await URLSession.shared.data(from:plain.url!);precondition((response as! HTTPURLResponse).statusCode != 200)
   _ = try await SupabaseClient.request(base:base,path:"media/delete",body:["id":uploaded.mediaId],token:tokens[0])
   print("PASS encrypted attachment \(i+1): idempotent retry, byte equality, recipient access, outsider and block rejection, no public download, Storage cleanup")
  }
  for t in tokens { _ = try await SupabaseClient.request(base:base,path:"logout",token:t) }
  precondition(SupabaseSyncPolicy.interval(conversationVisible:true,hasBacklog:false)==3)
  precondition(SupabaseSyncPolicy.interval(conversationVisible:false,hasBacklog:false)==15)
  precondition(SupabaseSyncPolicy.retryDelay(failures:1,rateLimited:true)==60)
  precondition(SupabaseSyncPolicy.retryDelay(failures:20,rateLimited:false)==60)
  print("PASS foreground pacing and bounded error backoff")
 }
}
