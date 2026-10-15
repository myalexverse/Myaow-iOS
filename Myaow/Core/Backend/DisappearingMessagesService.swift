//
//  DisappearingMessagesService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public enum DisappearingDuration: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "Desactivado"
    case twentyFourHours = "24 horas"
    case sevenDays = "7 días"
    case ninetyDays = "90 días"
    
    public var id: String { rawValue }
    
    public var timeInterval: TimeInterval? {
        switch self {
        case .off: return nil
        case .twentyFourHours: return 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        case .ninetyDays: return 90 * 24 * 3600
        }
    }
}

@MainActor
@Observable
public final class DisappearingMessagesService {
    public static let shared = DisappearingMessagesService()
    
    public var defaultDuration: DisappearingDuration = .off
    
    private init() {}
    
    /// Purga los mensajes que hayan superado la duración de vida útil en la base de datos
    public func purgeExpiredMessages(context: ModelContext, duration: DisappearingDuration = .off) {
        guard let maxAge = duration.timeInterval else { return }
        
        let cutoffDate = Date().addingTimeInterval(-maxAge)
        let descriptor = FetchDescriptor<MessageModel>(
            predicate: #Predicate { $0.timestamp < cutoffDate }
        )
        
        if let expired = try? context.fetch(descriptor) {
            for msg in expired {
                // Keep an offline decoration until it has been handed to the transport.
                if msg.messageTypeRaw == "theme-v1" && msg.isOutgoing && ["queued", "sending"].contains(msg.deliveryStatusRaw) { continue }
                context.delete(msg)
            }
            try? context.save()
        }
    }
}
