//
//  GroupMissionModel.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum MissionPriority: String, CaseIterable, Identifiable, Sendable {
    case normal = "Normal"
    case high = "Importante"
    case urgent = "Urgente"
    
    public var id: String { rawValue }
    
    public var emoji: String {
        switch self {
        case .normal: return "⭐"
        case .high: return "🔥"
        case .urgent: return "⚡️"
        }
    }
}

public struct GroupMissionModel: Identifiable, Sendable, Hashable, Equatable {
    public let id: UUID
    public let groupId: UUID
    public var creatorMyaowId: String?
    public var title: String
    public var assigneeMyaowId: String?
    public var assigneeDisplayName: String?
    public var assigneeAvatarCatState: String?
    public var completedDueAt: Date?
    public var dueAt: Date?
    public var dueTimezone: String
    public var isKey: Bool
    public var cadence: String
    public var dueText: String {
        guard let dueAt else { return dueLabel }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.timeZone = TimeZone(identifier: dueTimezone) ?? .current
        formatter.dateFormat = "d MMM yyyy · HH:mm"
        return formatter.string(from: dueAt) + " · " + (formatter.timeZone.abbreviation(for: dueAt) ?? dueTimezone)
    }
    public var dueLabel: String // "Hoy", "Mañana", "Esta semana", "Pronto"
    public var priority: MissionPriority
    public var isCompleted: Bool
    public var progress: Int
    public var completedAt: Date?
    public var completedByMyaowId: String?
    public var completedByDisplayName: String?
    public var reactions: [String: Int] // ["❤️": 2, "🔥": 4, "👏": 3, "😸": 1]
    
    public init(
        id: UUID = UUID(),
        groupId: UUID,
        title: String,
        assigneeMyaowId: String? = nil,
        assigneeDisplayName: String? = nil,
        assigneeAvatarCatState: String? = "Amigable",
        dueLabel: String = "Hoy",
        priority: MissionPriority = .normal,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        completedByDisplayName: String? = nil,
        reactions: [String: Int] = [:],
        creatorMyaowId: String? = nil,
        progress: Int = 0, dueAt: Date? = nil, dueTimezone: String = "UTC", isKey: Bool = false, cadence: String = "once", completedDueAt: Date? = nil, completedByMyaowId: String? = nil
    ) {
        self.id = id
        self.groupId = groupId
        self.title = title
        self.creatorMyaowId = creatorMyaowId
        self.assigneeMyaowId = assigneeMyaowId
        self.assigneeDisplayName = assigneeDisplayName
        self.assigneeAvatarCatState = assigneeAvatarCatState
        self.dueLabel = dueLabel
        self.completedDueAt = completedDueAt
        self.dueAt = dueAt; self.dueTimezone = dueTimezone; self.isKey = isKey; self.cadence = cadence
        self.priority = priority
        self.isCompleted = isCompleted
        self.progress = isCompleted ? 100 : min(99, max(0, progress))
        self.completedAt = completedAt
        self.completedByDisplayName = completedByDisplayName
        self.completedByMyaowId = completedByMyaowId
        self.reactions = reactions
    }
}

public enum GroupProjectMood: String, CaseIterable, Sendable {
    case organized = "Organizados"
    case inProgress = "En marcha"
    case almostDone = "¡Casi listos!"
    case completed = "¡Misión cumplida!"
    case paused = "Tranquilo"
    
    public var emoji: String {
        switch self {
        case .organized: return "😌"
        case .inProgress: return "😸"
        case .almostDone: return "🤩"
        case .completed: return "🎉"
        case .paused: return "😴"
        }
    }
    
    public var catState: MyaowCatState {
        switch self {
        case .organized: return .calm
        case .inProgress: return .friendly
        case .almostDone: return .cool
        case .completed: return .party
        case .paused: return .sleeping
        }
    }
    
    public var message: String {
        switch self {
        case .organized: return "Pocas tareas pendientes, todo bajo control."
        case .inProgress: return "¡El proyecto está avanzando a buen ritmo!"
        case .almostDone: return "¡Falta muy poco para terminar juntos!"
        case .completed: return "¡Todo el grupo completó el objetivo! 🎉"
        case .paused: return "Sin misiones urgentes por ahora."
        }
    }
}

public struct MissionTemplate: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let emoji: String
    public let missionTitles: [String]
    
    public static let allTemplates: [MissionTemplate] = [
        MissionTemplate(
            id: "party",
            title: "Fiesta / Evento",
            emoji: "🎉",
            missionTitles: [
                "Comprar pastel 🎂",
                "Conseguir bocinas y música 🎶",
                "Hacer y enviar invitaciones ✉️",
                "Comprar bebidas y botanas 🥤",
                "Confirmar lista de invitados 📋",
                "Montaje y decoración 🎈"
            ]
        ),
        MissionTemplate(
            id: "trip",
            title: "Viaje / Excursión",
            emoji: "🏕️",
            missionTitles: [
                "Reservar hospedaje / cabaña 🏡",
                "Planear transporte y gasolina 🚗",
                "Crear itinerario de lugares 🗺️",
                "Comprar víveres para el camino 🥪",
                "Revisar lista de equipaje 🎒"
            ]
        ),
        MissionTemplate(
            id: "home",
            title: "Hogar / Mudanza",
            emoji: "🏠",
            missionTitles: [
                "Empacar cajas por habitación 📦",
                "Contratar transporte / flete 🚚",
                "Contratar servicios (Internet, Luz) 💡",
                "Limpieza profunda del lugar 🧹"
            ]
        ),
        MissionTemplate(
            id: "school",
            title: "Escuela / Universidad",
            emoji: "🎓",
            missionTitles: [
                "Investigar fuentes y bibliografía 📚",
                "Diseñar diapositivas de presentación 📊",
                "Redactar conclusiones y reporte 📝",
                "Ensayo general de la exposición 🎤"
            ]
        ),
        MissionTemplate(
            id: "creative",
            title: "Proyecto Creativo",
            emoji: "🎬",
            missionTitles: [
                "Escribir guion y concepto 💡",
                "Sesión de grabación / fotografía 📸",
                "Edición y postproducción ✂️",
                "Publicar y compartir en redes 🚀"
            ]
        )
    ]
}
