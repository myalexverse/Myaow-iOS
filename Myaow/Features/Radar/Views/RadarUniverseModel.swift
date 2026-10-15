//
//  RadarUniverseModel.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum UniverseConnectionType: String, CaseIterable, Identifiable, Sendable {
    case localMeshOffline = "Mesh Local (Sin Internet)"
    case internetRelay = "Relay E2EE por Internet"
    case offline = "Fuera de Línea"
    
    public var id: String { rawValue }
    
    public var orbitRadiusFraction: CGFloat {
        switch self {
        case .localMeshOffline: return 0.42
        case .internetRelay: return 0.72
        case .offline: return 0.94
        }
    }
    
    public var badgeColor: Color {
        switch self {
        case .localMeshOffline: return MyaowColor.statusGreen
        case .internetRelay: return MyaowColor.orange
        case .offline: return Color(hex: "#636366")
        }
    }
}

public struct UniverseContactNode: Identifiable, Sendable {
    public var id: String { myaowId }
    public let displayName: String
    public let myaowId: String
    public let avatarState: MyaowCatState
    public let moodDescription: String
    public let connectionType: UniverseConnectionType
    public let angleDegrees: Double
    public let signalStrength: Int
    public let orbitRadiusFraction: CGFloat
    
    public init(
        displayName: String,
        myaowId: String,
        avatarState: MyaowCatState,
        moodDescription: String,
        connectionType: UniverseConnectionType,
        angleDegrees: Double,
        signalStrength: Int = 90,
        orbitRadiusFraction: CGFloat
    ) {
        self.displayName = displayName
        self.myaowId = myaowId
        self.avatarState = avatarState
        self.moodDescription = moodDescription
        self.connectionType = connectionType
        self.angleDegrees = angleDegrees
        self.signalStrength = signalStrength
        self.orbitRadiusFraction = orbitRadiusFraction
    }
    
    public static func buildFrom(contacts: [ContactModel], meshPeers: [MeshPeer], onlineIds: Set<String>) -> [UniverseContactNode] {
        var nodes: [UniverseContactNode] = []
        var processedIds = Set<String>()
        
        var currentIndex = 0
        let totalMesh = max(1, meshPeers.count)
        
        // 1. Pares descubiertos por la red Mesh Local P2P
        for peer in meshPeers {
            guard !peer.myaowId.isEmpty && !processedIds.contains(peer.myaowId) else { continue }
            processedIds.insert(peer.myaowId)
            
            // Recency score always 1 for local mesh since they are discovered live
            let idHash = abs(peer.myaowId.hashValue)
            let jitter = Double(idHash % 30) - 15.0
            let baseAngle = (Double(currentIndex) / Double(totalMesh)) * 360.0
            let angle = baseAngle + jitter + 45.0
            
            let signalStrength = 90 + Int.random(in: 0...10)
            
            let mood = MyaowCatState(rawValue: peer.avatarState) ?? .friendly
            nodes.append(
                UniverseContactNode(
                    displayName: peer.displayName,
                    myaowId: peer.myaowId,
                    avatarState: mood,
                    moodDescription: mood.displayName,
                    connectionType: .localMeshOffline,
                    angleDegrees: angle,
                    signalStrength: signalStrength,
                    orbitRadiusFraction: 0.25 + (1.0 - 1.0) * 0.20
                )
            )
            currentIndex += 1
        }
        
        // 2. Contactos registrados reales
        let totalContacts = max(1, contacts.count)
        currentIndex = 0
        
        for contact in contacts {
            guard !contact.myaowId.isEmpty && !processedIds.contains(contact.myaowId) else { continue }
            processedIds.insert(contact.myaowId)
            
            let isContactOnline = onlineIds.contains(contact.myaowId)
            let connectionType: UniverseConnectionType = isContactOnline ? .internetRelay : .offline
            
            let minutesSinceLastInteraction = contact.lastSeenDate.timeIntervalSinceNow
            let recencyScore = max(0, min(1, 1.0 / (1.0 + abs(minutesSinceLastInteraction) / 3600))) // 0-1, 1=just now
            
            let idHash = abs(contact.myaowId.hashValue)
            let jitter = Double(idHash % 30) - 15.0 // -15 to +15 degrees jitter
            let baseAngle = (Double(currentIndex) / Double(totalContacts)) * 360.0
            let angle = baseAngle + jitter + 45.0
            
            let signalStrength: Int
            let orbitFraction: Double
            switch connectionType {
            case .localMeshOffline:
                signalStrength = 90 + Int.random(in: 0...10)
                orbitFraction = 0.25 + (1.0 - recencyScore) * 0.20
            case .internetRelay:
                signalStrength = Int(50 + recencyScore * 45) // 50-95
                orbitFraction = 0.45 + (1.0 - recencyScore) * 0.30
            case .offline:
                signalStrength = 0
                orbitFraction = 0.75 + (1.0 - recencyScore) * 0.20
            }
            
            let mood = MyaowCatState(rawValue: contact.avatarCatState) ?? .friendly
            
            nodes.append(
                UniverseContactNode(
                    displayName: contact.displayName,
                    myaowId: contact.myaowId,
                    avatarState: mood,
                    moodDescription: mood.displayName,
                    connectionType: connectionType,
                    angleDegrees: angle,
                    signalStrength: signalStrength,
                    orbitRadiusFraction: CGFloat(orbitFraction)
                )
            )
            currentIndex += 1
        }
        
        return nodes
    }
}
