import Foundation

/// The caller arbitrates one floor over an ordered, reliable WebRTC data channel.
/// UUIDs make delayed grants/releases harmless after a button has been released.
struct RadioTurnState {
    let isAuthority: Bool
    private(set) var requestID: String?
    private(set) var turnID: String?
    private(set) var transmitting = false
    private(set) var receiving = false
    private(set) var deadline: TimeInterval?

    mutating func request(now: TimeInterval) -> [String] {
        guard requestID == nil, turnID == nil, !receiving else { return [] }
        let id = UUID().uuidString
        requestID = id
        if isAuthority {
            turnID = id; transmitting = true; deadline = now + 60
            return ["remote|" + id]
        }
        deadline = now + 5
        return ["request|" + id]
    }
    mutating func stop() -> [String] {
        guard let id = requestID else { return [] }
        requestID = nil; transmitting = false
        if turnID == id { turnID = nil }
        if !receiving { deadline = nil }
        return [(isAuthority ? "idle|" : "release|") + id]
    }
    mutating func receive(_ text: String, now: TimeInterval) -> [String] {
        let parts = text.split(separator: "|").map(String.init)
        guard parts.count == 2, UUID(uuidString: parts[1]) != nil else { return [] }
        let command = parts[0], id = parts[1]
        if isAuthority {
            if command == "request" {
                guard turnID == nil else { return ["busy|" + id] }
                turnID = id; receiving = true; deadline = now + 60
                return ["grant|" + id]
            }
            if command == "release", turnID == id, receiving {
                turnID = nil; receiving = false; deadline = nil
                return ["idle|" + id]
            }
        } else {
            switch command {
            case "grant":
                guard requestID == id else { return ["release|" + id] }
                turnID = id; transmitting = true; receiving = false; deadline = now + 60
            case "remote":
                let messages = stop()
                turnID = id; receiving = true; deadline = now + 65
                return messages
            case "idle":
                guard turnID == id else { return [] }
                let messages = stop()
                turnID = nil; receiving = false; deadline = nil
                return messages
            case "busy":
                if requestID == id { return stop() }
            default: break
            }
        }
        return []
    }
    mutating func expire(now: TimeInterval) -> [String] {
        guard let deadline, now >= deadline else { return [] }
        let previous = turnID
        var messages = stop()
        if isAuthority, let previous, receiving { messages.append("idle|" + previous) }
        turnID = nil; receiving = false; self.deadline = nil
        return messages
    }
    mutating func reset() { self = Self(isAuthority: isAuthority) }
}
