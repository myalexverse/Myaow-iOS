//
//  ModerationModels.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation

public enum ModerationStatus: String, Codable, Sendable {
    case approved = "Aprobado"
    case blurred = "Difuminado"
    case blocked = "Bloqueado"
}

public enum ModerationCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case violence = "Violencia"
    case nudity = "Desnudos"
    case offensiveLanguage = "Lenguaje ofensivo"
    case other = "Otro"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .violence: return "exclamationmark.triangle.fill"
        case .nudity: return "eye.slash.fill"
        case .offensiveLanguage: return "bubble.left.and.exclamationmark.bubble.right.fill"
        case .other: return "shield.slash.fill"
        }
    }
}

public struct ModerationResult: Sendable {
    public let status: ModerationStatus
    public let triggeredCategory: ModerationCategory?
    public let confidence: Double
    public let explanation: String
}
