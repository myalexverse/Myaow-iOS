import AVFoundation
import Observation

@MainActor @Observable
final class WallpaperVideoPlayback {
    private(set) var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var url: URL?

    func start(url: URL, suspended: Bool) {
        // A covered root keeps its current frame, but must never continue playing,
        // even if the requested resource changed while a modal was open.
        if suspended { player?.pause(); return }
        if let player, self.url == url { player.play(); return }
        stop()
        let player = AVQueuePlayer()
        player.isMuted = true
        player.volume = 0
        player.preventsDisplaySleepDuringVideoPlayback = false
        // No AVAudioSession changes: music, voice notes and calls retain control.
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        self.url = url
        self.player = player
        player.play()
    }

    func stop() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        player = nil
        url = nil
    }
}

