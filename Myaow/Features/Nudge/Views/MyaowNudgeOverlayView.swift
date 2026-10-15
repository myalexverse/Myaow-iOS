import SwiftUI

public struct MyaowNudgeOverlayView: View {
    public let senderName: String
    public var theme: NudgeTheme = .electric
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    @AppStorage("myaow_nudge_effects") private var screenEffects = true
    private var sound: CatVocalSynthesizer.CatSoundType { MyaowNudgeService.shared.activeSound }
    public var body: some View {
      ZStack(alignment: .top) {
        if screenEffects { MyaowNudgeScreenEffect(sound: sound).ignoresSafeArea() }
        VStack {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(MyaowColor.orange.opacity(0.22)).frame(width: 90, height: 90)
                        .scaleEffect(expanded ? 1.08 : 0.9)
                    MyaowMaullidoArtIconView(soundType: sound, size: 70)
                        .rotationEffect(.degrees(reduceMotion ? 0 : expanded ? 5 : -5))
                    ForEach(0..<3) { index in
                        Image(systemName: sound.effectSymbol)
                            .font(.system(size: 12 + CGFloat(index)*2, weight: .semibold)).foregroundStyle(MyaowColor.orange)
                            .offset(x: CGFloat(index-1)*32, y: expanded ? -42 : -26)
                            .opacity(expanded ? 0.8 : 0.15)
                    }
                }.frame(width: 94, height: 100).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("UN MAULLIDO PARA TI").font(.system(size: 9, weight: .bold)).tracking(1.3).foregroundStyle(MyaowColor.orange)
                    Text(sound.displayName).font(.system(size: 23, weight: .bold, design: .rounded))
                    Text(senderName).font(.subheadline).foregroundStyle(MyaowColor.textSecondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { MyaowNudgeService.shared.dismissEffect() } label: {
                    Image(systemName: "xmark").font(.caption.weight(.semibold)).frame(width: 36, height: 44)
                }.accessibilityLabel("Cerrar maullido")
            }
            .padding(14)
            .background(LinearGradient(colors: [Color(hex: "302017"), Color(hex: "141518")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).stroke(MyaowColor.orange.opacity(0.25)))
            .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
            .padding(12)
            Spacer().allowsHitTesting(false)
        }
      }
        .foregroundStyle(.white)
        .onAppear {
            guard !reduceMotion else { expanded = true; return }
            withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) { expanded = true }
        }
    }
}
