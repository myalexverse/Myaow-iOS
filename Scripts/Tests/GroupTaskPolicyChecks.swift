import Foundation

@main struct GroupTaskPolicyChecks {
    static func main() {
        let id = UUID()
        let members = [SpaceMemberModel(displayName: "Owner", myaowId: "owner", role: "Creador"), SpaceMemberModel(displayName: "Admin", myaowId: "admin", role: "Admin"), SpaceMemberModel(displayName: "Creator", myaowId: "creator"), SpaceMemberModel(displayName: "Assignee", myaowId: "assignee"), SpaceMemberModel(displayName: "Member", myaowId: "member")]
        let task = GroupMissionModel(groupId: id, title: "Task", assigneeMyaowId: "assignee", creatorMyaowId: "creator", progress: 25)
        var group = GroupSpaceModel(id: id, title: "Team", memberCount: members.count, connectedCount: 0, lastMessage: "", members: members, missions: [task], ownerMyaowId: "owner")
        for policy in GroupTaskPolicy.allCases {
            group.taskPolicy = policy
            for actor in ["owner", "admin"] { assert(group.canCreateTask(actor) && group.canUpdateTask(task, actor: actor) && group.canDeleteTask(task, actor: actor)) }
            assert(!group.canCreateTask("outsider") && !group.canUpdateTask(task, actor: "outsider") && !group.canDeleteTask(task, actor: "outsider"))
            assert(group.canUpdateTask(task, actor: "member") == (policy == .open))
            assert(group.canUpdateTask(task, actor: "assignee") == (policy != .admins))
            assert(group.canDeleteTask(task, actor: "creator") == (policy != .admins))
            assert(!group.canDeleteTask(task, actor: "member"))
        }
        group.missions.append(GroupMissionModel(groupId: id, title: "Done", isCompleted: true))
        assert(group.progressPercentage == 0.625 && group.completedMissionsCount == 1)
        group.missions = []; assert(group.progressPercentage == 0)
        print("PASS: all task roles, nonmembers, open/admin/assigned policies and weighted project percentage")
    }
}
