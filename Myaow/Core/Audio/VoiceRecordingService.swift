//
//  VoiceRecordingService.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import AVFoundation
import Combine

public struct WaveformBarItem: Identifiable, Sendable {
    public let id: Int
    public var value: CGFloat
}

@MainActor
@Observable
public final class VoiceRecordingService: NSObject {
    public static let shared = VoiceRecordingService()
    
    public var isRecording: Bool = false
    public var isLocked: Bool = false
    public var recordingDuration: TimeInterval = 0
    public var waveformBars: [WaveformBarItem] = []
    
    public var lastError: String?
    private var permissionRequest: UUID?
    private var timer: AnyCancellable?
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    
    public var durationFormatted: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    public override init() {
        super.init()
        resetWaveformBars()
    }
    
    private func resetWaveformBars() {
        self.waveformBars = (0..<18).map { WaveformBarItem(id: $0, value: 0.15) }
    }
    
    public func startRecording() {
        guard !isRecording, permissionRequest == nil else { return }
        lastError = nil
        let request = UUID()
        permissionRequest = request
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self, self.permissionRequest == request else { return }
                self.permissionRequest = nil
                guard granted else {
                    self.lastError = "Permite el acceso al micrófono en Ajustes para grabar una nota de voz."
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1, AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue, AVEncoderBitRateKey: 128000
            ]
            let recorder = try AVAudioRecorder(url: tempURL, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else { throw CocoaError(.fileWriteUnknown) }
            audioRecorder = recorder
            recordingURL = tempURL
            isRecording = true
            isLocked = false
            recordingDuration = 0
            resetWaveformBars()
        } catch {
            cancelRecording()
            try? FileManager.default.removeItem(at: tempURL)
            lastError = "No pudimos iniciar la grabación. Revisa el micrófono e intenta de nuevo."
            return
        }

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // 2. Timer de onda sonora y duración fluido y seguro
        timer?.cancel()
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isRecording else { return }
                self.recordingDuration = self.audioRecorder?.currentTime ?? 0
                
                // Muestras dinámicas de voz
                self.audioRecorder?.updateMeters()
                let power = self.audioRecorder?.averagePower(forChannel: 0) ?? -60.0
                let newSample = max(0.05, min(1.0, CGFloat((power + 60.0) / 60.0)))
                
                // Desplazar las barras de onda de manera inmutable y segura
                var updated = self.waveformBars
                if updated.count >= 18 {
                    updated.removeFirst()
                }
                let nextId = (self.waveformBars.last?.id ?? 0) + 1
                updated.append(WaveformBarItem(id: nextId, value: newSample))
                self.waveformBars = updated
            }
    }
    
    public func stopAndExportRecording() -> (duration: TimeInterval, samples: [CGFloat], audioData: Data?) {
        let resultDuration = audioRecorder?.currentTime ?? recordingDuration
        let resultSamples = waveformBars.map { $0.value }
        
        audioRecorder?.stop()
        let audioData: Data? = recordingURL.flatMap { try? Data(contentsOf: $0) }
        // Clean up temp file
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        audioRecorder = nil
        recordingURL = nil
        
        cancelRecording()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        return (resultDuration, resultSamples, audioData)
    }
    
    public func cancelRecording() {
        permissionRequest = nil
        self.isRecording = false
        self.isLocked = false
        self.recordingDuration = 0
        self.timer?.cancel()
        self.timer = nil
        self.resetWaveformBars()
        
        audioRecorder?.stop()
        audioRecorder = nil
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
