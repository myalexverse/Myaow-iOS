import Foundation
import Observation

@MainActor @Observable
public final class ContactBlockingService {
    public static let shared = ContactBlockingService()
    private init() {}
    
    private var revision = 0
    public private(set) var blockedIds: Set<String> {
        get {
            _ = revision
            return Set(UserDefaults.standard.stringArray(forKey: "myaow_blocked_" + IdentityManager.shared.currentIdentity.myaowId) ?? [])
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "myaow_blocked_" + IdentityManager.shared.currentIdentity.myaowId)
            revision += 1
        }
    }
    
    public func loadBlockedContacts() async {
        let owner = IdentityManager.shared.currentIdentity.myaowId
        do {
            let data = try await RelayAPI.request("/api/v1/contacts/blocked/\(owner)")
            guard IdentityManager.shared.currentIdentity.myaowId == owner else { return }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let ids = json["blockedIds"] as? [String] { blockedIds.formUnion(ids) }
        } catch { /* Preserve the local block list when offline. */ }
    }
    public func blockContact(_ myaowId: String) async -> Bool {
        await updateBlock(myaowId, blocked: true)
    }
    public func unblockContact(_ myaowId: String) async -> Bool {
        await updateBlock(myaowId, blocked: false)
    }
    private func updateBlock(_ target: String, blocked: Bool) async -> Bool {
        let owner = IdentityManager.shared.currentIdentity.myaowId
        do {
            _ = try await RelayAPI.request("/api/v1/contacts/\(blocked ? "block" : "unblock")", method: "POST", body: ["blockerId": owner, "blockedId": target])
            guard IdentityManager.shared.currentIdentity.myaowId == owner else { return false }
            if blocked { blockedIds.insert(target) } else { blockedIds.remove(target) }
            return true
        } catch { return false }
    }

    public func isBlocked(_ myaowId: String) -> Bool {
        blockedIds.contains(myaowId)
    }
}
