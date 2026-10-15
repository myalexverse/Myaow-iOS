//
//  MeshNetworkService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import MultipeerConnectivity

public struct MeshDataPacket: Codable, Sendable {
    public enum PacketType: String, Codable, Sendable {
        case message
        case deliveryAck
        case handshakeRequest
        case handshakeAccept
        case ping
    }
    
    public let id: String
    public let type: PacketType
    public let senderMyaowId: String
    public let recipientMyaowId: String
    public let payload: String
    public let timestamp: Date
}

@MainActor
@Observable
public final class MeshNetworkService: NSObject {
    public static let shared = MeshNetworkService()
    
    public private(set) var localPeerID: MCPeerID
    public var connectedPeers: [MeshPeer] = []
    public var discoveredPeers: [MeshPeer] = []
    public var isAdvertising: Bool = false
    public var isBrowsing: Bool = false
    public var totalNodesCount: Int { connectedPeers.count + discoveredPeers.count }
    public var allRadarPeers: [MeshPeer] {
        var peers = connectedPeers
        for p in discoveredPeers where !peers.contains(where: { $0.myaowId == p.myaowId }) {
            peers.append(p)
        }
        return peers
    }
    
    private let serviceType = "myaow-mesh"
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    
    public override init() {
        let identity = IdentityManager.shared.currentIdentity
        self.localPeerID = MCPeerID(displayName: "\(identity.displayName) (\(identity.myaowId))")
        super.init()
        setupMultipeer()
    }
    
    public func startMeshServices() {
        guard !isAdvertising && !isBrowsing else { return }
        advertiser?.startAdvertisingPeer()
        browser?.startBrowsingForPeers()
        isAdvertising = true
        isBrowsing = true
    }
    
    public func stopMeshServices() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        isAdvertising = false
        isBrowsing = false
    }
    
    private func setupMultipeer() {
        let session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        
        let discoveryInfo = [
            "myaowId": IdentityManager.shared.currentIdentity.myaowId,
            "did": IdentityManager.shared.currentIdentity.did
        ]
        
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: discoveryInfo,
            serviceType: serviceType
        )
        self.advertiser?.delegate = self
        
        self.browser = MCNearbyServiceBrowser(
            peer: localPeerID,
            serviceType: serviceType
        )
        self.browser?.delegate = self
    }
    
    /// Envía un paquete de datos a todos los peers o a uno en específico
    public func broadcastPacket(_ packet: MeshDataPacket) {
        guard let session = session, !session.connectedPeers.isEmpty else { return }
        if let data = try? JSONEncoder().encode(packet) {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        }
    }
}

// MARK: - MCSessionDelegate
extension MeshNetworkService: MCSessionDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                let peer = MeshPeer(peerID: peerID, displayName: peerID.displayName, status: .connected)
                if !self.connectedPeers.contains(where: { $0.peerID == peerID }) {
                    self.connectedPeers.append(peer)
                }
            case .connecting:
                break
            case .notConnected:
                self.connectedPeers.removeAll(where: { $0.peerID == peerID })
            @unknown default:
                break
            }
        }
    }
    
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let packet = try? JSONDecoder().decode(MeshDataPacket.self, from: data) {
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .didReceiveMeshPacket,
                    object: packet
                )
            }
        }
    }
    
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension MeshNetworkService: MCNearbyServiceAdvertiserDelegate {
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, self.session)
    }
    
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.isAdvertising = false
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension MeshNetworkService: MCNearbyServiceBrowserDelegate {
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        Task { @MainActor in
            let myaowId = info?["myaowId"] ?? "MYAOW-PEER"
            let peer = MeshPeer(peerID: peerID, myaowId: myaowId, displayName: peerID.displayName, status: .notConnected)
            if !self.discoveredPeers.contains(where: { $0.peerID == peerID }) {
                self.discoveredPeers.append(peer)
            }
            if let session = self.session {
                browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
            }
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredPeers.removeAll(where: { $0.peerID == peerID })
        }
    }
    
    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.isBrowsing = false
        }
    }
}

public extension Notification.Name {
    static let didReceiveMeshPacket = Notification.Name("didReceiveMeshPacket")
}
