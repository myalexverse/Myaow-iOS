//
//  GroupSpaceModel.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum SpaceCategory: String, CaseIterable, Identifiable, Sendable {
    case party = "Fiesta"
    case trip = "Viaje"
    case workshop = "Taller"
    case design = "Diseño"
    case family = "Familia"
    case general = "General"
    
    public var id: String { rawValue }
    
    public var emoji: String {
        switch self {
        case .party: return "🎉"
        case .trip: return "🏕️"
        case .workshop: return "🛠️"
        case .design: return "🎨"
        case .family: return "🏠"
        case .general: return "👥"
        }
    }
}

public struct SpaceMemberModel: Identifiable, Sendable, Hashable, Equatable {
    public let id: UUID
    public let displayName: String
    public let myaowId: String
    public let role: String // "Creadora", "Admin", "Miembro"
    public let isOnline: Bool
    public let moodEmoji: String
    public let moodLabel: String
    public let catState: MyaowCatState
    
    public init(
        id: UUID = UUID(),
        displayName: String,
        myaowId: String,
        role: String = "Miembro",
        isOnline: Bool = true,
        moodEmoji: String = "😸",
        moodLabel: String = "Feliz",
        catState: MyaowCatState = .happy
    ) {
        self.id = id
        self.displayName = displayName
        self.myaowId = myaowId
        self.role = role
        self.isOnline = isOnline
        self.moodEmoji = moodEmoji
        self.moodLabel = moodLabel
        self.catState = catState
    }
}

public struct SpaceFileModel: Identifiable, Sendable, Hashable, Equatable {
    public let id: UUID
    public let name: String
    public let sizeText: String
    public let senderName: String
    public let timestampText: String
    public let iconName: String
    
    public init(
        id: UUID = UUID(),
        name: String,
        sizeText: String,
        senderName: String,
        timestampText: String,
        iconName: String = "doc.fill"
    ) {
        self.id = id
        self.name = name
        self.sizeText = sizeText
        self.senderName = senderName
        self.timestampText = timestampText
        self.iconName = iconName
    }
}

public enum GroupTaskPolicy: String, CaseIterable, Sendable {
    case open, admins, assigned
    var title: String { switch self { case .open: "Todos colaboran"; case .admins: "Solo administradores"; case .assigned: "Responsables y creadores" } }
    var detail: String { switch self {
    case .open: "Todos los integrantes pueden crear tareas, actualizar avances y completarlas."
    case .admins: "Solo los administradores crean, actualizan y completan tareas. Todos pueden consultar y comentar."
    case .assigned: "Todos pueden crear; el responsable, el creador y los administradores actualizan cada tarea."
    } }
}

public struct GroupSpaceModel: Identifiable, Sendable, Hashable, Equatable {
    public let id: UUID
    public var title: String
    public var description: String
    public var category: SpaceCategory
    public var isTemporary: Bool
    public var expiresAtText: String?
    public var memberCount: Int
    public var connectedCount: Int
    public var isMeshActive: Bool
    public var lastMessage: String
    public var lastMessageTime: String
    public var pulseStatusText: String
    public var members: [SpaceMemberModel]
    public var files: [SpaceFileModel]
    public var missions: [GroupMissionModel]
    public var taskPolicy: GroupTaskPolicy
    public var ownerMyaowId: String?
    public var streakDays: Int
    
    public init(
        id: UUID = UUID(),
        title: String,
        description: String = "",
        category: SpaceCategory = .general,
        isTemporary: Bool = false,
        expiresAtText: String? = nil,
        memberCount: Int,
        connectedCount: Int,
        isMeshActive: Bool = true,
        lastMessage: String,
        lastMessageTime: String = "Ahora",
        pulseStatusText: String = "El grupo está activo",
        members: [SpaceMemberModel] = [],
        files: [SpaceFileModel] = [],
        missions: [GroupMissionModel] = [],
        streakDays: Int = 1,
        ownerMyaowId: String? = nil,
        taskPolicy: GroupTaskPolicy = .assigned
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.isTemporary = isTemporary
        self.expiresAtText = expiresAtText
        self.memberCount = memberCount
        self.connectedCount = connectedCount
        self.isMeshActive = isMeshActive
        self.lastMessage = lastMessage
        self.lastMessageTime = lastMessageTime
        self.pulseStatusText = pulseStatusText
        self.members = members
        self.files = files
        self.missions = missions
        self.streakDays = streakDays
        self.ownerMyaowId = ownerMyaowId
        self.taskPolicy = taskPolicy
    }
    
    public func isAdministrator(_ actor: String) -> Bool {
        ownerMyaowId == actor || members.contains { $0.myaowId == actor && ["Admin", "Creador", "Creadora"].contains($0.role) }
    }
    public func canCreateTask(_ actor: String) -> Bool { isAdministrator(actor) || (taskPolicy != .admins && members.contains { $0.myaowId == actor }) }
    public func canUpdateTask(_ task: GroupMissionModel, actor: String) -> Bool {
        if isAdministrator(actor) { return true }
        guard members.contains(where: { $0.myaowId == actor }) else { return false }
        return taskPolicy == .open || (taskPolicy == .assigned && (task.creatorMyaowId == actor || task.assigneeMyaowId == actor))
    }
    public func canDeleteTask(_ task: GroupMissionModel, actor: String) -> Bool {
        isAdministrator(actor) || (taskPolicy != .admins && members.contains { $0.myaowId == actor } && task.creatorMyaowId == actor)
    }

    // MARK: - Métodos Calculados de Progreso y Gamificación
    public var totalMissionsCount: Int {
        missions.count
    }
    
    public var completedMissionsCount: Int {
        missions.filter { $0.isCompleted }.count
    }
    
    public var pendingMissionsCount: Int {
        totalMissionsCount - completedMissionsCount
    }
    
    public var progressPercentage: Double {
        guard totalMissionsCount > 0 else { return 0.0 }
        return Double(missions.reduce(0) { $0 + ($1.isCompleted ? 100 : $1.progress) }) / Double(totalMissionsCount * 100)
    }
    
    public var progressPercentageInt: Int {
        Int(progressPercentage * 100)
    }
    
    public var groupMood: GroupProjectMood {
        if totalMissionsCount == 0 { return .paused }
        if completedMissionsCount == totalMissionsCount { return .completed }
        if progressPercentage >= 0.75 { return .almostDone }
        if progressPercentage >= 0.25 { return .inProgress }
        return .organized
    }
    
    public var nextActionMission: GroupMissionModel? {
        missions.first { !$0.isCompleted }
    }
    
    public func myPendingMissions(myMyaowId: String) -> [GroupMissionModel] {
        missions.filter { !$0.isCompleted && ($0.assigneeMyaowId == myMyaowId || $0.assigneeDisplayName == "Tú") }
    }
}
