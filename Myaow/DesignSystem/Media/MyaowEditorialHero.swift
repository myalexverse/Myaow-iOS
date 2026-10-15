import SwiftUI
import AVFoundation

/// The existing emblem receives materials and depth; emotional avatars keep their original artwork.
struct MyaowEditorialHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var isPaused = false
    var compact = false

    private var shouldPlay: Bool {
        isVisible && scenePhase == .active && !reduceMotion && !isPaused && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.065, green: 0.07, blue: 0.075)
                RadialGradient(colors: [MyaowColor.orange.opacity(0.24), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 340)
                MyaowFilmView(isPlaying: shouldPlay)
                    .opacity(0.7)
                LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)

                Text(compact ? "TU GENTE." : "MYAOW\nWORLD.")
                    .font(.system(size: compact ? 42 : 72, weight: .black, design: .default))
                    .tracking(-4)
                    .lineSpacing(-12)
                    .foregroundStyle(Color.white.opacity(0.12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 36)
                    .padding(.leading, 15)

                Image("MyaowCatSculpture")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // The source render has a baked backdrop. Clip only its silhouette at display time.
                    .mask(MyaowSculptureSilhouette())
                    .frame(width: compact ? 150 : min(geometry.size.width * 0.83, 300))
                    .rotationEffect(.degrees(-8))
                    .shadow(color: .black.opacity(0.55), radius: 16, x: 8, y: 16)
                    .offset(x: compact ? geometry.size.width * 0.24 : 13, y: compact ? 5 : 8)

                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Circle().fill(MyaowColor.orange).frame(width: 5, height: 5)
                        Text("MYAOW")
                        Spacer()
                        Text("TU MUNDO")
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        Text(compact ? "CERCA.\nA TU MANERA." : "TU GATO.\nTU PERSONALIDAD.")
                            .font(.system(size: compact ? 14 : 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.85))
                        Spacer()
                        if !reduceMotion {
                            Button {
                                isPaused.toggle()
                            } label: {
                                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                    .frame(width: 44, height: 44)
                                    .background(.black.opacity(0.65), in: Circle())
                            }
                            .accessibilityLabel(isPaused ? "Reproducir fondo" : "Pausar fondo")
                        }
                    }
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.16), lineWidth: 1))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Gato Myaow en relieve tridimensional")
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

/// Vector clipping keeps the original image intact and removes its background from the composition.
private struct MyaowSculptureSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 181, y: 871))
        p.addCurve(to: CGPoint(x: 612, y: 133), control1: CGPoint(x: 157, y: 374), control2: CGPoint(x: 328, y: 140))
        p.addCurve(to: CGPoint(x: 1050, y: 475), control1: CGPoint(x: 848, y: 116), control2: CGPoint(x: 1012, y: 231))
        p.addCurve(to: CGPoint(x: 1073, y: 1007), control1: CGPoint(x: 1082, y: 618), control2: CGPoint(x: 1070, y: 883))
        p.addQuadCurve(to: CGPoint(x: 1047, y: 1047), control: CGPoint(x: 1076, y: 1054))
        p.addLine(to: CGPoint(x: 784, y: 999))
        p.addCurve(to: CGPoint(x: 404, y: 953), control1: CGPoint(x: 633, y: 1065), control2: CGPoint(x: 502, y: 1017))
        p.addQuadCurve(to: CGPoint(x: 331, y: 906), control: CGPoint(x: 360, y: 934))
        p.addLine(to: CGPoint(x: 190, y: 884))
        p.closeSubpath()
        return p.applying(CGAffineTransform(scaleX: rect.width / 1254, y: rect.height / 1254))
    }
}

private struct MyaowFilmView: UIViewRepresentable {
    var isPlaying: Bool

    func makeUIView(context: Context) -> FilmSurface { FilmSurface() }
    func updateUIView(_ uiView: FilmSurface, context: Context) {
        if isPlaying { uiView.player.play() } else { uiView.player.pause() }
    }
    static func dismantleUIView(_ uiView: FilmSurface, coordinator: ()) {
        uiView.player.pause()
        uiView.player.removeAllItems()
        uiView.looper = nil
    }

    final class FilmSurface: UIView {
        let player = AVQueuePlayer()
        var looper: AVPlayerLooper?
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        init() {
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            guard let layer = layer as? AVPlayerLayer else { return }
            layer.videoGravity = .resizeAspectFill
            layer.player = player
            if let url = Bundle.main.url(forResource: "myaow-signal-loop", withExtension: "mp4") {
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

struct MyaowSculptureMark: View {
    var body: some View {
        Image("MyaowCatSculpture")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .mask(MyaowSculptureSilhouette())
            .rotationEffect(.degrees(-9))
            .shadow(color: .black.opacity(0.3), radius: 12, x: 5, y: 10)
            .accessibilityLabel("Emblema Myaow en relieve")
    }
}
