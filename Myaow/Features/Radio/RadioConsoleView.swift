import SwiftUI

enum RadioConsoleState: String {
    case offline = "SIN ENLACE", connecting = "ENLAZANDO", ready = "CANAL LIBRE"
    case requesting = "SOLICITANDO TURNO", transmitting = "TRANSMITIENDO", receiving = "RECIBIENDO", ended = "ENLACE CERRADO"
    var tint: Color {
        switch self {
        case .receiving: MyaowColor.statusGreen
        case .offline, .ended: MyaowColor.textSecondary
        default: MyaowColor.orange
        }
    }
}

/// Shared instrument face for nearby and internet radio; indicators reflect real state.
struct RadioConsoleView: View {
    let name: String
    let catState: MyaowCatState
    let mode: String
    let state: RadioConsoleState
    var levels: [CGFloat] = []
    var detail: String = "Un contacto. Un turno a la vez."

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Label(mode.uppercased(), systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                Image(systemName: "lock.fill").accessibilityLabel("Enlace privado")
            }.font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.3)
                .foregroundStyle(MyaowColor.textSecondary)
            HStack(spacing: 14) {
                MyaowCatView(state: catState, style: .darkOnOrange, size: 54, isInteractive: false)
                VStack(alignment: .leading, spacing: 5) {
                    Text("TU CONTACTO").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.8).foregroundStyle(MyaowColor.textSecondary)
                    Text(name).font(.system(size: 23, weight: .semibold, design: .rounded)).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(state.tint).frame(width: 7, height: 7)
                        .shadow(color: state.tint.opacity(0.5), radius: 5)
                    Text(state.rawValue).font(.system(size: 12, weight: .bold, design: .monospaced)).tracking(1.1)
                    Spacer(minLength: 0)
                    if state == .connecting || state == .requesting { ProgressView().controlSize(.mini).tint(state.tint) }
                    else { Text(state == .transmitting ? "TX" : state == .receiving ? "RX" : "PTT").font(.system(size: 11, weight: .bold, design: .monospaced)) }
                }.foregroundStyle(state.tint)
                GeometryReader { geometry in
                    HStack(alignment: .center, spacing: 3) {
                        ForEach(0..<28, id: \.self) { index in
                            let level = levels.isEmpty ? 0 : Double(levels[min(index * levels.count / 28, levels.count - 1)])
                            let safeLevel = level.isFinite ? max(0, min(1, level)) : 0
                            Capsule().fill(state.tint.opacity(state == .transmitting || state == .receiving ? 0.9 : 0.22))
                                .frame(width: max(2, (geometry.size.width - 81) / 28), height: 3 + safeLevel * 23)
                        }
                    }.frame(height: 28)
                }.frame(height: 28).accessibilityHidden(true)
                Text(detail).font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(14)
                .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(state.tint.opacity(0.18), lineWidth: 1))
        }
        .padding(18)
        .background(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.055)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.09), lineWidth: 1))
    }
}

/// A release, cancelled gesture, app interruption or view dismissal always closes the mic.
struct RadioTransmitControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var touching = false
    @State private var pressed = false
    @State private var cancelled = false
    let enabled: Bool
    let transmitting: Bool
    let receiving: Bool
    var requesting = false
    let tapToTalk: Bool
    var diameter: CGFloat = 212
    let start: () -> Void
    let stop: () -> Void
    private var tint: Color { receiving ? MyaowColor.statusGreen : MyaowColor.orange }
    private var title: String { transmitting ? "SUELTA" : receiving ? "ESCUCHA" : "PULSA" }

    var body: some View {
        Group {
            if tapToTalk {
                Button { (transmitting || requesting) ? stop() : start() } label: { face }
                    .buttonStyle(.plain).disabled(!enabled && !transmitting && !requesting)
            } else {
                face.contentShape(Circle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .updating($touching) { _, value, _ in value = true }
                        .onChanged { value in
                            guard !cancelled else { return }
                            if abs(value.translation.width) > 90 || abs(value.translation.height) > 90 {
                                cancelled = true; stop(); return
                            }
                            guard !pressed, enabled else { return }
                            pressed = true; start()
                        }
                        .onEnded { _ in release() })
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { if transmitting || requesting { stop() } else if enabled { start() } }
            }
        }
        .accessibilityLabel(requesting ? "Cancelar solicitud de turno" : transmitting ? "Terminar transmisión" : receiving ? "Tu contacto está hablando" : "Pulsar para hablar")
        .accessibilityValue(transmitting ? "Micrófono abierto" : "Micrófono cerrado")
        .accessibilityHint("Con VoiceOver, activa para hablar y activa otra vez para escuchar. Turnos de hasta un minuto.")
        .onChange(of: touching) { _, value in if !value { release() } }
        .onChange(of: tapToTalk) { _, _ in release() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { release() } }
        .onDisappear { release() }
    }
    private func release() { pressed = false; cancelled = false; stop() }
    private var face: some View {
        ZStack {
            Circle().fill(Color(white: 0.035)).shadow(color: .black.opacity(0.5), radius: 14, y: 9)
            Circle().stroke(.white.opacity(0.08), lineWidth: 1).padding(3)
            Circle().stroke(tint.opacity(transmitting || receiving ? 0.25 : 0.09), lineWidth: 9).padding(13)
            Circle().fill(LinearGradient(colors: [Color(white: 0.19), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(24)
            Circle().stroke(tint.opacity(enabled || transmitting || receiving ? 0.95 : 0.25), lineWidth: transmitting ? 4 : 2).padding(25)
            VStack(spacing: 8) {
                Image(systemName: receiving ? "speaker.wave.2.fill" : transmitting ? "waveform" : "mic.fill").font(.system(size: 32, weight: .medium))
                Text(requesting ? "ESPERA" : tapToTalk ? (transmitting ? "ESCUCHAR" : receiving ? "ESCUCHA" : "HABLAR") : title)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(2)
                Text(requesting ? "solicitud de turno" : transmitting ? (tapToTalk ? "para cerrar el micro" : "para escuchar") : receiving ? "turno de tu contacto" : (tapToTalk ? "toca para transmitir" : "mantén para hablar"))
                    .font(.system(size: 10)).foregroundStyle(MyaowColor.textSecondary)
            }.foregroundStyle(tint.opacity(enabled || transmitting || receiving ? 1 : 0.4))
        }.frame(width: diameter, height: diameter)
            .scaleEffect(transmitting ? 0.96 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: transmitting)
    }
}

struct RadioPreferencesView: View {
    @AppStorage("radioTapToTalk") private var tapToTalk = false
    @AppStorage("radioSoundsEnabled") private var sounds = true
    @AppStorage("radioCueIntensity") private var intensity = RadioSoundMix.defaultIntensity
    @State private var soundNotice: String?
    private var normalizedIntensity: Double { RadioSoundMix.intensity(intensity) }
    var body: some View {
        VStack(spacing: 14) {
            Toggle(isOn: $sounds) {
                Label("Señales de radio", systemImage: "waveform.path").font(.subheadline)
            }.onChange(of: sounds) { _, enabled in
                if !enabled { CommunicationTones.shared.silenceRadio(); CommunicationTones.shared.ringback(false) }
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Pulso Myaow").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(Int(normalizedIntensity * 100)) %").font(.caption.monospacedDigit()).foregroundStyle(MyaowColor.orange)
                }
                HStack(spacing: 12) {
                    Image(systemName: "speaker.fill").foregroundStyle(MyaowColor.textSecondary)
                    Slider(value: Binding(get: { normalizedIntensity }, set: { intensity = $0 }), in: 0...1, step: 0.05)
                        .accessibilityLabel("Intensidad de las señales de Radio")
                        .accessibilityValue("\(Int(normalizedIntensity * 100)) por ciento")
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(MyaowColor.orange)
                }
                Button { soundNotice = CommunicationTones.shared.previewRadio() } label: {
                    Label("Probar sonido", systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(MyaowColor.orange.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain).foregroundStyle(MyaowColor.orange)
                Text("Señales con carácter de radio. El volumen de voz y de salida se ajusta con los botones del iPhone.")
                    .font(.caption).foregroundStyle(MyaowColor.textSecondary)
                if let soundNotice { Text(soundNotice).font(.caption).foregroundStyle(MyaowColor.orange) }
            }.disabled(!sounds).opacity(sounds ? 1 : 0.45)
                .onChange(of: intensity) { _, _ in CommunicationTones.shared.updateRadioMix() }
            Toggle(isOn: $tapToTalk) {
                Label("Hablar con un toque", systemImage: "hand.tap").font(.subheadline)
            }
            Text("Apertura, cambio de turno y cierre. Sin ruido de fondo durante la voz.")
                .font(.caption).foregroundStyle(MyaowColor.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
        }.tint(MyaowColor.orange).padding(18)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct RadioSoundSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Label("Pulso Myaow", systemImage: "waveform.path").font(.title2.weight(.semibold)).foregroundStyle(MyaowColor.orange)
                    Text("La señal de tu gente.").font(.title3.weight(.medium))
                    RadioPreferencesView()
                }.padding(24)
            }.background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
                .navigationTitle("Sonido de Radio").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.tint(MyaowColor.orange) } }
        }.preferredColorScheme(.dark).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
