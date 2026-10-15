import SwiftUI
import AVFoundation

/// Only the foreground wallpaper plays. A navigation-covered root is paused
/// at its current frame, so backing out never jumps to the poster/start of loop.
/// Background, low power and Reduce Motion still release the decoder entirely.
struct VideoWallpaperView: View {
    let url: URL?
    let posterResource: String?
    let posterURL: URL?
    let motionEnabled: Bool
    let playbackSuspended: Bool
    init(resource: String, motionEnabled: Bool, playbackSuspended: Bool = false) {
        self.url = Bundle.main.url(forResource: resource, withExtension: "mp4")
        self.posterResource = resource
        self.posterURL = nil
        self.playbackSuspended = playbackSuspended
        self.motionEnabled = motionEnabled
    }
    init(url: URL, posterResource: String?, posterURL: URL?, motionEnabled: Bool, playbackSuspended: Bool = false) {
        self.url = url; self.posterResource = posterResource; self.posterURL = posterURL; self.motionEnabled = motionEnabled
        self.playbackSuspended = playbackSuspended
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var playback = WallpaperVideoPlayback()

    private var shouldPlay: Bool { visible && motionEnabled && !reduceMotion && !lowPower && scenePhase == .active }
    private var playbackKey: String { "\(url?.absoluteString ?? "")-\(shouldPlay)-\(playbackSuspended)" }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MyaowColor.charcoal
                if let posterResource { Image(posterResource).resizable().scaledToFill() }
                else if let posterURL {
                    AsyncImage(url: posterURL) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
                }
                if let player = playback.player {
                    WallpaperPlayerSurface(player: player, reduceMotion: reduceMotion)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .onAppear { visible = true }
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        .onDisappear { visible = false; playback.stop() }
        .task(id: playbackKey) {
            if shouldPlay, let url { playback.start(url: url, suspended: playbackSuspended) }
            else { playback.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WallpaperPlayerSurface: UIViewRepresentable {
    let player: AVQueuePlayer
    let reduceMotion: Bool
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.playerLayer.videoGravity = .resizeAspectFill
        view.setPlayer(player, reduceMotion: reduceMotion)
        return view
    }
    func updateUIView(_ view: PlayerView, context: Context) { view.setPlayer(player, reduceMotion: reduceMotion) }
    static func dismantleUIView(_ view: PlayerView, coordinator: ()) { view.detach() }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        private var readyObservation: NSKeyValueObservation?
        private var assignment = UUID()

        func setPlayer(_ player: AVQueuePlayer, reduceMotion: Bool) {
            guard playerLayer.player !== player else { return }
            detach()
            let token = UUID(); assignment = token
            alpha = 0
            playerLayer.player = player
            // The poster remains visible until AVPlayerLayer actually has a frame.
            // A transparent player layer must not expose a black flash on startup.
            readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.assignment == token, self.playerLayer.isReadyForDisplay else { return }
                    self.readyObservation = nil
                    UIView.animate(withDuration: reduceMotion ? 0 : 0.18, delay: 0,
                                   options: [.beginFromCurrentState, .allowUserInteraction]) { self.alpha = 1 }
                }
            }
        }
        func detach() {
            assignment = UUID()
            readyObservation?.invalidate(); readyObservation = nil
            layer.removeAllAnimations()
            playerLayer.player = nil
        }
    }
}
