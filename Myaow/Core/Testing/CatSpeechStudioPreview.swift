#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// An isolated design surface: no microphone, contact identity or network.
struct CatSpeechStudioPreview: View {
    @State private var level = 0.7
    @State private var emotion: MyaowCatState = .friendly
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("UNA VOZ. SU PROPIO GATO.").font(.caption).tracking(2).foregroundStyle(MyaowColor.orange)
                MyaowCatView(state: emotion, style: .darkOnOrange, size: 240, isInteractive: false, speakingLevel: level)
                Text("Gesticulación de llamada").font(.title2.weight(.semibold))
                HStack(spacing: 30) {
                    VStack { MyaowCatView(state: emotion, style: .darkOnOrange, size: 68, isInteractive: false, speakingLevel: level); Text("Burbuja · 68 pt").font(.caption2) }
                    VStack { MyaowCatView(state: emotion, style: .darkOnOrange, size: 150, isInteractive: false, speakingLevel: level); Text("Ventana flotante").font(.caption2) }
                }
                Slider(value: $level, in: 0...1).tint(MyaowColor.orange).accessibilityLabel("Intensidad de voz de prueba")
                Text("Voz de prueba: \(Int(level * 100))% · Sin grabación").font(.caption.monospacedDigit())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 18) {
                    ForEach([MyaowCatState.friendly, .curious, .angry, .shy, .laughing, .sad, .skeptical, .sleeping]) { state in
                        Button { emotion = state } label: {
                            VStack { MyaowCatView(state: state, style: .darkOnOrange, size: 66, isInteractive: false, speakingLevel: level); Text(state.displayName).font(.system(size: 10)) }
                        }.buttonStyle(.plain)
                    }
                }
                Text("REVISIÓN LOCAL · EXPRESIONES ORIGINALES").font(.caption2).foregroundStyle(.secondary)
            }.padding(24)
        }.background(MyaowColor.charcoal).foregroundStyle(.white)
    }
}
#endif
