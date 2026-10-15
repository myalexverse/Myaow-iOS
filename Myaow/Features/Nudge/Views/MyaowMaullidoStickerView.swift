import SwiftUI

/// A tappable sound sticker, shared by direct and group chats.
struct MyaowMaullidoStickerView: View {
    let sound: CatVocalSynthesizer.CatSoundType
    let onError: (String) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var audio = CatVocalSynthesizer.shared
    @State private var sourceID = UUID()

    private var playing: Bool { audio.playbackSourceID == sourceID && audio.playingType == sound }
    private var pulse: Double { playing ? sin(audio.playbackProgress * .pi * 6) : 0 }

    var body: some View {
        Button {
            if playing { audio.stop() }
            else if !audio.playCatSound(sound, sourceID: sourceID) {
                onError(audio.lastError ?? "No pudimos reproducir el maullido.")
            }
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    ForEach(0..<3) { index in
                        Image(systemName: ornament)
                            .font(.system(size: index == 1 ? 19 : 12, weight: .semibold))
                            .foregroundStyle(MyaowColor.orange.opacity(playing ? 0.9 : 0.45))
                            .rotationEffect(.degrees(index == 0 ? -18 : 15))
                            .offset(x: index == 1 ? 78 : -75,
                                    y: CGFloat(index == 0 ? -45 : index == 1 ? -20 : 42) - (playing && !reduceMotion ? pulse * 5 : 0))
                    }
                    MyaowCatView(state: sound.catState, style: .orangeOnTransparent,
                                 size: 154, isInteractive: false)
                        .shadow(color: MyaowColor.orange.opacity(playing ? 0.25 : 0.09), radius: 16, y: 5)
                        .scaleEffect(playing && !reduceMotion ? 1.02 + pulse * 0.035 : 1)
                        .rotationEffect(.degrees(playing && !reduceMotion ? pulse * 3 : 0))
                }.frame(width: 200, height: 177)
                Text(sound.displayName)
                    .font(.system(size: 23, weight: .heavy, design: .rounded))
                    .foregroundStyle(MyaowColor.textPrimary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Label(playing ? "Sonando" : "Toca para escuchar", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(playing ? MyaowColor.orange : MyaowColor.textSecondary)
                    .padding(.top, 5)
            }.padding(.horizontal, 8).padding(.bottom, 6)
                .frame(width: 216).contentShape(RoundedRectangle(cornerRadius: 24))
        }.buttonStyle(.plain)
            .accessibilityLabel("Maullido \(sound.displayName), sticker con sonido")
            .accessibilityValue(playing ? "Reproduciendo" : "")
            .accessibilityHint(playing ? "Toca para detenerlo" : "Toca para escuchar el maullido")
            .onDisappear { if playing { audio.stop() } }
    }

    private var ornament: String {
        switch sound {
        case .classic, .echo: "sparkle"
        case .giggle: "sparkles"
        default: sound.effectSymbol
        }
    }
}
