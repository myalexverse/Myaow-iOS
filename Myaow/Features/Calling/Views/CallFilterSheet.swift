import SwiftUI
#if canImport(WebRTC)
import WebRTC

struct CallFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var peer = WebRTCPeerService.shared
    @State private var call = CallSessionService.shared
    @State private var draft = VideoFilterSettings()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack(alignment: .bottomLeading) {
                        Color(white: 0.08)
                        if !call.isCameraOff, let track = peer.filterPreviewTrack {
                            CallVideoSurface(track: track, fit: true).scaleEffect(x: call.isFrontCamera ? -1 : 1, y: 1)
                        } else {
                            ContentUnavailableView("Cámara apagada", systemImage: "video.slash", description: Text("Enciende la cámara para probar los efectos."))
                        }
                        Label("Vista previa · solo tú", systemImage: "eye").font(.caption.weight(.medium)).padding(10).background(.black.opacity(0.65), in: Capsule()).padding(12)
                    }.frame(height: 290).clipShape(RoundedRectangle(cornerRadius: 24))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(VideoCallFilterType.allCases) { filter in
                            Button { draft.type = filter } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: filter.iconName).font(.title3).foregroundStyle(MyaowColor.orange)
                                    Text(filter.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                    if draft.type == filter { Image(systemName: "checkmark.circle.fill").foregroundStyle(MyaowColor.orange) }
                                }.frame(maxWidth: .infinity, minHeight: 46).padding(10)
                                    .background(draft.type == filter ? MyaowColor.orange.opacity(0.15) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(draft.type == filter ? MyaowColor.orange : .clear))
                            }.buttonStyle(.plain).accessibilityAddTraits(draft.type == filter ? .isSelected : [])
                        }
                    }
                    Text(draft.type.subtitle).font(.subheadline).foregroundStyle(.secondary)
                    if draft.type == .pocketCat || draft.type == .livingInk {
                        HStack { Text(draft.type == .pocketCat ? "Tamaño del gato" : "Intensidad de tinta"); Spacer(); Text("\(Int(draft.intensity * 100))%").monospacedDigit() }.font(.caption)
                        Slider(value: $draft.intensity, in: 0...1).tint(MyaowColor.orange).accessibilityLabel(draft.type == .pocketCat ? "Tamaño del gato" : "Intensidad de tinta")
                    }
                    if draft.type == .catverse || draft.type == .pocketCat {
                        Text("Con buena luz, mueve la cabeza, parpadea o abre la boca. Si no encuentra un rostro, el gato descansa.").font(.caption).foregroundStyle(.secondary)
                    }
                    if draft.type == .duoPortal { Text("Aplicar muestra tu portal. Después podrás invitar a tu contacto; las sorpresas se habilitan cuando acepte.").font(.caption).foregroundStyle(.secondary) }
                    if let notice = peer.filterNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
                    Button {
                        peer.applyFilter(draft); dismiss()
                    } label: { Text(draft.type == .normal ? "Usar cámara natural" : "Aplicar a mi video").font(.headline).frame(maxWidth: .infinity).padding(16).foregroundStyle(.black).background(MyaowColor.orange, in: Capsule()) }
                    .disabled(call.isCameraOff || peer.localVideoTrack == nil)
                    Text("El efecto aplicado también lo verá tu contacto. El análisis del rostro se realiza en tu dispositivo.").font(.caption2).foregroundStyle(.secondary)
                }.padding(20)
            }.navigationTitle("Tu lado de la llamada").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
                .background(MyaowColor.charcoal)
        }.preferredColorScheme(.dark)
            .onAppear { draft = peer.videoFilter; draft.reducedMotion = reducedMotion; peer.previewFilter(draft) }
            .onChange(of: draft) { _, value in peer.previewFilter(value) }
            .onChange(of: reducedMotion) { _, value in draft.reducedMotion = value }
            .onChange(of: call.callState) { _, state in if state == .ended || state == .idle { dismiss() } }
            .onDisappear { peer.closeFilterPreview() }
    }
}

struct CallPortalControls: View {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var peer = WebRTCPeerService.shared
    var body: some View {
        VStack(spacing: 10) {
            switch peer.portalSession.phase {
            case .invited:
                Text("Tu contacto te invita al Portal a dúo").font(.subheadline.weight(.semibold))
                Text("Al aceptar, se aplica el portal a tu video y podrán enviarse sorpresas.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Ahora no") { peer.answerPortal(accept: false, reducedMotion: reducedMotion) }
                    Spacer()
                    Button("Entrar al portal") { peer.answerPortal(accept: true, reducedMotion: reducedMotion) }.tint(MyaowColor.orange)
                }
            case .inviting:
                HStack { Text("Esperando a tu contacto…"); Spacer(); Button("Cancelar") { peer.leavePortal() } }.font(.caption)
            case .connected:
                HStack {
                    ForEach(PortalGift.allCases, id: \.self) { gift in
                        Button { peer.sendPortalGift(gift) } label: { Text(gift.symbol).font(.title2).frame(maxWidth: .infinity).padding(8).background(.white.opacity(0.08), in: Capsule()) }.accessibilityLabel("Enviar \(gift.title)")
                    }
                    Button { peer.leavePortal() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.accessibilityLabel("Cerrar portal")
                }
            case .idle:
                if peer.videoFilter.type == .duoPortal {
                    Button { peer.inviteToPortal() } label: { Label(peer.effectsReady ? "Invitar al Portal a dúo" : "Esperando conexión compatible…", systemImage: "sparkles") }.disabled(!peer.effectsReady)
                }
            }
            if let notice = peer.portalNotice, peer.videoFilter.type == .duoPortal || peer.portalSession.phase != .idle { Text(notice).font(.caption2).foregroundStyle(.secondary) }
        }.padding(12).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
    }
}
#endif
