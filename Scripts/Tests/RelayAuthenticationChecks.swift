import Foundation

@main
struct RelayAuthenticationChecks {
    static func main() throws {
        struct Vector: Decodable {
            let myaowId: String
            let privateKeyHex: String
            let nonce: String
            let serverPublicKeyHex: String
            let expectedProof: String
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let vector = try JSONDecoder().decode(Vector.self, from: data)
        let proof = try RelayAuthentication.proof(myaowId: vector.myaowId, privateKeyHex: vector.privateKeyHex, nonce: vector.nonce, serverPublicKeyHex: vector.serverPublicKeyHex)
        precondition(proof == vector.expectedProof, "Swift and Node must produce the same proof")
        let otherIdentity = try RelayAuthentication.proof(myaowId: "MYAOW-OTHER", privateKeyHex: vector.privateKeyHex, nonce: vector.nonce, serverPublicKeyHex: vector.serverPublicKeyHex)
        precondition(otherIdentity != proof, "Proof must be bound to the identity")
        do {
            _ = try RelayAuthentication.proof(myaowId: vector.myaowId, privateKeyHex: vector.privateKeyHex, nonce: "invalid", serverPublicKeyHex: vector.serverPublicKeyHex)
            fatalError("Invalid challenges must be rejected")
        } catch {}
        print("PASS: Swift CryptoKit and Node agree; identity binding and malformed challenge checks passed.")
    }
}
