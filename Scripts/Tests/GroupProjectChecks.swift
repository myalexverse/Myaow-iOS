import Foundation
@main struct GroupProjectChecks {
    static func main() throws {
        let now = ProjectDate.parse("2026-10-14T18:00:00Z")!
        let id = UUID()
        let key = GroupMissionModel(groupId: id, title: "Clave", dueAt: now.addingTimeInterval(-60), isKey: true)
        let later = GroupMissionModel(groupId: id, title: "Después", dueAt: now.addingTimeInterval(60))
        var plan = GroupProjectPlan(objective: "Objetivo", startsAt: now.addingTimeInterval(-86400), endsAt: now.addingTimeInterval(86400))
        assert(plan.isValid)
        assert(ProjectHealth.evaluate(plan: nil, tasks: [key], now: now) == .unplanned)
        assert(ProjectHealth.evaluate(plan: plan, tasks: [key], now: now) == .critical)
        assert(ProjectHealth.evaluate(plan: plan, tasks: [later], now: now) == .active)
        assert(GroupTaskFocus.overdue(key, now: now))
        assert(!GroupTaskFocus.dueToday(key, now: now)) // overdue and today never duplicate rows
        assert(!GroupTaskFocus.overdue(later, now: now))
        var ordinary = key; ordinary.isKey = false
        assert(ProjectHealth.evaluate(plan: plan, tasks: [ordinary], now: now) == .attention)
        plan.reviewAt = now.addingTimeInterval(-30)
        assert(ProjectHealth.evaluate(plan: plan, tasks: [later], now: now) == .attention)
        plan.status = "paused"
        assert(ProjectHealth.evaluate(plan: plan, tasks: [key], now: now) == .paused)
        plan.status = "completed"
        assert(ProjectHealth.evaluate(plan: plan, tasks: [key], now: now) != .completed)
        var done = key; done.isCompleted = true; done.progress = 100; done.completedDueAt = key.dueAt; done.completedAt = now.addingTimeInterval(-120)
        assert(ProjectHealth.earlyDeliveries([done, key]).count == 1)
        assert(ProjectHealth.evaluate(plan: plan, tasks: [done], now: now) == .completed)
        assert(ProjectDate.parse("2026-10-14T12:00:00-06:00") == now)
        assert(ProjectDate.parse("2026-10-14T18:00:00.000Z") == now)
        plan.reviewAt = plan.endsAt.addingTimeInterval(1); assert(!plan.isValid)
        plan.reviewAt = nil; plan.endsAt = plan.startsAt; assert(!plan.isValid)
        print("PASS: exact instant, timezone offsets, fractional timestamps, health states, key deadlines, review period, honest early achievements")
    }
}
