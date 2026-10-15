import Foundation

@MainActor
enum GroupProjectService {
    static func request(group: UUID, operation: String = "project", method: String = "GET", body: [String: Any]? = nil) async throws -> GroupProjectSnapshot {
        guard !DesignPreviewData.isEnabled else { throw RelayRequestError(message: "Vista de diseño: no se envían cambios al grupo.") }
        let data = try await RelayAPI.request("/api/v1/groups/\(group.uuidString.lowercased())/\(operation)", method: method, body: body)
        return try JSONDecoder().decode(GroupProjectSnapshot.self, from: data)
    }
    static func save(group: UUID, plan: GroupProjectPlan) async throws -> GroupProjectSnapshot {
        guard plan.isValid else { throw RelayRequestError(message: "Revisa el objetivo y el orden de las fechas.") }
        let formatter = ISO8601DateFormatter()
        return try await request(group: group, method: "PUT", body: ["objective": plan.objective, "startsAt": formatter.string(from: plan.startsAt), "endsAt": formatter.string(from: plan.endsAt), "reviewAt": plan.reviewAt.map { formatter.string(from: $0) } as Any? ?? NSNull(), "timezone": plan.timezone, "status": plan.status, "version": plan.version])
    }
}
