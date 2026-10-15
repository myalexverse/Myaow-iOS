//
//  SettingsView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//  Rediseño: De pantalla de ajustes a "centro de identidad"
//  "Este es mi pequeño espacio dentro de Myaow."
//

import SwiftUI
import SwiftData

public struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var identityManager = IdentityManager.shared
    
    @State private var showingLaunchAppearance = false
    @State private var showingEmotionPickerSheet = false
    @State private var showingEditProfile = false
    @State private var showingPhotoPickerSheet = false
    @State private var showingBioSheet = false
    @State private var editNameInput = ""
    @State private var activeSessions: [[String: Any]] = []
    
    public init() {}
    
    private var currentCatState: MyaowCatState {
        MyaowCatState(rawValue: identityManager.currentIdentity.avatarStateName) ?? .friendly
    }
    
    private var statusText: String {
        switch currentCatState {
        case .happy, .friendly: return "Disponible para hablar"
        case .busy, .thinking: return "Ocupado ahora"
        case .sleeping, .exhausted: return "Descansando"
        case .party: return "¡De fiesta!"
        case .drunk: return "Una noche de más"
        case .laughing: return "No puedo parar de reír"
        case .shy: return "Me da un poquito de pena"
        case .crying: return "Hoy necesito compañía"
        case .skeptical: return "No sé, no me convence"
        case .mischievous: return "Algo estoy tramando"
        case .gossiping: return "Te encanta saber lo que pasa"
        case .calm: return "Todo tranquilo"
        case .curious: return "Explorando"
        case .cool: return "Relajado"
        case .ninja: return "Modo fantasma"
        case .inLove: return "Enamorado"
        case .sad: return "Necesita un abrazo"
        case .angry: return "Mejor no molestar"
        default: return "Disponible"
        }
    }
    
    @State private var showingWallpaper = false
    @State private var showingQR = false
    @State private var showingSessions = false
    @State private var sessionsLoading = false
    @State private var sessionsError: String?

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MyaowScreenHeader(title: "Tu espacio", subtitle: "Así se siente ser tú.") {
                        MyaowIconAction(symbol: "qrcode", label: "Compartir mi código") { showingQR = true }
                    }
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Original.\nComo tú.")
                                .font(.system(size: 32, weight: .semibold)).tracking(-1.2)
                            Text("MYAOW / YOUR WORLD")
                                .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).opacity(0.6)
                        }
                        .foregroundStyle(AppAtmosphereStore.shared.isEnabled ? MyaowColor.textPrimary : MyaowColor.charcoal)
                        .padding(.leading, 24)
                        Spacer(minLength: 0)
                        MyaowSculptureMark().frame(width: 164, height: 178).padding(.trailing, -5)
                    }
                    .frame(maxWidth: .infinity)
                    .background(AppAtmosphereStore.shared.isEnabled ? AppAtmosphereStyle.card : MyaowColor.textPrimary, in: RoundedRectangle(cornerRadius: 24))
                    .padding(.horizontal, 24)

                    HStack(spacing: 16) {
                        Button { showingPhotoPickerSheet = true } label: {
                            ProfileAvatarView(avatarUrl: identityManager.profilePhotoUrl, avatarImageData: identityManager.profilePhotoData, catState: currentCatState, size: 68, showMiniCat: false, animateTransition: false)
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "camera.fill").font(.system(size: 10)).foregroundStyle(.black)
                                        .frame(width: 24, height: 24).background(MyaowColor.orange, in: Circle())
                                }
                        }.accessibilityLabel("Cambiar foto de perfil")
                        VStack(alignment: .leading, spacing: 7) {
                            Text(identityManager.currentIdentity.displayName).font(.system(size: 23, weight: .semibold)).tracking(-0.6).foregroundStyle(MyaowColor.textPrimary)
                            Text(identityManager.currentIdentity.customUsername.map { "@\($0)" } ?? identityManager.currentIdentity.myaowId)
                                .font(.system(size: 14)).foregroundStyle(MyaowColor.textSecondary)
                        }
                        Spacer(minLength: 3)
                        Button { showingEditProfile = true } label: {
                            Image(systemName: "pencil").font(.system(size: 16)).foregroundStyle(MyaowColor.textSecondary).frame(width: 40, height: 44)
                        }.accessibilityLabel("Editar nombre")
                    }
                    .padding(.horizontal, 24)

                    Button { showingEmotionPickerSheet = true } label: {
                        HStack(spacing: 12) {
                            MyaowCatView(state: currentCatState, style: .orangeOnTransparent, size: 36, isInteractive: false)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentCatState.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(MyaowColor.textPrimary)
                                Text("¿Cómo te sientes hoy?").font(.system(size: 13)).foregroundStyle(MyaowColor.textSecondary)
                            }
                            Spacer()
                            Text("Cambiar").font(.system(size: 13, weight: .semibold)).foregroundStyle(MyaowColor.orange)
                        }.padding(16).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)

                    MyaowSectionLabel(title: "Hazlo tuyo").padding(.horizontal, 24)
                    VStack(spacing: 0) {
                        NavigationLink { AppearanceSettingsView() } label: { MyaowSettingsRow(symbol: "circle.lefthalf.filled", title: "Apariencia", subtitle: "Tu estilo, tus colores") }
                        Divider().overlay(MyaowColor.borderSubtle).padding(.leading, 60)
                        Button { showingWallpaper = true } label: { MyaowSettingsRow(symbol: "photo.on.rectangle", title: "Fondos de chat") }
                        Divider().overlay(MyaowColor.borderSubtle).padding(.leading, 60)
                        Button { showingBioSheet = true } label: { MyaowSettingsRow(symbol: "text.bubble", title: "Acerca de ti", subtitle: identityManager.currentIdentity.bioStatus) }
                    }
                    .buttonStyle(.plain)
                    .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 24)

                    MyaowSectionLabel(title: "Tu cuenta").padding(.horizontal, 24)
                    VStack(spacing: 0) {
                        NavigationLink { PrivacySecuritySettingsView() } label: { MyaowSettingsRow(symbol: "hand.raised", title: "Privacidad y seguridad") }
                        Divider().overlay(MyaowColor.borderSubtle).padding(.leading, 60)
                        Button { showingSessions = true } label: { MyaowSettingsRow(symbol: "laptopcomputer.and.iphone", title: "Dispositivos") }
                        Divider().overlay(MyaowColor.borderSubtle).padding(.leading, 60)
                        NavigationLink { AdvancedSettingsView() } label: { MyaowSettingsRow(symbol: "slider.horizontal.3", title: "Conexión y ajustes") }
                    }
                    .buttonStyle(.plain)
                    .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, 24)
                    MomentsReelView().padding(.top, 4)
                    HStack { Spacer(); MyaowWordmarkView(fontSize: 22, textColor: MyaowColor.textTertiary); Spacer() }.padding(.vertical, 16)
                }.padding(.bottom, 26)
            }
            .background(AppAtmosphereStyle.page)
            .containerBackground(AppAtmosphereStyle.page, for: .navigation)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showingLaunchAppearance) { AppearanceSettingsView() }
            .onAppear {
                if DesignPreviewData.consumeLaunchRoute("--appearance-preview") { showingLaunchAppearance = true }
            }
            .sheet(isPresented: $showingEmotionPickerSheet) { MyaowEmotionPickerSheetView() }
            .sheet(isPresented: $showingEditProfile) { editProfileSheet }
            .sheet(isPresented: $showingWallpaper) { ChatWallpaperPickerView() }
            .sheet(isPresented: $showingQR) { MyQRCodeView() }
            .sheet(isPresented: $showingBioSheet) { EditBioStatusSheetView() }
            .sheet(isPresented: $showingSessions) { sessionsSheet }
            .sheet(isPresented: $showingPhotoPickerSheet) {
                ProfilePhotoPickerSheet(currentAvatarUrl: identityManager.profilePhotoUrl, currentAvatarData: identityManager.profilePhotoData, catState: currentCatState,
                    onPhotoSelected: { identityManager.saveProfilePhoto($0); showingPhotoPickerSheet = false },
                    onRemovePhoto: { identityManager.removeProfilePhoto(); showingPhotoPickerSheet = false })
            }
        }
    }

    private var sessionsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if sessionsLoading {
                        ProgressView("Consultando dispositivos…").padding(32)
                    } else if let sessionsError {
                        MyaowEmptyState(title: "Sin conexión al servidor", message: sessionsError, symbol: "wifi.slash", actionTitle: "Reintentar", action: fetchSessions)
                    } else if activeSessions.isEmpty {
                        MyaowEmptyState(title: "Sin sesiones remotas", message: "Este dispositivo conserva tu identidad local.", symbol: "iphone")
                    } else {
                        ForEach(Array(activeSessions.enumerated()), id: \.offset) { _, session in
                            MyaowSettingsRow(symbol: "iphone", title: session["device_name"] as? String ?? session["deviceName"] as? String ?? "Dispositivo", subtitle: session["last_active"] as? String)
                                .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }.padding(24)
            }
            .background(MyaowColor.charcoal)
            .navigationTitle("Dispositivos").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showingSessions = false } } }
            .onAppear(perform: fetchSessions)
        }.presentationDragIndicator(.visible)
    }

    // MARK: - Header Bar
    private var headerBar: some View {
        HStack {
            Text("Tú")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            NavigationLink(destination: AdvancedSettingsView()) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.3))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }
    
    // MARK: - Tu Estado (prominent section)
    private var stateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TU ESTADO")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.25))
                .tracking(0.6)
                .padding(.horizontal, 24)
            
            Button(action: { showingEmotionPickerSheet = true }) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(MyaowColor.orange.opacity(0.12))
                            .frame(width: 48, height: 48)
                        
                        MyaowCatView(state: currentCatState, style: .darkOnOrange, size: 32, isInteractive: false)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(currentCatState.displayName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Cambia cómo te ven los demás")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.35))
                    }
                    
                    Spacer()
                    
                    Text("Cambiar")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(MyaowColor.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(MyaowColor.orange.opacity(0.12))
                        .clipShape(Capsule())
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.15))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Advanced (discrete)
    private var advancedLink: some View {
        NavigationLink(destination: AdvancedSettingsView()) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                Text("Configuración avanzada")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
            }
            .foregroundColor(Color.white.opacity(0.2))
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Edit Profile Sheet
    private var editProfileSheet: some View {
        NavigationStack {
            ZStack {
                MyaowColor.background.ignoresSafeArea()
                
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TU NOMBRE PÚBLICO")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(MyaowColor.orange)
                        
                        TextField("Nombre", text: $editNameInput)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Spacer()
                    
                    Button(action: {
                        let cleaned = editNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleaned.isEmpty {
                            identityManager.updateDisplayName(cleaned)
                        }
                        showingEditProfile = false
                    }) {
                        Text("Guardar")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(MyaowColor.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Editar Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { showingEditProfile = false }
                        .foregroundColor(MyaowColor.orange)
                }
            }
            .onAppear {
                editNameInput = identityManager.currentIdentity.displayName
            }
        }
        .presentationDetents([.fraction(0.45)])
    }
    
    // MARK: - Fetch Sessions from Server
    private func fetchSessions() {
        guard !sessionsLoading else { return }
        sessionsLoading = true
        sessionsError = nil
        Task { @MainActor in
            defer { sessionsLoading = false }
            guard let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.httpURL else {
                sessionsError = "Revisa la dirección de conexión en Ajustes."
                return
            }
            var request = URLRequest(url: base.appendingPathComponent("api/v1/sessions").appendingPathComponent(identityManager.currentIdentity.myaowId))
            request.timeoutInterval = 10
            OnlineMessagingService.shared.authenticatedRequest(&request)
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sessions = json["sessions"] as? [[String: Any]] else { throw URLError(.badServerResponse) }
                activeSessions = sessions
            } catch { sessionsError = "No pudimos consultar tus sesiones. Intenta cuando tengas conexión." }
        }
    }

}

#Preview {
    SettingsView()
        .modelContainer(for: [ContactModel.self, ConversationModel.self, MessageModel.self, MeshNodeModel.self, MomentModel.self], inMemory: true)
}
