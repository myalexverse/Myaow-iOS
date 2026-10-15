#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct EmotionAtlasPreview: View {
    @State private var page = 0
    private var states: [MyaowCatState] { Array(MyaowCatState.allCases.dropFirst(page * 16).prefix(16)) }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                MyaowMaullidosMark(size: 32)
                Text("31 formas de ser tú").font(.title2.bold())
                Spacer()
            }.padding(.horizontal, 22)
            HStack {
                ForEach(0..<2) { index in
                    Button(index == 0 ? "Emociones 1–16" : "Emociones 17–31") { page = index }
                        .buttonStyle(.bordered).tint(page == index ? MyaowColor.orange : .gray)
                }
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(),spacing: 8),count: 4),spacing: 16) {
                    ForEach(states) { state in
                        VStack(spacing: 8) {
                            MyaowCatView(state: state, style: .darkOnOrange, size: 76, isInteractive: true)
                            Text(state.displayName).font(.system(size: 10,weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        }.padding(.vertical, 12).frame(maxWidth: .infinity)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                    }
                }.padding(.horizontal, 12)
            }
            Text("REVISIÓN LOCAL · MOVIMIENTO NATIVO").font(.caption2).tracking(1).foregroundStyle(.secondary)
        }.padding(.top, 14).padding(.bottom, 14).background(MyaowColor.charcoal).foregroundStyle(.white)
    }
}
#endif
