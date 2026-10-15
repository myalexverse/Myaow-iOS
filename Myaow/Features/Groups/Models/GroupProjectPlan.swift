import Foundation

enum ProjectDate {
    static func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
    static func text(_ date: Date, timezone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.timeZone = TimeZone(identifier: timezone) ?? .current
        formatter.dateFormat = "d MMM yyyy · HH:mm z"
        return formatter.string(from: date)
    }
}

struct GroupProjectPlan: Decodable, Equatable, Sendable {
    var objective: String
    var startsAt: Date
    var endsAt: Date
    var reviewAt: Date?
    var timezone: String
    var status: String
    var version: Int
    enum CodingKeys: String, CodingKey {
        case objective, timezone, status, version
        case startsAt = "starts_at", endsAt = "ends_at", reviewAt = "review_at"
    }
    init(objective: String = "", startsAt: Date = Date(), endsAt: Date = Date().addingTimeInterval(7 * 86400), reviewAt: Date? = nil, timezone: String = TimeZone.current.identifier, status: String = "active", version: Int = 0) {
        self.objective = objective; self.startsAt = startsAt; self.endsAt = endsAt; self.reviewAt = reviewAt
        self.timezone = timezone; self.status = status; self.version = version
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objective = try c.decode(String.self, forKey: .objective)
        guard let start = ProjectDate.parse(try c.decode(String.self, forKey: .startsAt)), let end = ProjectDate.parse(try c.decode(String.self, forKey: .endsAt)) else { throw DecodingError.dataCorruptedError(forKey: .startsAt, in: c, debugDescription: "Invalid project dates") }
        startsAt = start; endsAt = end
        reviewAt = ProjectDate.parse(try c.decodeIfPresent(String.self, forKey: .reviewAt))
        timezone = try c.decode(String.self, forKey: .timezone); status = try c.decode(String.self, forKey: .status); version = try c.decode(Int.self, forKey: .version)
    }
    var isValid: Bool { !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && objective.count <= 1200 && endsAt > startsAt && (reviewAt == nil || (reviewAt! >= startsAt && reviewAt! <= endsAt)) }
}

struct GroupProjectProposal: Decodable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var author: String
    var author_name: String
    var accepted: Bool
    var task_id: UUID?
    var votes: Int
    var voted: Bool
}
struct GroupProjectSnapshot: Decodable, Sendable {
    var project: GroupProjectPlan?
    var proposals: [GroupProjectProposal]
}

enum ProjectHealth: String {
    case unplanned = "Por definir", active = "En marcha", attention = "Necesita atención", critical = "Rescatemos el plan", paused = "En pausa", completed = "Objetivo cumplido"
    static func evaluate(plan: GroupProjectPlan?, tasks: [GroupMissionModel], now: Date = Date()) -> ProjectHealth {
        guard let plan else { return .unplanned }
        if plan.status == "paused" { return .paused }
        let pending = tasks.filter { !$0.isCompleted }
        if plan.status == "completed" && pending.isEmpty { return .completed }
        if (!pending.isEmpty && now > plan.endsAt) || pending.contains(where: { $0.isKey && GroupTaskFocus.overdue($0, now: now) }) { return .critical }
        if pending.contains(where: { GroupTaskFocus.overdue($0, now: now) }) || (plan.reviewAt.map { $0 < now } ?? false) { return .attention }
        return .active
    }
    func reason(plan: GroupProjectPlan?, tasks: [GroupMissionModel], now: Date = Date()) -> String {
        switch self {
        case .unplanned: return "Definan el objetivo y las fechas para darle dirección al equipo."
        case .paused: return "El equipo puso el proyecto en pausa. Los plazos siguen visibles."
        case .completed: return "El equipo cerró el proyecto con sus tareas terminadas."
        case .critical: return tasks.contains { !$0.isCompleted && $0.isKey && GroupTaskFocus.overdue($0, now: now) } ? "Hay tareas clave vencidas. Reorganicemos el siguiente paso." : "La fecha de cierre pasó y aún quedan tareas. Revisemos el plan."
        case .attention: return tasks.contains { GroupTaskFocus.overdue($0, now: now) } ? "Hay entregas vencidas. Revisen responsables y fechas." : "Es momento de revisar el proyecto y acordar la siguiente fecha."
        case .active: return tasks.isEmpty ? "El objetivo está definido. Añadan las primeras tareas." : "No hay vencimientos pendientes de atención. Sigamos avanzando."
        }
    }
    static func earlyDeliveries(_ tasks: [GroupMissionModel]) -> [GroupMissionModel] {
        tasks.filter { $0.isCompleted && $0.completedDueAt != nil && $0.completedAt != nil && $0.completedAt! < $0.completedDueAt! }
    }
}
