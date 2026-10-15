//
//  MomentModel.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation
import SwiftData

@Model
public final class MomentModel {
    @Attribute(.unique) public var id: String = UUID().uuidString
    public var authorMyaowId: String = ""
    public var authorDisplayName: String = ""
    public var authorAvatarCatState: String = "friendly"
    public var captionText: String = ""
    @Attribute(.externalStorage) public var mediaData: Data? = nil
    public var catEmotionRaw: String = "friendly"
    public var backgroundGradientIndex: Int = 0
    public var createdAt: Date = Date()
    public var expiresAt: Date = Date().addingTimeInterval(86400) // 24 horas por defecto
    public var isSeen: Bool = false
    public var isMine: Bool = false
    
    public init(
        id: String = UUID().uuidString,
        authorMyaowId: String,
        authorDisplayName: String,
        authorAvatarCatState: String = "friendly",
        captionText: String = "",
        mediaData: Data? = nil,
        catEmotionRaw: String = "friendly",
        backgroundGradientIndex: Int = 0,
        createdAt: Date = Date(),
        expiresAt: Date = Date().addingTimeInterval(86400),
        isSeen: Bool = false,
        isMine: Bool = false
    ) {
        self.id = id
        self.authorMyaowId = authorMyaowId
        self.authorDisplayName = authorDisplayName
        self.authorAvatarCatState = authorAvatarCatState
        self.captionText = captionText
        self.mediaData = mediaData
        self.catEmotionRaw = catEmotionRaw
        self.backgroundGradientIndex = backgroundGradientIndex
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.isSeen = isSeen
        self.isMine = isMine
    }
    
    public var isExpired: Bool {
        Date() > expiresAt
    }
    
    public var formattedTimeAgo: String {
        let diff = Date().timeIntervalSince(createdAt)
        let hours = Int(diff / 3600)
        if hours <= 0 {
            let minutes = max(1, Int(diff / 60))
            return "hace \(minutes)m"
        }
        return "hace \(hours)h"
    }
}
