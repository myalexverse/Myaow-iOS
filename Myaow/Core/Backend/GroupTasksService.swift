import Foundation
import SwiftUI

struct RelayRequestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
enum RelayAPI {
    static func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        if let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL {
            let own = IdentityManager.shared.currentIdentity.myaowId
            try await OnlineMessagingService.shared.waitUntilAuthenticated()
            guard let token = OnlineMessagingService.shared.sessionToken else { throw SupabaseHTTPError(status: 401) }
            let data: Data
            if path == "/api/v1/groups/invite/create", method == "POST" {
                let target = (body?["target"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
                let found = try await SupabaseClient.request(base: base, path: "directory/lookup", body: ["username": target], token: token)
                let person = try JSONDecoder().decode(DirectoryUserResult.self, from: found)
                let invitation = try await SupabaseClient.request(base: base, path: "groups/invite", body: ["groupId": body?["groupId"] ?? "", "recipientId": person.myaowId], token: token)
                guard let result = try JSONSerialization.jsonObject(with: invitation) as? [String: Any], let code = result["inviteId"] as? String else { throw URLError(.cannotParseResponse) }
                data = try JSONSerialization.data(withJSONObject: ["token": code])
            } else {
                let route = try SupabaseRoute(path, method: method, body: body ?? [:])
                data = try await SupabaseClient.request(base: base, path: route.path, body: route.body, token: token)
            }
            guard IdentityManager.shared.currentIdentity.myaowId == own,
                  OnlineMessagingService.shared.sessionToken == token,
                  RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL == base else { throw CancellationError() }
            return data
        }
        guard let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.httpURL,
              let url = URL(string: path, relativeTo: base) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        OnlineMessagingService.shared.authenticatedRequest(&request)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw RelayRequestError(message: "No pudimos conectar. Tus cambios no están confirmados; revisa la conexión e inténtalo de nuevo.")
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode
            throw RelayRequestError(message: code == 401 ? "Conecta tu cuenta para continuar." : code == 403 ? "No tienes permiso para realizar esta acción." : code == 409 ? "El estado cambió. Actualiza e inténtalo de nuevo." : "No se guardaron los cambios. Revisa la conexión e inténtalo de nuevo.")
        }
        return data
    }
}

public struct GroupTaskItem: Identifiable, Decodable, Sendable {
    public let id: String
    public let groupId: String
    public let title: String
    public let assigneeMyaowId: String?
    public let assigneeName: String?
    public let completedDueAt: String?
    public let dueAt: String?
    public let dueTimezone: String
    public let isKey: Bool
    public let cadence: String
    public let dueLabel: String
    public let priority: String
    public let isCompleted: Bool
    public let progress: Int
    public let completedByMyaowId: String?
    public let completedByName: String?
    public let completedAt: String?
    public let createdByMyaowId: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, priority, progress, cadence
        case completedDueAt = "completed_due_at", dueAt = "due_at", dueTimezone = "due_timezone", isKey = "is_key"
        case groupId = "group_id", assigneeMyaowId = "assignee_myaow_id", assigneeName = "assignee_name"
        case dueLabel = "due_label", isCompleted = "is_completed", completedByMyaowId = "completed_by_myaow_id"
        case completedByName = "completed_by_name", completedAt = "completed_at", createdByMyaowId = "created_by_myaow_id", createdAt = "created_at"
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); groupId = try c.decode(String.self, forKey: .groupId)
        title = try c.decode(String.self, forKey: .title)
        assigneeMyaowId = try c.decodeIfPresent(String.self, forKey: .assigneeMyaowId)
        assigneeName = try c.decodeIfPresent(String.self, forKey: .assigneeName)
        completedDueAt = try c.decodeIfPresent(String.self, forKey: .completedDueAt)
        dueAt = try c.decodeIfPresent(String.self, forKey: .dueAt)
        dueTimezone = try c.decodeIfPresent(String.self, forKey: .dueTimezone) ?? "UTC"
        isKey = try c.decodeIfPresent(Bool.self, forKey: .isKey) ?? false
        cadence = try c.decodeIfPresent(String.self, forKey: .cadence) ?? "once"
        dueLabel = try c.decode(String.self, forKey: .dueLabel); priority = try c.decode(String.self, forKey: .priority)
        isCompleted = try c.decode(Int.self, forKey: .isCompleted) == 1
        progress = isCompleted ? 100 : min(99, max(0, try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0))
        completedByMyaowId = try c.decodeIfPresent(String.self, forKey: .completedByMyaowId)
        completedByName = try c.decodeIfPresent(String.self, forKey: .completedByName)
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        createdByMyaowId = try c.decode(String.self, forKey: .createdByMyaowId)
        createdAt = try c.decode(String.self, forKey: .createdAt)
    }
    var mission: GroupMissionModel? {
        guard let id = UUID(uuidString: id), let group = UUID(uuidString: groupId) else { return nil }
        let mapped = MissionPriority(rawValue: priority) ?? (priority == "urgent" ? .urgent : priority == "high" ? .high : .normal)
        return GroupMissionModel(id: id, groupId: group, title: title, assigneeMyaowId: assigneeMyaowId,
            assigneeDisplayName: assigneeName, dueLabel: dueLabel, priority: mapped, isCompleted: isCompleted,
            completedAt: ProjectDate.parse(completedAt), completedByDisplayName: completedByName, creatorMyaowId: createdByMyaowId, progress: progress, dueAt: ProjectDate.parse(dueAt), dueTimezone: dueTimezone, isKey: isKey, cadence: cadence, completedDueAt: ProjectDate.parse(completedDueAt), completedByMyaowId: completedByMyaowId)
    }
}

@MainActor @Observable
public final class GroupTasksService {
    public static let shared = GroupTasksService()
    public var revision = 0
    public var tasks: [GroupTaskItem] = []
    public private(set) var policies: [String: GroupTaskPolicy] = [:]
    private struct TaskResponse: Decodable { let task: GroupTaskItem }
    private struct ListResponse: Decodable { let tasks: [GroupTaskItem]; let task_policy: String? }
    private init() {}

    public func createTask(groupId: String, title: String, assigneeMyaowId: String?, assigneeName: String?, dueLabel: String, priority: String, createdByMyaowId: String, requestId: String = UUID().uuidString, dueAt: Date? = nil, dueTimezone: String = "UTC", isKey: Bool = false, cadence: String = "once") async throws -> GroupTaskItem {
        var body: [String: Any] = ["id": requestId.lowercased(), "title": title, "dueLabel": dueLabel, "priority": priority]
        body["assigneeMyaowId"] = assigneeMyaowId
        let planned = dueAt != nil || isKey || cadence != "once"
        if planned {
            body["dueAt"] = dueAt.map { ISO8601DateFormatter().string(from: $0) }
            body["dueTimezone"] = dueTimezone; body["isKey"] = isKey; body["cadence"] = cadence
        }
        let data = try await RelayAPI.request("/api/v1/groups/\(groupId.lowercased())/\(planned ? "planned-tasks" : "tasks")", method: "POST", body: body)
        let task = try JSONDecoder().decode(TaskResponse.self, from: data).task
        tasks.removeAll { $0.id == task.id }; tasks.append(task)
        return task
    }
    public func fetchTasks(groupId: String) async throws -> [GroupTaskItem] {
        let data = try await RelayAPI.request("/api/v1/groups/\(groupId.lowercased())/tasks")
        let response = try JSONDecoder().decode(ListResponse.self, from: data)
        if let value = response.task_policy, let policy = GroupTaskPolicy(rawValue: value) { policies[groupId.lowercased()] = policy }
        let result = response.tasks
        tasks.removeAll { $0.groupId == groupId }; tasks.append(contentsOf: result)
        return result
    }
    public func completeTask(taskId: String, completedByMyaowId: String, completedByName: String, completed: Bool = true) async throws {
        let data = try await RelayAPI.request("/api/v1/tasks/\(taskId.lowercased())/complete", method: "PUT", body: ["completed": completed])
        let task = try JSONDecoder().decode(TaskResponse.self, from: data).task
        tasks.removeAll { $0.id == task.id }; tasks.append(task)
    }
    public func deleteTask(taskId: String) async throws {
        _ = try await RelayAPI.request("/api/v1/tasks/\(taskId.lowercased())", method: "DELETE")
        tasks.removeAll { $0.id.lowercased() == taskId.lowercased() }
    }
    public func updatePlan(taskId: String, dueAt: Date?, timezone: String, isKey: Bool, cadence: String, assignee: String?) async throws -> GroupMissionModel? {
        let data = try await RelayAPI.request("/api/v1/tasks/\(taskId.lowercased())/plan", method: "PUT", body: ["dueAt": dueAt.map { ISO8601DateFormatter().string(from: $0) } as Any? ?? NSNull(), "dueTimezone": timezone, "isKey": isKey, "cadence": cadence, "assigneeMyaowId": assignee as Any? ?? NSNull()])
        let item = try JSONDecoder().decode(TaskResponse.self, from: data).task
        tasks.removeAll { $0.id == item.id }; tasks.append(item)
        revision += 1
        return item.mission
    }
    public func updateProgress(taskId: String, progress: Int) async throws -> GroupMissionModel? {
        guard (0...100).contains(progress) else { throw SupabaseHTTPError(status: 501) }
        let data = try await RelayAPI.request("/api/v1/tasks/\(taskId.lowercased())/complete", method: "PUT",
            body: ["state": progress == 100 ? "done" : progress == 0 ? "pending" : "in_progress", "progress": progress])
        let task = try JSONDecoder().decode(TaskResponse.self, from: data).task
        tasks.removeAll { $0.id.lowercased() == task.id.lowercased() }; tasks.append(task)
        return task.mission
    }
}
