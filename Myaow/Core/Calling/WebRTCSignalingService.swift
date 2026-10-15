//
//  WebRTCSignalingService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum WebRTCSignalingType: String, Codable, Sendable {
    case offer = "webrtc_offer"
    case answer = "webrtc_answer"
    case iceCandidate = "webrtc_ice_candidate"
    case hangup = "webrtc_hangup"
}

public struct WebRTCSignalingPacket: Codable, Sendable {
    public let type: WebRTCSignalingType
    public let senderMyaowId: String
    public let targetMyaowId: String
    public let sdpOrCandidate: String
    public let timestamp: Date
}

@MainActor
@Observable
public final class WebRTCSignalingService {
    public static let shared = WebRTCSignalingService()
    
    public var isSignalingReady: Bool = true
    public var iceServers: [String] = [
        "stun:stun.l.google.com:19302",
        "stun:stun1.l.google.com:19302",
        "stun:stun.cloudflare.com:3478"
    ]
    
    public var onIncomingOffer: ((String, String) -> Void)? // (senderId, sdp)
    public var onIncomingAnswer: ((String, String) -> Void)?
    public var onIncomingCandidate: ((String, String) -> Void)?
    public var onCallEndedByRemote: (() -> Void)?
    
    public init() {}
    
    /// Despacha una oferta SDP al contacto remoto a través del Relay WebSocket
    public func sendOffer(targetMyaowId: String, sdp: String) {
        let packet: [String: Any] = [
            "type": WebRTCSignalingType.offer.rawValue,
            "senderMyaowId": IdentityManager.shared.currentIdentity.myaowId,
            "targetMyaowId": targetMyaowId,
            "sdpOrCandidate": sdp,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        sendSignalingJSON(packet)
    }
    
    /// Despacha la respuesta SDP
    public func sendAnswer(targetMyaowId: String, sdp: String) {
        let packet: [String: Any] = [
            "type": WebRTCSignalingType.answer.rawValue,
            "senderMyaowId": IdentityManager.shared.currentIdentity.myaowId,
            "targetMyaowId": targetMyaowId,
            "sdpOrCandidate": sdp,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        sendSignalingJSON(packet)
    }
    
    /// Despacha un candidato ICE para atravesar NAT y Firewalls
    public func sendIceCandidate(targetMyaowId: String, candidate: String) {
        let packet: [String: Any] = [
            "type": WebRTCSignalingType.iceCandidate.rawValue,
            "senderMyaowId": IdentityManager.shared.currentIdentity.myaowId,
            "targetMyaowId": targetMyaowId,
            "sdpOrCandidate": candidate,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        sendSignalingJSON(packet)
    }
    
    /// Notifica el fin de la llamada
    public func sendHangup(targetMyaowId: String) {
        let packet: [String: Any] = [
            "type": WebRTCSignalingType.hangup.rawValue,
            "senderMyaowId": IdentityManager.shared.currentIdentity.myaowId,
            "targetMyaowId": targetMyaowId,
            "sdpOrCandidate": "",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        sendSignalingJSON(packet)
    }
    
    private func sendSignalingJSON(_ dictionary: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary),
              let string = String(data: data, encoding: .utf8) else { return }
        // Enviar por WebSocket real
        OnlineMessagingService.shared.sendRawJSON(string)
        print("📡 [WebRTC Signaling] Paquete enviado al Relay")
    }
}
