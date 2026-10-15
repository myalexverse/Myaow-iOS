import SwiftUI
import SwiftData
#if canImport(WebRTC)
import WebRTC
#endif

public struct CallOverlayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Query private var contacts: [ContactModel]
    @State private var call = CallSessionService.shared
    @State private var peer = WebRTCPeerService.shared
    @State private var controlsVisible = true
    @State private var localIsMain = false
    @State private var fitVideo = true
    @State private var settings = false
    @State private var filters = false
    public init() {}
    private var ended: Bool { call.callState == .ended }
    private var contact: ContactModel? { contacts.first { $0.myaowId == call.activeCallMyaowId } }
    private var active: Bool { call.callState == .connected }
    private var hasVideo: Bool {
        #if canImport(WebRTC)
        call.callType == .video && peer.remoteVideoTrack != nil && !ended
        #else
        false
        #endif
    }
    public var body: some View {
        if call.callType == .radio { RadioSessionView() }
        else { callBody }
    }
    private var callBody: some View {
        ZStack {
            Color(hex: "#08090B").ignoresSafeArea()
            videoStage
            if controlsVisible || !hasVideo {
                VStack(spacing: 18) {
                    HStack {
                        if !ended {
                            Button { call.minimize() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left").frame(width: 44, height: 44) }
                                .accessibilityLabel("Minimizar llamada")
                        }
                        if active && call.callType != .radio {
                            Button { CallPictureInPicture.shared.start() } label: { Image(systemName: "pip.enter").frame(width: 44, height: 44) }.accessibilityLabel("Ventana flotante sobre otras apps")
                        }
                        Text(call.callType.rawValue.uppercased()).font(.caption.weight(.semibold)).tracking(1)
                        Spacer()
                        if call.callType == .video && !ended {
                            #if canImport(WebRTC)
                            Button { filters = true } label: { Image(systemName: "camera.filters").frame(width: 44, height: 44) }.accessibilityLabel("Filtros de video")
                            #endif
                            Button { settings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44) }.accessibilityLabel("Opciones de video")
                        }
                    }
                    Spacer(minLength: 12)
                    if !hasVideo {
                        MyaowCatView(state: contact.flatMap { MyaowCatState(rawValue: $0.avatarCatState) } ?? .friendly,
                            style: .darkOnOrange, size: 190, isInteractive: false, speakingLevel: active ? peer.remoteSpeakingLevel : 0)
                            .shadow(color: MyaowColor.orange.opacity(0.2), radius: 28)
                    }
                    VStack(spacing: 8) {
                        Text(call.activeCallContactName).font(.system(size: hasVideo ? 23 : 32, weight: .semibold, design: .rounded)).multilineTextAlignment(.center)
                        Text(active ? call.durationFormatted : call.callState.rawValue).font(.subheadline.monospacedDigit()).foregroundStyle(MyaowColor.orange)
                        if ended { Text(call.endReason).font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center) }
                    }
                    Spacer(minLength: 12)
                    if hasVideo { thumbnail }
                    #if canImport(WebRTC)
                    if active && call.callType == .video && (peer.videoFilter.type == .duoPortal || peer.portalSession.phase != .idle) { CallPortalControls() }
                    if let notice = peer.filterNotice { Text(notice).font(.caption).foregroundStyle(.orange) }
                    #endif
                    if ended {
                        Button("Volver al chat") { call.dismissCall(); dismiss() }.buttonStyle(GroupPrimaryStyle())
                        Button("Volver a llamar") { call.startCall(contactName: call.activeCallContactName, myaowId: call.activeCallMyaowId, type: call.callType) }.tint(MyaowColor.orange)
                    } else if call.callState == .incoming {
                        HStack(spacing: 50) {
                            control("Rechazar", symbol: "phone.down.fill", color: .red) { call.endCall() }
                            control("Contestar", symbol: "phone.fill", color: .green) { call.acceptCall() }
                        }
                    } else {
                        HStack(spacing: 14) {
                            if call.callType != .radio {
                                control(call.isMuted ? "Activar micrófono" : "Silenciar", symbol: call.isMuted ? "mic.slash.fill" : "mic.fill") { call.toggleMute() }
                            }
                            control(call.isSpeakerOn ? "Auricular" : "Altavoz", symbol: call.isSpeakerOn ? "speaker.wave.2.fill" : "ear") { call.toggleSpeaker() }
                            if call.callType == .video {
                                control(call.isCameraOff ? "Activar cámara" : "Cámara", symbol: call.isCameraOff ? "video.slash.fill" : "video.fill") { call.toggleCamera() }
                            }
                            control("Finalizar", symbol: "phone.down.fill", color: .red) { call.endCall() }
                        }
                    }
                }.padding(24)
                .background {
                    if hasVideo { LinearGradient(colors: [.black.opacity(0.75), .clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false) }
                }
                .allowsHitTesting(true)
            }
            if hasVideo, !controlsVisible {
                VStack { HStack { Spacer(); Button { controlsVisible = true } label: { Image(systemName: "ellipsis").padding(14).background(.black.opacity(0.5), in: Circle()) }.accessibilityLabel("Mostrar controles") }; Spacer() }.padding(20)
            }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .interactiveDismissDisabled(!ended)
        .onChange(of: call.callState) { _, state in if state == .idle { dismiss() }; if state == .ended { controlsVisible = true } }
        .onDisappear { call.stopRadioTransmission() }
        .alert("Ventana flotante", isPresented: Binding(get: { CallPictureInPicture.shared.notice != nil }, set: { if !$0 { CallPictureInPicture.shared.notice = nil } })) {
            Button("Entendido", role: .cancel) {}
        } message: { Text(CallPictureInPicture.shared.notice ?? "") }
        #if canImport(WebRTC)
        .sheet(isPresented: $filters) { CallFilterSheet() }
        .onChange(of: peer.portalSession.phase) { _, phase in if case .invited = phase { controlsVisible = true } }
        #endif
        .sheet(isPresented: $settings) {
            NavigationStack {
                Form {
                    Toggle("Mostrar imagen completa", isOn: $fitVideo)
                    Button("Intercambiar video principal") { localIsMain.toggle(); settings = false }
                    Button("Cambiar cámara frontal / trasera") { call.flipCamera() }.disabled(call.isCameraOff)
                    Button(call.isCameraOff ? "Encender cámara" : "Apagar cámara") { call.toggleCamera() }
                    Text("Toca el video para ocultar o mostrar controles. Toca la miniatura para intercambiar las imágenes.").font(.footnote)
                }.navigationTitle("Video").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { settings = false } } }
            }.presentationDetents([.medium])
        }
    }
    @ViewBuilder private var videoStage: some View {
        #if canImport(WebRTC)
        if hasVideo, let remote = peer.remoteVideoTrack {
            let track = localIsMain ? peer.localVideoTrack ?? remote : remote
            if localIsMain && call.isCameraOff {
                Image(systemName: "video.slash.fill").font(.largeTitle).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle()).onTapGesture { controlsVisible.toggle() }
            } else {
                CallVideoSurface(track: track, fit: fitVideo).scaleEffect(x: localIsMain && call.isFrontCamera ? -1 : 1, y: 1)
                    .ignoresSafeArea().contentShape(Rectangle()).onTapGesture { controlsVisible.toggle() }
                    .accessibilityLabel("Video principal").accessibilityAction(named: "Mostrar u ocultar controles") { controlsVisible.toggle() }
            }
        }
        #endif
    }
    @ViewBuilder private var thumbnail: some View {
        #if canImport(WebRTC)
        if let local = peer.localVideoTrack {
            HStack {
                Spacer()
                Button { localIsMain.toggle() } label: {
                    ZStack(alignment: .bottomLeading) {
                        if !localIsMain && call.isCameraOff { Color(white: 0.15); Image(systemName: "video.slash").frame(maxWidth: .infinity, maxHeight: .infinity) }
                        else { CallVideoSurface(track: localIsMain ? peer.remoteVideoTrack ?? local : local, fit: false).scaleEffect(x: !localIsMain && call.isFrontCamera ? -1 : 1, y: 1) }
                        Text(localIsMain ? call.activeCallContactName : "Tú").font(.caption).padding(8).background(.black.opacity(0.4))
                    }.frame(width: 100, height: 140).clipShape(RoundedRectangle(cornerRadius: 20))
                }.accessibilityLabel("Intercambiar video principal y miniatura")
            }
        }
        #endif
    }
    private func control(_ title: String, symbol: String, color: Color = .white.opacity(0.12), action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 22)).frame(width: 56, height: 56).background(color, in: Circle())
                Text(title).font(.system(size: 10)).lineLimit(2).frame(height: 26)
            }.frame(maxWidth: .infinity)
        }.accessibilityLabel(title)
    }
}

struct MinimizedCallBubble: View {
    @State private var call = CallSessionService.shared
    @State private var peer = WebRTCPeerService.shared
    @State private var offset = CGSize.zero
    @GestureState private var drag = CGSize.zero
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 4) {
                Button { call.isMinimized = false } label: {
                    if call.callType == .radio {
                        Image(systemName: call.radioReceiving ? "speaker.wave.2.fill" : "antenna.radiowaves.left.and.right")
                            .font(.system(size: 26)).foregroundStyle(call.radioReceiving ? MyaowColor.statusGreen : MyaowColor.orange)
                            .frame(width: 68, height: 68).background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 22))
                            .overlay(RoundedRectangle(cornerRadius: 22).stroke(MyaowColor.orange.opacity(0.6), lineWidth: 1))
                    } else {
                        MyaowCatView(state: call.activeCallCatState, style: .darkOnOrange, size: 68, isInteractive: false, speakingLevel: peer.remoteSpeakingLevel)
                            .background(.black.opacity(0.85), in: Circle()).overlay(Circle().stroke(MyaowColor.orange, lineWidth: 2))
                    }
                }.accessibilityLabel("Volver a \(call.callType == .radio ? "Radio" : "la llamada") con \(call.activeCallContactName)")
                Text(call.callState == .ended ? "Finalizada" : call.callState != .connected ? "Conectando" : call.callType == .radio ? (call.radioReceiving ? "Recibiendo" : "Radio") : call.durationFormatted)
                    .font(.caption2.monospacedDigit()).foregroundStyle(.white).padding(5).background(.black.opacity(0.85), in: Capsule())
            }
            .position(x: min(max(44, geometry.size.width - 52 + offset.width + drag.width), max(44, geometry.size.width - 44)),
                      y: min(max(56, 90 + offset.height + drag.height), max(56, geometry.size.height - 140)))
            .simultaneousGesture(DragGesture(minimumDistance: 10).updating($drag) { value, state, _ in state = value.translation }.onEnded { value in
                offset.width = min(8, max(96 - geometry.size.width, offset.width + value.translation.width))
                offset.height = min(max(0, geometry.size.height - 230), max(-34, offset.height + value.translation.height))
            })
        }
    }
}

#if canImport(WebRTC)
struct CallVideoSurface: UIViewRepresentable {
    let track: RTCVideoTrack
    var fit: Bool
    final class Coordinator { var track: RTCVideoTrack? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero); view.videoContentMode = fit ? .scaleAspectFit : .scaleAspectFill
        track.add(view); context.coordinator.track = track; return view
    }
    func updateUIView(_ view: RTCMTLVideoView, context: Context) {
        view.videoContentMode = fit ? .scaleAspectFit : .scaleAspectFill
        if context.coordinator.track !== track { context.coordinator.track?.remove(view); track.add(view); context.coordinator.track = track }
    }
    static func dismantleUIView(_ view: RTCMTLVideoView, coordinator: Coordinator) { coordinator.track?.remove(view); coordinator.track = nil }
}
#endif
