import AVFoundation
import SwiftUI

@MainActor
public final class SciFiSoundEngine {
    public static let shared = SciFiSoundEngine()
    
    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    public enum SciFiSound: String, CaseIterable, Sendable {
        case laserBlast = "Laser Blast"          // pew pew
        case spaceshipWarp = "Warp Drive"         // rising whoosh
        case godzillaRoar = "Roar Titánico"       // deep growl
        case retroAlarm = "Alarma Retro"          // ay ay ay pirate phone
        case photonTorpedo = "Torpedeo Fotónico"  // Star Trek style
        case lightsaber = "Sable de Luz"          // bzzzz
        case teleport = "Teletransporte"          // shimmer
        case robotVoice = "Robot Myaow"           // beep boop
        case alienPurr = "Ronroneo Alien"         // weird purr
        case hyperdrive = "Hyperdrives"           // deep bass whoosh
        
        public var emoji: String {
            switch self {
            case .laserBlast: return "⚡"
            case .spaceshipWarp: return "🚀"
            case .godzillaRoar: return "🦖"
            case .retroAlarm: return "📞"
            case .photonTorpedo: return "💫"
            case .lightsaber: return "⚔️"
            case .teleport: return "✨"
            case .robotVoice: return "🤖"
            case .alienPurr: return "👽"
            case .hyperdrive: return "🌀"
            }
        }
    }
    
    private var playbackFormat: AVAudioFormat?
    
    private init() {
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        let mixerFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        // Use the mixer's format so channel counts always match
        playbackFormat = AVAudioFormat(standardFormatWithSampleRate: mixerFormat.sampleRate, channels: mixerFormat.channelCount)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)
    }
    
    public func playSound(_ sound: SciFiSound) {
        Task.detached { [weak self] in
            guard let self = self else { return }
            let sampleRate: Double = await MainActor.run { self.playbackFormat?.sampleRate ?? 44100 }
            let buffer: AVAudioPCMBuffer
            
            switch sound {
            case .laserBlast:
                buffer = self.generateSweep(from: 2000, to: 200, duration: 0.3, sampleRate: sampleRate)
            case .spaceshipWarp:
                buffer = self.generateSweep(from: 100, to: 3000, duration: 0.8, sampleRate: sampleRate)
            case .godzillaRoar:
                buffer = self.generateGrowl(baseFreq: 60, duration: 1.2, sampleRate: sampleRate)
            case .retroAlarm:
                buffer = self.generateAlarm(freq1: 800, freq2: 1200, duration: 0.6, sampleRate: sampleRate)
            case .photonTorpedo:
                buffer = self.generateSweep(from: 400, to: 1800, duration: 0.4, sampleRate: sampleRate)
            case .lightsaber:
                buffer = self.generateBuzz(baseFreq: 120, duration: 0.7, sampleRate: sampleRate)
            case .teleport:
                buffer = self.generateShimmer(duration: 0.5, sampleRate: sampleRate)
            case .robotVoice:
                buffer = self.generateRobotBeep(duration: 0.4, sampleRate: sampleRate)
            case .alienPurr:
                buffer = self.generateGrowl(baseFreq: 35, duration: 1.0, sampleRate: sampleRate)
            case .hyperdrive:
                buffer = self.generateSweep(from: 40, to: 2500, duration: 1.0, sampleRate: sampleRate)
            }
            
            await MainActor.run {
                do {
                    if !self.audioEngine.isRunning {
                        try self.audioEngine.start()
                    }
                    
                    // Convert mono buffer to match mixer format (stereo)
                    let finalBuffer: AVAudioPCMBuffer
                    if let fmt = self.playbackFormat, fmt.channelCount != buffer.format.channelCount {
                        let converted = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: buffer.frameLength)!
                        converted.frameLength = buffer.frameLength
                        guard let monoChannelData = buffer.floatChannelData else { return }
                        let monoData = monoChannelData[0]
                        for ch in 0..<Int(fmt.channelCount) {
                            guard let convChannelData = converted.floatChannelData else { return }
                            let chData = convChannelData[ch]
                            for i in 0..<Int(buffer.frameLength) {
                                chData[i] = monoData[i]
                            }
                        }
                        finalBuffer = converted
                    } else {
                        finalBuffer = buffer
                    }
                    
                    self.playerNode.stop()
                    self.playerNode.scheduleBuffer(finalBuffer, at: nil, options: .interrupts)
                    self.playerNode.play()
                } catch {
                    print("❌ [SciFi] Error: \(error)")
                }
            }
        }
    }
    
    // MARK: - Sound Generators
    
    nonisolated private func generateSweep(from startFreq: Double, to endFreq: Double, duration: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return buffer }
        let data = channelData[0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let freq = startFreq + (endFreq - startFreq) * progress
            let envelope = sin(Double.pi * progress) // fade in/out
            data[i] = Float(sin(2.0 * Double.pi * freq * t) * envelope * 0.4)
        }
        return buffer
    }
    
    nonisolated private func generateGrowl(baseFreq: Double, duration: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return buffer }
        let data = channelData[0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let vibrato = sin(2.0 * Double.pi * 5.0 * t) * 15.0
            let freq = baseFreq + vibrato
            let envelope = min(1.0, progress * 4) * max(0, 1.0 - (progress - 0.7) * 3.3)
            let sample = sin(2.0 * Double.pi * freq * t) + 0.5 * sin(4.0 * Double.pi * freq * t) + 0.3 * sin(6.0 * Double.pi * freq * t)
            data[i] = Float(sample * envelope * 0.3)
        }
        return buffer
    }
    
    nonisolated private func generateAlarm(freq1: Double, freq2: Double, duration: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return buffer }
        let data = channelData[0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let switchRate = 8.0
            let freq = sin(2.0 * Double.pi * switchRate * t) > 0 ? freq1 : freq2
            let envelope = sin(Double.pi * t / duration)
            data[i] = Float(sin(2.0 * Double.pi * freq * t) * envelope * 0.35)
        }
        return buffer
    }
    
    nonisolated private func generateBuzz(baseFreq: Double, duration: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return buffer }
        let data = channelData[0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let envelope = sin(Double.pi * progress)
            var sample = 0.0
            for harmonic in 1...8 {
                sample += sin(2.0 * Double.pi * baseFreq * Double(harmonic) * t) / Double(harmonic)
            }
            data[i] = Float(sample * envelope * 0.2)
        }
        return buffer
    }
    
    nonisolated private func generateShimmer(duration: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return buffer }
        let data = channelData[0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let freq = 1000 + 2000 * sin(Double.pi * progress * 3)
            let envelope = sin(Double.pi * progress)
            let noise = Double.random(in: -0.1...0.1)
            data[i] = Float((sin(2.0 * Double.pi * freq * t) + noise) * envelope * 0.3)
        }
        return buffer
    }
    
    nonisolated private func generateRobotBeep(duration: Double, sampleRate: Double) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return buffer }
        let data = channelData[0]
        let freqs = [440.0, 880.0, 660.0, 1100.0]
        let segmentLength = duration / Double(freqs.count)
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let segIndex = min(Int(t / segmentLength), freqs.count - 1)
            let freq = freqs[segIndex]
            let segProgress = (t - Double(segIndex) * segmentLength) / segmentLength
            let envelope = sin(Double.pi * segProgress)
            data[i] = Float(sin(2.0 * Double.pi * freq * t) * envelope * 0.35)
        }
        return buffer
    }
}
