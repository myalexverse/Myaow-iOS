import SwiftUI
import Combine
import AVFoundation

@MainActor
@Observable
public final class VoicePlaybackService: NSObject, AVAudioPlayerDelegate {
    public static let shared = VoicePlaybackService()
    public var activeMessageId: String?
    public var isPlaying = false
    public var playbackProgress = 0.0
    public var playbackSpeed = 1.0
    public var lastError: String?
    public var audioPlayer: AVAudioPlayer?
    private var timer: AnyCancellable?

    public func togglePlay(messageId: String, audioData: Data?, duration: TimeInterval = 10.0) {
        if activeMessageId == messageId && isPlaying { pause() }
        else { play(messageId: messageId, audioData: audioData, duration: duration) }
    }
    public func play(messageId: String, audioData: Data?, duration: TimeInterval = 10.0) {
        lastError = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            if activeMessageId != messageId || audioPlayer == nil {
                pause()
                audioPlayer = nil
                playbackProgress = 0
                activeMessageId = messageId
                guard let audioData, !audioData.isEmpty else {
                    lastError = "El audio todavía no está disponible en este dispositivo."
                    return
                }
                let player = try AVAudioPlayer(data: audioData)
                player.delegate = self
                player.enableRate = true
                audioPlayer = player
            }
            guard let player = audioPlayer else { return }
            player.rate = Float(playbackSpeed)
            guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
            isPlaying = true
            timer?.cancel()
            timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                guard let self, let player = self.audioPlayer, self.isPlaying else { return }
                self.playbackProgress = player.duration > 0 ? player.currentTime / player.duration : 0
            }
        } catch {
            pause()
            audioPlayer = nil
            lastError = "No pudimos reproducir esta nota de voz. El archivo puede estar incompleto."
        }
    }
    public func pause() {
        isPlaying = false
        audioPlayer?.pause()
        timer?.cancel()
        timer = nil
    }
    public func cyclePlaybackSpeed() {
        playbackSpeed = playbackSpeed == 1 ? 1.5 : playbackSpeed == 1.5 ? 2 : 1
        audioPlayer?.rate = Float(playbackSpeed)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    public func seek(progress: Double) {
        guard let player = audioPlayer else { return }
        playbackProgress = min(1, max(0, progress))
        player.currentTime = player.duration * playbackProgress
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.audioPlayer === player else { return }
            self.pause()
            self.playbackProgress = 0
            player.currentTime = 0
            if !flag { self.lastError = "La reproducción se interrumpió." }
        }
    }
}
