import Foundation

/// A local view of confirmed tasks. Never infers an overdue date from a legacy label.
enum GroupTaskFocus {
    enum Lane: String, CaseIterable {
        case pending = "Por empezar", active = "En marcha", completed = "Listas"
        var symbol: String { switch self { case .pending: "circle.dotted"; case .active: "arrow.trianglehead.2.clockwise.rotate.90"; case .completed: "checkmark.circle.fill" } }
    }
    static func lane(_ task: GroupMissionModel) -> Lane {
        task.isCompleted ? .completed : task.progress > 0 ? .active : .pending
    }
    static func exactDate(_ value: String, calendar: Calendar = .current) -> Date? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }
    static func dueToday(_ task: GroupMissionModel, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !task.isCompleted, !overdue(task, now: now, calendar: calendar) else { return false }
        if let date = task.dueAt ?? exactDate(task.dueLabel, calendar: calendar) { return calendar.isDate(date, inSameDayAs: now) }
        return task.dueLabel == "Hoy"
    }
    static func overdue(_ task: GroupMissionModel, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !task.isCompleted else { return false }
        if let date = task.dueAt { return date < now }
        guard let date = exactDate(task.dueLabel, calendar: calendar) else { return false }
        return date < calendar.startOfDay(for: now)
    }
    static func ordered(_ tasks: [GroupMissionModel], now: Date = Date(), calendar: Calendar = .current) -> [GroupMissionModel] {
        func priority(_ task: GroupMissionModel) -> Int { switch task.priority { case .urgent: 0; case .high: 1; case .normal: 2 } }
        func rank(_ task: GroupMissionModel) -> Int {
            task.isCompleted ? 4 : overdue(task, now: now, calendar: calendar) ? 0 : dueToday(task, now: now, calendar: calendar) ? 1 : 2
        }
        return tasks.sorted {
            if rank($0) != rank($1) { return rank($0) < rank($1) }
            if priority($0) != priority($1) { return priority($0) < priority($1) }
            let left = $0.dueAt ?? exactDate($0.dueLabel, calendar: calendar) ?? .distantFuture
            let right = $1.dueAt ?? exactDate($1.dueLabel, calendar: calendar) ?? .distantFuture
            if left != right { return left < right }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
