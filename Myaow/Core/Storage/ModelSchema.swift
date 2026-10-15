//
//  ModelSchema.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation
import SwiftData

@Model
public final class ContactModel {
    @Attribute(.unique) public var id: String = UUID().uuidString
    public var myaowId: String = ""
    public var did: String = ""
    public var displayName: String = ""
    public var avatarCatState: String = "Neutro"
    public var avatarTypeRaw: String = "cat"
    public var avatarUrl: String? = nil
    public var isMeshNearby: Bool = true
    public var isVerified: Bool = true
    public var lastSeenDate: Date = Date()
    public var publicKeyHex: String = ""
    public var allowsLocalRadio: Bool = false
    public var radioAuthorizationOwnerId: String = ""
    
    public init(
        id: String = UUID().uuidString,
        myaowId: String,
        did: String,
        displayName: String,
        avatarCatState: String = "Neutro",
        avatarTypeRaw: String = "cat",
        avatarUrl: String? = nil,
        isMeshNearby: Bool = true,
        isVerified: Bool = true,
        lastSeenDate: Date = Date(),
        publicKeyHex: String = ""
    ) {
        self.id = id
        self.myaowId = myaowId
        self.did = did
        self.displayName = displayName
        self.avatarCatState = avatarCatState
        self.avatarTypeRaw = avatarTypeRaw
        self.avatarUrl = avatarUrl
        self.isMeshNearby = isMeshNearby
        self.isVerified = isVerified
        self.lastSeenDate = lastSeenDate
        self.publicKeyHex = publicKeyHex
    }
}

@Model
public final class ConversationModel {
    public var sharedDecorationJSON: String? = nil
    public var localDecorationRaw: String? = nil
    @Attribute(.unique) public var id: String = UUID().uuidString
    public var title: String = ""
    public var recipientMyaowId: String = ""
    public var isGroup: Bool = false
    public var unreadCount: Int = 0
    public var lastMessageSnippet: String = ""
    public var lastMessageTimestamp: Date = Date()
    public var isMeshConnected: Bool = true
    public var nodeCount: Int = 1
    public var participantNames: [String] = []
    
    @Relationship(deleteRule: .cascade)
    public var messages: [MessageModel] = []
    
    public init(
        id: String = UUID().uuidString,
        title: String,
        recipientMyaowId: String = "",
        isGroup: Bool = false,
        unreadCount: Int = 0,
        lastMessageSnippet: String = "",
        lastMessageTimestamp: Date = Date(),
        isMeshConnected: Bool = true,
        nodeCount: Int = 1,
        participantNames: [String] = []
    ) {
        self.id = id
        self.title = title
        self.recipientMyaowId = recipientMyaowId
        self.isGroup = isGroup
        self.unreadCount = unreadCount
        self.lastMessageSnippet = lastMessageSnippet
        self.lastMessageTimestamp = lastMessageTimestamp
        self.isMeshConnected = isMeshConnected
        self.nodeCount = nodeCount
        self.participantNames = participantNames
    }
    
    public var pinnedMessages: [MessageModel] {
        messages.filter { $0.isPinned }.sorted { ($0.pinnedTimestamp ?? $0.timestamp) > ($1.pinnedTimestamp ?? $1.timestamp) }
    }
}

@Model
public final class MessageModel {
    public var decorationJSON: String? = nil
    @Attribute(.unique) public var id: String = UUID().uuidString
    public var conversationId: String = ""
    public var senderId: String = ""
    public var senderName: String = ""
    public var isOutgoing: Bool = false
    public var text: String = ""
    public var timestamp: Date = Date()
    
    // Entrega: queued, sending, sent, delivered, read
    public var deliveryStatusRaw: String = "delivered"
    
    // Tipo: text, image, video, rawFile, handshake
    public var messageTypeRaw: String = "text"
    public var mediaData: Data? = nil
    
    // Moderación IA Local: approved, blurred, blocked
    public var moderationStatusRaw: String = "approved"
    public var moderationReason: String? = nil
    public var isContentRevealedByConsent: Bool = false
    
    // Mensajes Anclados & Baúl Seguro (Pins & Vault)
    public var isPinned: Bool = false
    public var isSavedToVault: Bool = false
    public var pinnedTimestamp: Date? = nil
    public var pinCategory: String? = nil
    public var isEdited: Bool = false
    public var replyToId: String? = nil
    public var replyToText: String? = nil
    public var replyToSender: String? = nil
    /// Shared reference inside the encrypted group envelope; delivery IDs remain per recipient.
    public var groupMessageId: String? = nil
    public var reactionsJSON: String? = nil // JSON string: {"emoji": ["senderId1", "senderId2"]}
    
    public var taskTitle: String? = nil
    public var taskAssignee: String? = nil  
    public var taskDueLabel: String? = nil
    public var taskIsCompleted: Bool = false
    public var taskCompletedBy: String? = nil
    
    public init(
        id: String = UUID().uuidString,
        conversationId: String,
        senderId: String,
        senderName: String,
        isOutgoing: Bool,
        text: String,
        timestamp: Date = Date(),
        deliveryStatusRaw: String = "delivered",
        messageTypeRaw: String = "text",
        mediaData: Data? = nil,
        moderationStatusRaw: String = "approved",
        moderationReason: String? = nil,
        isContentRevealedByConsent: Bool = false,
        isPinned: Bool = false,
        isSavedToVault: Bool = false,
        pinnedTimestamp: Date? = nil,
        pinCategory: String? = nil,
        isEdited: Bool = false,
        replyToId: String? = nil,
        replyToText: String? = nil,
        replyToSender: String? = nil,
        reactionsJSON: String? = nil,
        taskTitle: String? = nil,
        taskAssignee: String? = nil,
        taskDueLabel: String? = nil,
        taskIsCompleted: Bool = false,
        taskCompletedBy: String? = nil
    ) {
        self.id = id
        self.conversationId = conversationId
        self.senderId = senderId
        self.senderName = senderName
        self.isOutgoing = isOutgoing
        self.text = text
        self.timestamp = timestamp
        self.deliveryStatusRaw = deliveryStatusRaw
        self.messageTypeRaw = messageTypeRaw
        self.mediaData = mediaData
        self.moderationStatusRaw = moderationStatusRaw
        self.moderationReason = moderationReason
        self.isContentRevealedByConsent = isContentRevealedByConsent
        self.isPinned = isPinned
        self.isSavedToVault = isSavedToVault
        self.pinnedTimestamp = pinnedTimestamp
        self.pinCategory = pinCategory
        self.isEdited = isEdited
        self.replyToId = replyToId
        self.replyToText = replyToText
        self.replyToSender = replyToSender
        self.reactionsJSON = reactionsJSON
        self.taskTitle = taskTitle
        self.taskAssignee = taskAssignee
        self.taskDueLabel = taskDueLabel
        self.taskIsCompleted = taskIsCompleted
        self.taskCompletedBy = taskCompletedBy
    }
    
    public var deliveryStatus: MessageDeliveryStatus {
        get { MessageDeliveryStatus(rawValue: deliveryStatusRaw) ?? .delivered }
        set { deliveryStatusRaw = newValue.rawValue }
    }
}

@Model
public final class MeshNodeModel {
    @Attribute(.unique) public var peerId: String = ""
    public var myaowId: String = ""
    public var displayName: String = ""
    public var signalStrength: Double = 0.9
    public var isConnected: Bool = true
    public var lastSeen: Date = Date()
    public var hopsCount: Int = 1
    
    public init(
        peerId: String,
        myaowId: String,
        displayName: String,
        signalStrength: Double = 0.9,
        isConnected: Bool = true,
        lastSeen: Date = Date(),
        hopsCount: Int = 1
    ) {
        self.peerId = peerId
        self.myaowId = myaowId
        self.displayName = displayName
        self.signalStrength = signalStrength
        self.isConnected = isConnected
        self.lastSeen = lastSeen
        self.hopsCount = hopsCount
    }
}

extension MessageModel {
    var parsedReactions: [String: [String]]? {
        guard let json = reactionsJSON,
              let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return nil }
        return dict
    }
}
