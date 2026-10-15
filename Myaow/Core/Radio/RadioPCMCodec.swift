import AVFAudio
import Foundation

/// Shared by capture, playback and the offline audio regression checks.
nonisolated enum RadioPCMCodec {
    static let sampleRate: Double = 16_000
    static func format() -> AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)! }

    static func encode(_ buffer: AVAudioPCMBuffer) -> (data: Data, level: Float)? {
        guard buffer.format.sampleRate == sampleRate, buffer.format.channelCount == 1,
              buffer.frameLength > 0, buffer.frameLength <= 1024,
              let samples = buffer.floatChannelData?[0] else { return nil }
        var data = Data(capacity: Int(buffer.frameLength) * 2)
        var energy: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let value = samples[index].isFinite ? max(-1, min(1, samples[index])) : 0
            energy += value * value
            let sample = UInt16(bitPattern: Int16(value * 32767))
            data.append(UInt8(truncatingIfNeeded: sample)); data.append(UInt8(truncatingIfNeeded: sample >> 8))
        }
        return (data, min(1, sqrt(energy / Float(buffer.frameLength)) * 5))
    }

    static func decode(_ data: Data) -> (buffer: AVAudioPCMBuffer, level: Float)? {
        guard !data.isEmpty, data.count <= 2048, data.count.isMultiple(of: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format(), frameCapacity: AVAudioFrameCount(data.count / 2)),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = buffer.frameCapacity
        let bytes = [UInt8](data); var energy: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let sample = Int16(bitPattern: UInt16(bytes[index * 2]) | UInt16(bytes[index * 2 + 1]) << 8)
            let value = Float(sample) / 32768; samples[index] = value; energy += value * value
        }
        return (buffer, min(1, sqrt(energy / Float(buffer.frameLength)) * 5))
    }
}
