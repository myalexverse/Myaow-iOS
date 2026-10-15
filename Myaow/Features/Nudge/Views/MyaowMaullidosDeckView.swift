import SwiftUI

public struct MyaowMaullidosButtonIconView: View {
    public var cooldownSeconds: Int = 0
    public var body: some View {
        ZStack {
            Circle().fill(MyaowColor.orange.opacity(0.12))
            if cooldownSeconds > 0 {
                Text("\(cooldownSeconds)").font(.caption.monospacedDigit())
            } else { MyaowMaullidosMark(size: 29) }
        }.foregroundStyle(MyaowColor.orange).frame(width: 44, height: 44)
    }
}

public struct MyaowMaullidosDeckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    public var onSelectMaullido: (CatVocalSynthesizer.CatSoundType) -> Bool
    @State private var selected: CatVocalSynthesizer.CatSoundType = .classic
    @State private var audio = CatVocalSynthesizer.shared
    @State private var error: String?
    @State private var showingOptions = false
    @State private var showingEffect = false
    @AppStorage("myaow_nudge_autoplay") private var autoplay = true
    @AppStorage("myaow_nudge_haptics") private var haptics = true
    @AppStorage("myaow_nudge_effects") private var screenEffects = true

    public init(onSelectMaullido: @escaping (CatVocalSynthesizer.CatSoundType) -> Bool) {
        self.onSelectMaullido = onSelectMaullido
    }
    public var body: some View {
      VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Maullidos").font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("Di más. A tu manera.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                    }
                    Spacer()
                    Button { showingOptions = true } label: {
                        Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                            .background(.white.opacity(0.05), in: Circle())
                    }.accessibilityLabel("Opciones de maullidos")
                    Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("Cerrar maullidos")
                }
                preview
                HStack {
                    Text("ELIGE TU SONIDO").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(MyaowColor.textSecondary)
                    Spacer()
                    Text("\(CatVocalSynthesizer.CatSoundType.allCases.count) / MYAOW").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(MyaowColor.orange)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 260 : 145), spacing: 10)], spacing: 10) {
                    ForEach(CatVocalSynthesizer.CatSoundType.allCases) { sound in
                        Button {
                            audio.stop(); selected = sound
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    MyaowMaullidoArtIconView(soundType: sound, size: 44)
                                    Spacer()
                                    Image(systemName: selected == sound ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected == sound ? MyaowColor.orange : Color.white.opacity(0.15))
                                }
                                Text(sound.displayName).font(.system(size: 16, weight: .semibold))
                            }.padding(15)
                                .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
                                .background(selected == sound ? MyaowColor.orange.opacity(0.08) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 21))
                                .overlay(RoundedRectangle(cornerRadius: 21).stroke(selected == sound ? MyaowColor.orange.opacity(0.6) : .white.opacity(0.07), lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityAddTraits(selected == sound ? .isSelected : [])
                    }
                }
                Label("Cada maullido tiene su propio sonido de notificación. Respeta el modo silencio y tus ajustes del iPhone.", systemImage: "lock.iphone")
                    .font(.footnote).foregroundStyle(MyaowColor.textSecondary).lineSpacing(3)
            }.padding(20).padding(.top, 14)
        }
            VStack(spacing: 10) {
                if let error { Text(error).font(.caption).foregroundStyle(MyaowColor.orange).accessibilityAddTraits(.updatesFrequently) }
                Button {
                    audio.stop()
                    if onSelectMaullido(selected) { dismiss() }
                    else { error = "No pudimos guardar el maullido. Espera un momento e inténtalo otra vez." }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "paperplane.fill")
                        Text(MyaowNudgeService.shared.cooldownSeconds > 0 ? "Espera \(MyaowNudgeService.shared.cooldownSeconds) s" : "Enviar \(selected.displayName)")
                    }.font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 17)
                        .foregroundStyle(.black).background(MyaowColor.orange, in: Capsule())
                }.disabled(MyaowNudgeService.shared.cooldownSeconds > 0)
            }.padding(20).background(Color(hex: "0D0E10"))
      }
        .background(Color(hex: "0D0E10"))
        .foregroundStyle(.white)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(32)
        .onDisappear { audio.stop() }
        .sheet(isPresented: $showingEffect) { MyaowNudgeEffectPreview(sound: selected) }
        .sheet(isPresented: $showingOptions) {
            NavigationStack {
                Form {
                    Section("Dentro de Myaow") {
                        Toggle("Reproducir al recibir", isOn: $autoplay)
                        Toggle("Respuesta háptica", isOn: $haptics)
                        Toggle("Efectos en pantalla", isOn: $screenEffects)
                    }
                    Section {
                        Button("Abrir ajustes del iPhone", systemImage: "arrow.up.right.square") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    } header: { Text("Con el teléfono bloqueado") }
                    footer: { Text("Los avisos dependen de los permisos, el volumen, el modo silencio y los modos de concentración del iPhone. Puedes escuchar manualmente cada maullido desde el chat.") }
                }.tint(MyaowColor.orange).preferredColorScheme(.dark)
                    .navigationTitle("Opciones").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showingOptions = false } } }
            }.presentationDetents([.medium, .large])
        }
    }
    private var preview: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(MyaowColor.orange.opacity(0.12), lineWidth: 1).frame(width: 108, height: 108)
                MyaowMaullidoArtIconView(soundType: selected, size: 88)
                    .scaleEffect(audio.playingType == selected && !reduceMotion ? 1.04 : 1)
                    .animation(.easeInOut(duration: 0.25), value: audio.playingType)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 9) {
                Text(selected.displayName).font(.system(size: 23, weight: .semibold, design: .rounded))
                Text(selected.subtitle).font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                Button {
                    error = nil
                    if audio.playingType == selected { audio.stop() }
                    else if !audio.playCatSound(selected) { error = audio.lastError }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: audio.playingType == selected ? "stop.fill" : "play.fill")
                        Text(audio.playingType == selected ? "Detener" : "Escuchar")
                        Text(selected.duration.formatted(.number.precision(.fractionLength(1))) + " s").foregroundStyle(MyaowColor.textSecondary).monospacedDigit()
                    }.font(.system(size: 12, weight: .semibold)).frame(minHeight: 44)
                }.buttonStyle(.plain)
                ProgressView(value: audio.playingType == selected ? audio.playbackProgress : 0)
                    .tint(MyaowColor.orange).accessibilityLabel("Progreso del maullido")
                Button("Ver efecto", systemImage: "sparkles") { showingEffect = true }
                    .font(.system(size: 12, weight: .semibold)).tint(MyaowColor.orange).frame(minHeight: 36)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(20)
            .background(LinearGradient(colors: [Color(hex: "251B15"), Color(hex: "141416")], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(Color.white.opacity(0.07)))
    }
}
