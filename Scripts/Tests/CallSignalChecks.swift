import Foundation
import CryptoKit
@main struct CallSignalChecks {
    static func main() throws {
        let alice = Curve25519.KeyAgreement.PrivateKey(), bob = Curve25519.KeyAgreement.PrivateKey()
        let mid = UUID().uuidString, cid = UUID().uuidString
        let now = Date(timeIntervalSince1970: 1000)
        let signal: [String:Any] = ["id":mid,"callId":cid,"type":"call_offer","callType":"Llamada de Audio","expiresAt":1045.0]
        let envelope = try SecureMessageEnvelope.seal(.init(text:String(decoding:JSONSerialization.data(withJSONObject:signal),as:UTF8.self),messageType:"call-signal-v2"),messageId:mid,senderId:"alice",recipientId:"bob",senderPrivateKey:alice.rawRepresentation,recipientPublicKey:bob.publicKey.rawRepresentation)
        let packet: [AnyHashable:Any] = ["id":mid,"callId":cid,"signalType":"call_offer","expiresAt":1045.0,"senderMyaowId":"alice","encryptedPayload":String(decoding:try JSONEncoder().encode(envelope),as:UTF8.self)]
        func open(_ p:[AnyHashable:Any], date:Date=now, owner:String="bob", peer:Data=alice.publicKey.rawRepresentation) throws -> VerifiedCallSignal {
            try VerifiedCallSignal.open(p,owner:owner,privateKey:bob.rawRepresentation,peerKey:peer,now:date,requiresOffer:true)
        }
        let verified = try open(packet)
        precondition(verified.callID == UUID(uuidString:cid))
        var count=1
        for (key,value) in [("callId",UUID().uuidString),("signalType","call_hangup"),("id",UUID().uuidString),("senderMyaowId","mallory")] {
            var altered=packet;altered[key]=value
            do { _=try open(altered);fatalError("Accepted tampered \(key)") } catch { count += 1 }
        }
        var altered=packet;altered["expiresAt"]=1046.0
        do { _=try open(altered);fatalError("Accepted changed expiry") } catch { count += 1 }
        do { _=try open(packet,date:Date(timeIntervalSince1970:1046));fatalError("Accepted stale call") } catch { count += 1 }
        do { _=try open(packet,owner:"mallory");fatalError("Accepted different account") } catch { count += 1 }
        do { _=try open(packet,peer:Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation);fatalError("Accepted untrusted identity") } catch { count += 1 }
        print("Call signal: \(count) authenticated routing / expiry checks passed")
    }
}
