import Foundation

@MainActor
@Observable
public final class GroupsNetworkService {
    public static let shared = GroupsNetworkService()
    public var lastError: String?
    private init() {}
    
    private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async -> [String: Any]? {
        lastError = nil
        let owner = IdentityManager.shared.currentIdentity.myaowId
        do {
            let data = try await RelayAPI.request(path, method: method, body: body)
            guard IdentityManager.shared.currentIdentity.myaowId == owner else { throw CancellationError() }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.cannotParseResponse) }
            return json
        } catch { lastError = error.localizedDescription; return nil }
    }
    public func createGroup(name: String, category: String) async -> String? {
        let body: [String: Any] = ["id": UUID().uuidString.lowercased(), "name": name, "category": category, "taskPolicy": "open", "creatorMyaowId": IdentityManager.shared.currentIdentity.myaowId]
        return await request("/api/v1/groups/create", method: "POST", body: body)?["groupId"] as? String
    }
    public func fetchMyGroups() async -> [[String: Any]] {
        await request("/api/v1/groups/my/\(IdentityManager.shared.currentIdentity.myaowId)")?["groups"] as? [[String: Any]] ?? []
    }
    public func fetchMembers(groupId: String) async -> [[String: Any]] {
        await request("/api/v1/groups/\(groupId.lowercased())/members")?["members"] as? [[String: Any]] ?? []
    }
    public func joinGroup(groupId: String) async -> Bool {
        await request("/api/v1/groups/\(groupId.lowercased())/join", method: "POST", body: ["myaowId": IdentityManager.shared.currentIdentity.myaowId]) != nil
    }
    public func leaveGroup(groupId: String) async -> Bool {
        await request("/api/v1/groups/\(groupId.lowercased())/leave", method: "POST", body: ["myaowId": IdentityManager.shared.currentIdentity.myaowId]) != nil
    }
    public func kickMember(groupId: String, targetMyaowId: String) async -> Bool {
        await request("/api/v1/groups/\(groupId.lowercased())/kick", method: "POST", body: ["requesterMyaowId": IdentityManager.shared.currentIdentity.myaowId, "targetMyaowId": targetMyaowId]) != nil
    }
    public func promoteMember(groupId: String, targetMyaowId: String) async -> Bool {
        await request("/api/v1/groups/\(groupId.lowercased())/promote", method: "POST", body: ["requesterMyaowId": IdentityManager.shared.currentIdentity.myaowId, "targetMyaowId": targetMyaowId]) != nil
    }
    public func updateGroupInfo(groupId: String, name: String?, description: String?, taskPolicy: GroupTaskPolicy? = nil) async -> Bool {
        var body: [String: Any] = [:]
        body["name"] = name; body["description"] = description; body["taskPolicy"] = taskPolicy?.rawValue
        return await request("/api/v1/groups/\(groupId.lowercased())/info", method: "PUT", body: body) != nil
    }
}
