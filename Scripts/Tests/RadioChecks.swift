import Foundation

@main struct RadioChecks {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); count += 1
        }
        let stream = UUID()
        let audio = RadioPacket(.audio, channel: 1, stream: stream, sequence: 1, pcm: Data([0, 0, 255, 127]))
        check(RadioPacket.decode(try! JSONEncoder().encode(audio))?.pcm == audio.pcm, "PCM round trip")
        check(!RadioPacket(.audio, channel: 1, pcm: Data([1])).isValid, "Reject partial sample")
        check(!RadioPacket(.audio, channel: 1).isValid, "Reject empty audio")
        check(!RadioPacket(.audio, channel: 1, pcm: Data(repeating: 0, count: 2050)).isValid, "Bound frame size")
        check(!RadioPacket(.start, channel: 4).isValid, "Reject unknown channel")
        check(!RadioPacket(.start, channel: 1, pcm: Data([0, 0])).isValid, "Control cannot carry audio")
        check(RadioPacket.decode(Data(repeating: 65, count: 5000)) == nil, "Bound wire size")
        check(RadioPacket.decode(Data("{}".utf8)) == nil, "Reject malformed packet")
        let futureVersion = String(data: try JSONEncoder().encode(audio), encoding: .utf8)!.replacingOccurrences(of: "\"version\":1", with: "\"version\":2")
        check(RadioPacket.decode(Data(futureVersion.utf8)) == nil, "Reject unknown version")
        var gate = RadioReceiveGate()
        check(!gate.accept(audio, from: "B", channel: 1, now: 1), "Audio cannot open microphone stream")
        check(gate.accept(RadioPacket(.start, channel: 1, stream: stream), from: "B", channel: 1, now: 1), "Announce stream")
        check(!gate.accept(audio, from: "B", channel: 2, now: 1.1), "Channel isolation")
        check(!gate.accept(audio, from: "A", channel: 1, now: 1.1), "Peer binding")
        check(!gate.accept(RadioPacket(.audio, channel: 1, pcm: Data([0, 0])), from: "B", channel: 1, now: 1.1), "Stream binding")
        check(gate.accept(audio, from: "B", channel: 1, now: 1.1), "Accept announced audio")
        check(!gate.accept(audio, from: "B", channel: 1, now: 1.2), "Drop duplicate")
        check(!gate.accept(RadioPacket(.audio, channel: 1, stream: stream, sequence: 0, pcm: audio.pcm), from: "B", channel: 1, now: 1.2), "Drop out-of-order frame")
        check(!gate.accept(RadioPacket(.start, channel: 1), from: "C", channel: 1, now: 1.2), "One speaker")
        let winner = UUID()
        check(gate.accept(RadioPacket(.start, channel: 1, stream: winner), from: "A", channel: 1, now: 1.2), "Deterministic simultaneous speaker priority")
        check(!gate.accept(audio, from: "B", channel: 1, now: 1.3), "Previous speaker discarded")
        check(!gate.accept(RadioPacket(.end, channel: 1, stream: stream), from: "B", channel: 1, now: 1.3), "Unrelated end ignored")
        check(gate.accept(RadioPacket(.end, channel: 1, stream: winner), from: "A", channel: 1, now: 1.3), "Speaker releases floor")
        check(gate.peer == nil, "End clears receiver")
        check(!gate.accept(audio, from: "B", channel: 1, now: 1.4), "Late audio discarded")
        check(gate.accept(RadioPacket(.start, channel: 1, stream: stream), from: "B", channel: 1, now: 2), "New transmission")
        check(gate.expire(now: 4), "Lost end expires")
        check(gate.peer == nil, "Timeout releases floor")
        _ = gate.accept(RadioPacket(.start, channel: 1, stream: stream), from: "B", channel: 1, now: 5)
        for i in 1...60 {
            _ = gate.accept(RadioPacket(.audio, channel: 1, stream: stream, sequence: UInt32(i), pcm: audio.pcm), from: "B", channel: 1, now: 5 + Double(i))
        }
        check(gate.expire(now: 65.1), "Hard 60-second limit even with continuous frames")
        print("PASS: \(count) local Radio protocol checks")
    }
}
