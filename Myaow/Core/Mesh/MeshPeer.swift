//
//  MeshPeer.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import Foundation
import MultipeerConnectivity

public enum MeshConnectionStatus: String, Sendable {
    case notConnected
    case connecting
    case connected
}

public struct MeshPeer: Identifiable, Hashable, Sendable {
    public var id: String { peerID.displayName }
    public let peerID: MCPeerID
    public var myaowId: String
    public var displayName: String
    public var status: MeshConnectionStatus
    public var signalStrength: Double // 0.0 a 1.0
    public var angle: Double          // Posición orbital en el radar (grados 0 a 360)
    public var distanceRadius: Double // Distancia al centro en el radar (0.3 a 0.9)
    public var avatarState: String
    
    public init(
        peerID: MCPeerID,
        myaowId: String = "MYAOW-NODE",
        displayName: String,
        status: MeshConnectionStatus = .connected,
        signalStrength: Double = 0.85,
        angle: Double = Double.random(in: 0...360),
        distanceRadius: Double = Double.random(in: 0.35...0.85),
        avatarState: String = "Neutro"
    ) {
        self.peerID = peerID
        self.myaowId = myaowId
        self.displayName = displayName
        self.status = status
        self.signalStrength = signalStrength
        self.angle = angle
        self.distanceRadius = distanceRadius
        self.avatarState = avatarState
    }
}
