import Foundation

nonisolated enum VideoCallFilterType: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal, catverse, pocketCat, livingInk, duoPortal
    var id: String { rawValue }
    var title: String {
        switch self {
        case .normal: "Natural"
        case .catverse: "Gatoverso"
        case .pocketCat: "Gato de bolsillo"
        case .livingInk: "Tinta viva"
        case .duoPortal: "Portal a dúo"
        }
    }
    var subtitle: String {
        switch self {
        case .normal: "Tu cámara, sin efecto."
        case .catverse: "Un gato ilustrado sigue tu cabeza, tus ojos y tu boca."
        case .pocketCat: "Un pequeño compañero se asoma junto a tu rostro."
        case .livingInk: "Tu video se convierte en una viñeta de papel y tinta."
        case .duoPortal: "Invita a tu contacto y envíense pequeñas sorpresas."
        }
    }
    var iconName: String {
        switch self {
        case .normal: "video"
        case .catverse: "cat.fill"
        case .pocketCat: "pawprint.fill"
        case .livingInk: "paintbrush.pointed.fill"
        case .duoPortal: "sparkles"
        }
    }
}

nonisolated struct VideoFilterSettings: Equatable, Sendable {
    var type: VideoCallFilterType = .normal
    var intensity: Double = 0.7
    var reducedMotion = false
}

nonisolated enum PortalGift: String, CaseIterable, Codable, Sendable {
    case star, fish, cat
    var title: String { switch self { case .star: "Estrella"; case .fish: "Pez"; case .cat: "Gatito" } }
    var symbol: String { switch self { case .star: "★"; case .fish: "🐟"; case .cat: "🐱" } }
}

/// Versioned, bounded messages travel only on this call's WebRTC data channel.
nonisolated struct PortalMessage: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case invite, accept, decline, cancel, gift }
    var version = 1
    var kind: Kind
    var invitation: UUID
    var event = UUID()
    var gift: PortalGift?
    var data: Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> Self? {
        guard data.count <= 512, let message = try? JSONDecoder().decode(Self.self, from: data), message.version == 1,
              (message.kind == .gift) == (message.gift != nil) else { return nil }
        return message
    }
}

nonisolated struct PortalSession: Sendable {
    enum Phase: Equatable, Sendable { case idle, inviting(UUID), invited(UUID), connected(UUID) }
    private(set) var phase: Phase = .idle
    private(set) var deadline: TimeInterval = 0
    private var seen = Set<UUID>()
    private var lastGift: TimeInterval = -.infinity
    var id: UUID? { switch phase { case .idle: nil; case .inviting(let id), .invited(let id), .connected(let id): id } }
    var connected: Bool { if case .connected = phase { true } else { false } }
    mutating func invite(now: TimeInterval) -> PortalMessage? {
        guard phase == .idle else { return nil }
        let id = UUID(); phase = .inviting(id); deadline = now + 30
        return PortalMessage(kind: .invite, invitation: id)
    }
    mutating func answer(accept: Bool, now: TimeInterval) -> PortalMessage? {
        guard case .invited(let id) = phase else { return nil }
        let accepted = accept && now < deadline
        phase = accepted ? .connected(id) : .idle
        return PortalMessage(kind: accepted ? .accept : .decline, invitation: id)
    }
    mutating func cancel() -> PortalMessage? {
        guard let id else { return nil }; phase = .idle
        return PortalMessage(kind: .cancel, invitation: id)
    }
    mutating func expire(now: TimeInterval) -> PortalMessage? {
        guard !connected, phase != .idle, now >= deadline else { return nil }; return cancel()
    }
    mutating func send(_ gift: PortalGift, now: TimeInterval) -> PortalMessage? {
        guard connected, let id, now - lastGift >= 1 else { return nil }
        lastGift = now; return PortalMessage(kind: .gift, invitation: id, gift: gift)
    }
    /// Returns a valid incoming gift and/or a response. Unsolicited gifts never render.
    mutating func receive(_ message: PortalMessage, now: TimeInterval) -> (gift: PortalGift?, reply: PortalMessage?) {
        guard message.version == 1, !seen.contains(message.event) else { return (nil, nil) }
        if seen.count >= 128 { seen.removeAll(keepingCapacity: true) }
        seen.insert(message.event)
        switch message.kind {
        case .invite:
            guard phase == .idle else { return (nil, PortalMessage(kind: .decline, invitation: message.invitation)) }
            phase = .invited(message.invitation); deadline = now + 30
        case .accept:
            guard phase == .inviting(message.invitation), now < deadline else { return (nil, nil) }
            phase = .connected(message.invitation)
        case .decline, .cancel:
            if id == message.invitation { phase = .idle }
        case .gift:
            guard phase == .connected(message.invitation), now - lastGift >= 0.8 else { return (nil, nil) }
            lastGift = now; return (message.gift, nil)
        }
        return (nil, nil)
    }
}
