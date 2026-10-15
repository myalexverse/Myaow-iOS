#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import AVFoundation

/// Isolated design/audio bench. No transport, peer, CallKit, contacts or microphone.
struct RadioConsolePreview: View {
    @State private var state = RadioConsoleState.ready
    @State private var tap = false
    @State private var transitions = RadioCueTransitions()
    @State private var cueResult = "Micrófono de prueba cerrado"
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("RADIO · PRUEBA DE DISEÑO").font(.caption.monospaced()).foregroundStyle(MyaowColor.orange)
                RadioConsoleView(name: "Sofía", catState: .cool, mode: "Por internet", state: state,
                    levels: state == .receiving ? [0.1, 0.4, 0.7, 0.2, 0.85, 0.3, 0.1] : [], detail: "Datos ficticios. Ningún micrófono ni conexión real.")
                RadioTransmitControl(enabled: state == .ready || state == .transmitting, transmitting: state == .transmitting,
                    receiving: state == .receiving, tapToTalk: tap,
                    start: { change(.transmitting) }, stop: { if state == .transmitting { change(.ready) } })
                Text(cueResult).font(.caption.monospaced()).foregroundStyle(MyaowColor.orange)
                Toggle("Hablar con un toque", isOn: $tap)
                HStack {
                    Button("Recibir") { change(.receiving) }
                    Button("Canal libre") { change(.ready) }
                }.buttonStyle(.bordered)
                ForEach(RadioSoundCue.allCases, id: \.self) { cue in
                    Button("Escuchar: \(cue.rawValue)") {
                        CommunicationTones.shared.playRadio(cue)
                        cueResult = cue.rawValue
                    }.buttonStyle(.bordered)
                }
            }.padding(24)
        }.background(Color(hex: "#08090B").ignoresSafeArea()).foregroundStyle(.white)
            .task {
                guard DesignPreviewData.isEnabled else { return }
                try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
            }
    }
    private func change(_ value: RadioConsoleState) {
        state = value
        if let cue = transitions.update(transmitting: value == .transmitting, receiving: value == .receiving) {
            CommunicationTones.shared.playRadio(cue); cueResult = cue.rawValue
        }
    }
}
#endif
