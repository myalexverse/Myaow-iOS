import Foundation
import AVFAudio

@main struct RadioAudioChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); checks += 1
        }
        for rate in [44_100.0, 48_000.0] {
            let source = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
            let converter = AVAudioConverter(from: source, to: RadioPCMCodec.format())!
            var frames = 0
            for packet in 0..<20 {
                let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 1024)!
                input.frameLength = 1024
                for channel in 0..<2 {
                    for index in 0..<1024 {
                        input.floatChannelData![channel][index] = Float(sin(2 * Double.pi * 440 * Double(packet * 1024 + index) / rate)) * 0.3
                    }
                }
                let output = AVAudioPCMBuffer(pcmFormat: RadioPCMCodec.format(), frameCapacity: 1024)!
                var supplied = false; var error: NSError?
                converter.convert(to: output, error: &error) { _, status in
                    if supplied { status.pointee = .noDataNow; return nil }
                    supplied = true; status.pointee = .haveData; return input
                }
                check(error == nil, "Resample microphone format")
                guard let encoded = RadioPCMCodec.encode(output), let decoded = RadioPCMCodec.decode(encoded.data) else { fatalError("PCM failed") }
                check(decoded.buffer.frameLength == output.frameLength, "Preserve sample count")
                check(encoded.data.count <= 2048 && encoded.level > 0, "Bounded real meter")
                for index in 0..<Int(output.frameLength) {
                    check(abs(output.floatChannelData![0][index] - decoded.buffer.floatChannelData![0][index]) < 0.0001, "Audio round trip fidelity")
                }
                frames += Int(output.frameLength)
                // Render the actual receive buffer through AVAudioPlayerNode, without speakers or microphone.
                let engine = AVAudioEngine(); let player = AVAudioPlayerNode()
                engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: RadioPCMCodec.format())
                try engine.enableManualRenderingMode(.offline, format: RadioPCMCodec.format(), maximumFrameCount: 1024)
                player.scheduleBuffer(decoded.buffer); try engine.start(); player.play()
                let rendered = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 1024)!
                let result = try engine.renderOffline(decoded.buffer.frameLength, to: rendered)
                check(result == .success && rendered.frameLength == decoded.buffer.frameLength, "Player renders framed PCM")
                let peak = (0..<Int(rendered.frameLength)).map { abs(rendered.floatChannelData![0][$0]) }.max()!
                check(peak > 0.1, "Rendered output contains the test tone")
                engine.stop()
            }
            let expected = 20 * 1024 * 16_000 / rate
            check(abs(Double(frames) - expected) < 100, "Correct duration after rate conversion")
        }
        let invalid = AVAudioPCMBuffer(pcmFormat: RadioPCMCodec.format(), frameCapacity: 3)!
        invalid.frameLength = 3
        invalid.floatChannelData![0][0] = .nan; invalid.floatChannelData![0][1] = .infinity; invalid.floatChannelData![0][2] = -2
        check(RadioPCMCodec.encode(invalid)?.data == Data([0, 0, 0, 0, 1, 128]), "Nonfinite samples are safe and peaks clip")
        check(RadioPCMCodec.decode(Data([0])) == nil, "Incomplete PCM rejected")
        print("PASS: \(checks) Radio audio assertions, 44.1/48 kHz stereo → PCM16 mono → real offline player render")
    }
}
