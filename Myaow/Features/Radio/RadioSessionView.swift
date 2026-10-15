import SwiftUI

/// Radio has its own visual language; CallKit/WebRTC still own secure audio transport.
struct RadioSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var call = CallSessionService.shared
    @State private var showSoundSettings = false
    @State private var peer = WebRTCPeerService.shared
    @State private var receivedLevels: [CGFloat] = Array(repeating: 0, count: 28)
    @AppStorage("radioTapToTalk") private var tapToTalk = false
    private var ended: Bool { call.callState == .ended }
    private var state: RadioConsoleState {
        if ended { return .ended }
        if call.radioTransmitting { return .transmitting }
        if call.radioReceiving { return .receiving }
        if call.radioRequestPending { return .requesting }
        return call.canRequestRadioTurn ? .ready : .connecting
    }
    private var detail: String {
        if ended { return call.endReason }
        if call.callState == .incoming { return "Quiere abrir un canal privado contigo. Tú decides si entrar." }
        if call.radioReceiving { return "\(call.activeCallContactName) tiene el turno. Escucha y espera la señal." }
        if call.radioTransmitting { return tapToTalk ? "Tu voz está al aire. Toca de nuevo para dejar libre el canal." : "Tu voz está al aire. Suelta el botón para dejar libre el canal." }
        if call.radioRequestPending { return "Esperando permiso de turno. Tu micrófono sigue cerrado." }
        if call.canRequestRadioTurn { return "Mantén el botón para hablar. Solo tu contacto te escucha." }
        return "Esperando un enlace seguro. Tu micrófono está cerrado."
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Radio").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("DIRECTO CON TU GENTE").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.6).foregroundStyle(MyaowColor.textSecondary)
                    }
                    Spacer()
                    Button { showSoundSettings = true } label: {
                        Image(systemName: "waveform").frame(width: 44, height: 44).background(.white.opacity(0.06), in: Circle())
                    }.accessibilityLabel("Sonido de Radio")
                    if !ended {
                        Button { call.minimize() } label: {
                            Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44).background(.white.opacity(0.06), in: Circle())
                        }.accessibilityLabel("Minimizar Radio y cerrar el micrófono")
                    }
                }
                RadioConsoleView(name: call.activeCallContactName, catState: call.activeCallCatState,
                    mode: "Por internet", state: state,
                    levels: call.radioReceiving ? receivedLevels : [], detail: detail)
                if ended {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash").font(.system(size: 48)).foregroundStyle(MyaowColor.textSecondary).padding(20)
                    Button("Volver a Radio") { call.dismissCall(); dismiss() }.buttonStyle(GroupPrimaryStyle())
                    Button("Volver a conectar") { call.startCall(contactName: call.activeCallContactName, myaowId: call.activeCallMyaowId, type: .radio) }.tint(MyaowColor.orange)
                } else if call.callState == .incoming {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 50)).foregroundStyle(MyaowColor.orange).padding(24)
                    Button("Aceptar enlace de Radio") { call.acceptCall() }.buttonStyle(GroupPrimaryStyle())
                    Button("Ahora no", role: .cancel) { call.endCall() }.foregroundStyle(MyaowColor.textSecondary)
                } else {
                    RadioTransmitControl(enabled: call.canRequestRadioTurn, transmitting: call.radioTransmitting,
                        receiving: call.radioReceiving, requesting: call.radioRequestPending, tapToTalk: tapToTalk, start: { call.startRadioTransmission() }, stop: { call.stopRadioTransmission() })
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(call.radioTransmitting ? "\(call.radioTurnSecondsRemaining) s · tu turno" : call.radioReceiving ? "RX · escuchando" : "PTT · un turno a la vez")
                            .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(state.tint)
                    }
                    HStack(spacing: 12) {
                        Button { call.toggleSpeaker() } label: {
                            Label(call.isSpeakerOn ? "Altavoz" : "Auricular", systemImage: call.isSpeakerOn ? "speaker.wave.2.fill" : "ear")
                                .frame(maxWidth: .infinity).padding(.vertical, 15).background(.white.opacity(0.06), in: Capsule())
                        }.accessibilityLabel("Cambiar salida de audio")
                        Button { call.endCall() } label: {
                            Label("Desconectar", systemImage: "power").frame(maxWidth: .infinity).padding(.vertical, 15)
                                .background(MyaowColor.orange.opacity(0.12), in: Capsule()).foregroundStyle(MyaowColor.orange)
                        }
                    }.font(.system(size: 13, weight: .semibold))
                    if let notice = call.radioNotice { Text(notice).font(.caption).foregroundStyle(MyaowColor.orange) }
                    RadioPreferencesView()
                }
                Label("Canal privado entre contactos", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(MyaowColor.textSecondary)
            }.padding(24)
        }
        .background(Color(hex: "#08090B").ignoresSafeArea()).foregroundStyle(.white).preferredColorScheme(.dark)
        .interactiveDismissDisabled(!ended)
        .sheet(isPresented: $showSoundSettings) { RadioSoundSettingsSheet() }
        .onChange(of: call.callState) { _, value in if value == .idle { dismiss() } }
        .onChange(of: peer.remoteSpeakingLevel) { _, level in
            guard call.radioReceiving else { return }
            receivedLevels.removeFirst(); receivedLevels.append(CGFloat(level))
        }
        .onChange(of: call.radioReceiving) { _, _ in receivedLevels = Array(repeating: 0, count: 28) }
        .onDisappear { call.stopRadioTransmission() }
    }
}
