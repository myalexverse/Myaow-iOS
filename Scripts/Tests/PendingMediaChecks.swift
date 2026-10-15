import Foundation
import CryptoKit
@main struct PendingMediaChecks {
 static func main() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:root) }
  let base=URL(string:"https://example.supabase.co/functions/v1/myaow-api")!
  let bytes=Data("private file payload".utf8),key=Data(repeating:7,count:32),mid=UUID().uuidString
  let store=PendingMediaUploadStore(base:base,owner:"A",root:root)
  let initial=try store.prepare(data:bytes,messageID:mid,privateKey:key)
  let restarted=try PendingMediaUploadStore(base:base,owner:"A",root:root).prepare(data:bytes,messageID:mid,privateKey:key)
  precondition(initial.id==restarted.id && initial.ciphertext==restarted.ciphertext && initial.keyFragment==restarted.keyFragment)
  let other=try PendingMediaUploadStore(base:base,owner:"B",root:root).prepare(data:bytes,messageID:mid,privateKey:key)
  precondition(other.id != initial.id)
  do { _ = try store.prepare(data:Data("different".utf8),messageID:mid,privateKey:key);fatalError("Message ID reuse") } catch SecureMessageError.invalidEnvelope {}
  do { _ = try store.prepare(data:bytes,messageID:mid,privateKey:Data(repeating:9,count:32));fatalError("Wrong key") } catch {}
  let file=root.appendingPathComponent(store.scope).appendingPathComponent(mid)
  let saved=try Data(contentsOf:file)
  precondition(saved.range(of:bytes)==nil && saved.range(of:Data(initial.keyFragment.utf8))==nil)
  for link in ["https://evil.test/functions/v1/myaow-api/media/"+mid,"https://example.supabase.co/other/media/"+mid,"https://example.supabase.co/functions/v1/myaow-api/media/"+mid+"?key=bad"] {
   do { _ = try SupabaseMediaClient.objectID(from:URL(string:link)!,base:base);fatalError("Foreign origin accepted") } catch {}
  }
  try store.remove(messageID:mid);precondition(!FileManager.default.fileExists(atPath:file.path))
  print("PASS: encrypted pending uploads survive restart, reuse ciphertext, isolate accounts, reject changed payloads/keys and foreign download origins, clean up after enqueue")
 }
}
