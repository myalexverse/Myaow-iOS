import Foundation
import AVFoundation

@main struct WallpaperPlaybackChecks {
    @MainActor static func main() async throws {
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Myaow/Resources/Wallpapers")
        let lava = folder.appendingPathComponent("WallpaperLava.mp4")
        let water = folder.appendingPathComponent("WallpaperWater.mp4")
        let playback = WallpaperVideoPlayback()
        playback.start(url: lava, suspended: true)
        precondition(playback.player == nil, "Covered cold launch must not allocate a decoder")
        playback.start(url: lava, suspended: false)
        let original = playback.player!
        precondition(original.isMuted && original.volume == 0, "Wallpapers must not interfere with call/music audio")
        // Exercise the actual AVPlayer, not a duplicate of the lifecycle logic.
        for _ in 0..<40 {
            if original.currentTime().seconds > 0.1 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        precondition(original.currentTime().seconds > 0.1, "Fixture must really be decoding before testing its paused frame")
        playback.start(url: lava, suspended: true)
        let frozenTime = original.currentTime()
        precondition(original.rate == 0)
        try await Task.sleep(for: .milliseconds(180))
        precondition(abs(original.currentTime().seconds - frozenTime.seconds) < 0.1, "Covered video must stop consuming playback time")
        for _ in 0..<30 {
            playback.start(url: lava, suspended: false)
            precondition(playback.player === original, "Back navigation must reuse the same player and frame")
            playback.start(url: lava, suspended: true)
        }
        playback.start(url: water, suspended: true)
        precondition(playback.player === original && original.rate == 0, "Hidden selection changes must not start another player")
        playback.start(url: water, suspended: false)
        precondition(playback.player !== original && original.items().isEmpty, "Resource replacement must release the old queue")
        playback.stop()
        precondition(playback.player == nil, "Background/low-power release path must tear down the decoder")
        playback.start(url: lava, suspended: false)
        precondition(playback.player != nil && playback.player !== original)
        playback.stop()
        print("PASS: cold covered launch, silent playback, frozen time, 30 back/forward reuse cycles, hidden selection changes, queue teardown and restart.")
    }
}
