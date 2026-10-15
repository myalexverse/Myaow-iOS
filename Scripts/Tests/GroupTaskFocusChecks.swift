import Foundation

@main struct GroupTaskFocusChecks {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Mexico_City")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 14))!
        let group = UUID()
        let today = GroupMissionModel(groupId: group, title: "Hoy", dueLabel: "2026-10-13", progress: 50)
        let overdue = GroupMissionModel(groupId: group, title: "Ayer", dueLabel: "2026-10-12")
        let future = GroupMissionModel(groupId: group, title: "Después", dueLabel: "2026-10-20", priority: .urgent)
        let done = GroupMissionModel(groupId: group, title: "Listo", dueLabel: "2026-10-01", isCompleted: true)
        let relative = GroupMissionModel(groupId: group, title: "Heredada", dueLabel: "Hoy")
        assert(GroupTaskFocus.dueToday(today, now: now, calendar: calendar))
        assert(!GroupTaskFocus.overdue(today, now: now, calendar: calendar))
        assert(GroupTaskFocus.overdue(overdue, now: now, calendar: calendar))
        assert(!GroupTaskFocus.overdue(done, now: now, calendar: calendar))
        assert(!GroupTaskFocus.overdue(relative, now: now, calendar: calendar))
        assert(GroupTaskFocus.exactDate("2026-02-31", calendar: calendar) == nil)
        assert(GroupTaskFocus.exactDate("Mañana", calendar: calendar) == nil)
        assert(GroupTaskFocus.exactDate("2026-13-01", calendar: calendar) == nil)
        assert(GroupTaskFocus.exactDate("2028-02-29", calendar: calendar) != nil)
        assert(GroupTaskFocus.lane(today) == .active && GroupTaskFocus.lane(done) == .completed && GroupTaskFocus.lane(future) == .pending)
        let sorted = GroupTaskFocus.ordered([done, future, today, overdue], now: now, calendar: calendar)
        assert(sorted.map(\.id) == [overdue.id, today.id, future.id, done.id])
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        assert(GroupTaskFocus.overdue(today, now: tomorrow, calendar: calendar))
        print("PASS: exact-date and legacy-label classification, midnight, invalid dates, priority order and complete lanes")
    }
}
