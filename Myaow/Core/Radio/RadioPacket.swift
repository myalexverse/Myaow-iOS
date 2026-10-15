import Foundation

/// Local radio v1: mono, signed little-endian PCM16, 16 kHz. Never stored or relayed.
struct RadioPacket: Codable, Sendable {
    enum Kind: String, Codable, Sendable { case presence, start, audio, end }
    let version: Int
    let kind: Kind
    let channel: Int
    let stream: UUID
    let sequence: UInt32
    let pcm: Data

    init(_ kind: Kind, channel: Int, stream: UUID = UUID(), sequence: UInt32 = 0, pcm: Data = Data()) {
        self.version = 1; self.kind = kind; self.channel = channel
        self.stream = stream; self.sequence = sequence; self.pcm = pcm
    }
    var isValid: Bool {
        version == 1 && (1...3).contains(channel) &&
        (kind == .audio ? (!pcm.isEmpty && pcm.count <= 2048 && pcm.count.isMultiple(of: 2)) : pcm.isEmpty)
    }
    static func decode(_ data: Data) -> RadioPacket? {
        guard data.count <= 4096, let value = try? JSONDecoder().decode(Self.self, from: data), value.isValid else { return nil }
        return value
    }
}

/// A receiver accepts only an announced stream and strictly increasing frames.
/// The transport supplies the peer identity; the payload cannot impersonate it.
struct RadioReceiveGate {
    private(set) var peer: String?
    private(set) var stream: UUID?
    private var sequence: UInt32?
    private var lastFrame: TimeInterval = 0
    private var started: TimeInterval = 0

    mutating func accept(_ packet: RadioPacket, from sender: String, channel: Int, now: TimeInterval) -> Bool {
        guard packet.isValid, packet.channel == channel else { return false }
        if now - lastFrame > 1.5 || now - started > 60 { reset() }
        switch packet.kind {
        case .presence: return false
        case .start:
            guard peer == nil || (peer != sender && sender < peer!) else { return false }
            peer = sender; stream = packet.stream; sequence = nil; lastFrame = now; started = now
            return true
        case .audio:
            guard peer == sender, stream == packet.stream,
                  sequence.map({ packet.sequence > $0 }) ?? true else { return false }
            sequence = packet.sequence; lastFrame = now
            return true
        case .end:
            guard peer == sender, stream == packet.stream else { return false }
            reset(); return true
        }
    }
    mutating func expire(now: TimeInterval) -> Bool {
        guard peer != nil, now - lastFrame > 1.5 || now - started > 60 else { return false }
        reset(); return true
    }
    mutating func reset() { peer = nil; stream = nil; sequence = nil }
}
