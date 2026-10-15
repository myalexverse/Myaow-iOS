import SwiftUI
import SwiftData

struct RadioView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \ContactModel.displayName) private var contacts: [ContactModel]
    @State private var radio = WalkieTalkieService.shared
    @State private var selectedID: String?
    @State private var readyIDs: Set<String> = []
    @State private var authorizingID: String?
    @State private var contactError: String?
    @State private var showHelp = false
    @State private var showSoundSettings = false
    @State private var showContactPicker = false
    @State private var internetMode = false
    @AppStorage("radioTapToTalk") private var tapToTalk = false
    var contactHint: String? = nil
    var contactIDHint: String? = nil
    private var active: Bool { radio.transport.isActive }
    private var selected: ContactModel? { contacts.first { $0.myaowId == selectedID } }
    private var partner: RadioNeighbor? { radio.transport.connected.first }
    private var blockedIDs: Set<String> { ContactBlockingService.shared.blockedIds }
    private var contactSignature: [String] { contacts.map { "\($0.id)|\($0.myaowId)|\($0.displayName)|\($0.allowsLocalRadio)|\($0.radioAuthorizationOwnerId)|\($0.publicKeyHex)" } }
    private var waiting: Bool { radio.transport.requestedContactID != nil && partner == nil }
    private var receiving: Bool { if case .receiving = radio.state { return true }; return false }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                header
                Picker("Conexión", selection: $internetMode) {
                    Text("Cerca · sin internet").tag(false)
                    Text("Por internet").tag(true)
                }.pickerStyle(.segmented).onChange(of: internetMode) { _, _ in radio.deactivate() }
                if internetMode { internetHandset }
                else { handset }
                quickContacts
                if !internetMode { availability; contactsSection }
                RadioPreferencesView()
                Label("Solo entre contactos que se autorizan mutuamente.", systemImage: "lock.shield")
                    .font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                    .frame(maxWidth: .infinity).padding(.bottom, 10)
            }.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 20)
        }
        .background(AppAtmosphereStyle.page.ignoresSafeArea())
        .foregroundStyle(MyaowColor.textPrimary)
        .onAppear {
            refreshAuthorization()
            if selectedID == nil {
                selectedID = contactIDHint.flatMap { id in contacts.first(where: { $0.myaowId == id })?.myaowId }
                    ?? (contactIDHint == nil ? contacts.first?.myaowId : nil)
            }
        }
        .onChange(of: contactSignature) { _, _ in refreshAuthorization() }
        .onChange(of: blockedIDs) { _, _ in refreshAuthorization() }
        .onChange(of: IdentityManager.shared.currentIdentity.myaowId) { _, _ in refreshAuthorization() }
        .task { await ContactBlockingService.shared.loadBlockedContacts() }
        .onDisappear { radio.deactivate() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { radio.stopTransmitting() }
            if phase == .background { radio.deactivate() }
        }
        .onChange(of: CallSessionService.shared.callState) { _, state in
            if state != .idle { radio.deactivate() }
        }
        .sheet(isPresented: $showHelp) { help }
        .sheet(isPresented: $showSoundSettings) { RadioSoundSettingsSheet() }
        .sheet(isPresented: $showContactPicker) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 24) { quickContacts; contactsSection }.padding(24)
                }.background(MyaowColor.charcoal).navigationTitle("Tu gente en Radio")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { showContactPicker = false } } }
            }.preferredColorScheme(.dark)
        }
        .alert("Tu contacto quiere hablar", isPresented: Binding(
            get: { radio.transport.invitation != nil },
            set: { if !$0 { radio.transport.respond(false) } }
        )) {
            Button("Aceptar") {
                selectedID = radio.transport.invitation?.contact.id
                radio.transport.respond(true)
            }
            Button("Ahora no", role: .cancel) { radio.transport.respond(false) }
        } message: {
            Text("\(radio.transport.invitation?.name ?? "Tu contacto") te invita a una conversación privada por Radio. Su clave coincide con la de tu contacto guardado.")
        }
    }
    private var internetHandset: some View {
        VStack(spacing: 22) {
            RadioConsoleView(name: selected?.displayName ?? "Elige un contacto",
                catState: selected.flatMap { MyaowCatState(rawValue: $0.avatarCatState) } ?? .friendly,
                mode: "Por internet", state: .offline,
                detail: "Abre un canal privado. Cuando tu contacto acepte, pulsen para alternar la voz.")
            Button {
                guard let selected else { return }
                radio.deactivate()
                CallSessionService.shared.startCall(contactName: selected.displayName, myaowId: selected.myaowId, type: .radio)
            } label: {
                Label("Enlazar Radio", systemImage: "antenna.radiowaves.left.and.right")
            }.buttonStyle(GroupPrimaryStyle())
                .disabled(selected == nil || selected.map { blockedIDs.contains($0.myaowId) } == true || OnlineMessagingService.shared.status != .online)
            if OnlineMessagingService.shared.status != .online {
                Label("Sin internet. Usa Cerca si están juntos.", systemImage: "wifi.slash").font(.caption).foregroundStyle(MyaowColor.orange)
            }
        }
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Radio").font(.system(size: 32, weight: .bold)).tracking(-1.2)
                Text("Pulsa. Habla. Suelta y escucha.").font(.system(size: 14)).foregroundStyle(MyaowColor.textSecondary)
            }
            Spacer()
            Button { showSoundSettings = true } label: {
                Image(systemName: "waveform").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44).background(MyaowColor.surfaceElevated, in: Circle())
            }.accessibilityLabel("Sonido de Radio")
            Button { showContactPicker = true } label: {
                Image(systemName: "person.2").font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44).background(MyaowColor.surfaceElevated, in: Circle())
            }.accessibilityLabel("Elegir contacto de Radio")
            Button { showHelp = true } label: {
                Image(systemName: "info").font(.system(size: 17, weight: .medium))
                    .frame(width: 42, height: 42).background(MyaowColor.surfaceElevated, in: Circle())
            }.accessibilityLabel("Privacidad y ayuda de Radio")
        }
    }
    private var availability: some View {
        HStack(spacing: 12) {
            RadioHandsetGlyph().frame(width: 22, height: 24).foregroundStyle(MyaowColor.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(active ? "Disponible para tus contactos" : "Walkie-talkie privado")
                    .font(.system(size: 14, weight: .semibold))
                Text(active ? "Solo quienes tú permites pueden invitarte" : "Voz local · Sin datos móviles")
                    .font(.system(size: 11)).foregroundStyle(MyaowColor.textSecondary)
            }
            Spacer(minLength: 4)
            Button {
                if active { radio.deactivate() }
                else if readyIDs.isEmpty { contactError = "Permite Radio con un contacto para estar disponible." }
                else { radio.activate() }
            } label: {
                Image(systemName: "power").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(active ? MyaowColor.orange : MyaowColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(active ? MyaowColor.orange.opacity(0.12) : Color.white.opacity(0.04), in: Circle())
            }.accessibilityLabel(active ? "Apagar Radio" : "Estar disponible en Radio")
        }
    }
    private var quickContacts: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tus contactos").font(.system(size: 17, weight: .semibold))
            if contacts.isEmpty {
                Text("Agrega un contacto en Tu gente para empezar. Tu radio solo conecta con personas que conoces.")
                    .font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(contacts) { contact in
                        Button { choose(contact) } label: {
                            VStack(spacing: 7) {
                                avatar(contact, size: 44)
                                    .padding(4).overlay(Circle().stroke(selectedID == contact.myaowId ? MyaowColor.orange : .clear, lineWidth: 1.5))
                                Text(contact.displayName.components(separatedBy: " ").first ?? contact.displayName)
                                    .font(.system(size: 11, weight: .medium)).lineLimit(1)
                            }.frame(width: 56)
                        }.buttonStyle(.plain).accessibilityLabel("Elegir a \(contact.displayName) para Radio")
                            .accessibilityAddTraits(selectedID == contact.myaowId ? .isSelected : [])
                    }
                }.padding(.vertical, 2)
            }
        }
    }
    private func choose(_ contact: ContactModel) {
        if selectedID != contact.myaowId { radio.deactivate() }
        selectedID = contact.myaowId; contactError = nil; showContactPicker = false
        UISelectionFeedbackGenerator().selectionChanged()
    }
    private var localConsoleState: RadioConsoleState {
        if radio.isTransmitting { return .transmitting }
        if receiving { return .receiving }
        if partner != nil { return .ready }
        return waiting ? .connecting : .offline
    }
    private var handset: some View {
        VStack(spacing: 14) {
            RadioConsoleView(name: selected?.displayName ?? "Elige un contacto",
                catState: selected.flatMap { MyaowCatState(rawValue: $0.avatarCatState) } ?? .friendly,
                mode: "Cerca · sin internet", state: localConsoleState, levels: radio.audioLevels,
                detail: radio.isTransmitting ? (tapToTalk ? "Tu voz está al aire. Toca de nuevo para escuchar." : "Tu voz está al aire. Suelta para escuchar.") : receiving ? "Tu contacto tiene el turno. Espera la señal de cierre." : partner != nil ? "Canal libre. Solo tu contacto puede escucharte." : "Ambos abran Radio cerca, con Wi-Fi y Bluetooth activados.")
            if partner == nil { connectionButton }
            RadioTransmitControl(enabled: radio.canTalk, transmitting: radio.isTransmitting, receiving: receiving,
                tapToTalk: tapToTalk, diameter: 188, start: { radio.startTransmitting() }, stop: { radio.stopTransmitting() })
            if let started = radio.transmissionStartedAt {
                TimelineView(.periodic(from: started, by: 1)) { context in
                    Text("\(max(0, 60 - Int(context.date.timeIntervalSince(started)))) s · tu turno")
                        .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(MyaowColor.orange)
                }
            } else {
                Text(receiving ? "RX · escuchando" : "PTT · un turno a la vez")
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(MyaowColor.textSecondary)
            }
            if partner != nil || waiting {
                HStack(spacing: 12) {
                    Button { radio.isMuted.toggle() } label: {
                        Label(radio.isMuted ? "Silenciado" : "Sonido", systemImage: radio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 14).background(.white.opacity(0.06), in: Capsule())
                    }.accessibilityLabel(radio.isMuted ? "Activar recepción de audio" : "Silenciar recepción")
                    Button { radio.deactivate() } label: {
                        Label(waiting ? "Cancelar" : "Desconectar", systemImage: "power")
                            .frame(maxWidth: .infinity).padding(.vertical, 14).background(MyaowColor.orange.opacity(0.12), in: Capsule()).foregroundStyle(MyaowColor.orange)
                    }
                }.font(.system(size: 13, weight: .semibold))
            }
            if let error = contactError ?? radio.notice ?? radio.transport.error {
                Label(error, systemImage: "info.circle").font(.caption).foregroundStyle(MyaowColor.orange)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(MyaowColor.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    @ViewBuilder private var connectionButton: some View {
        if let selected {
            if blockedIDs.contains(selected.myaowId) {
                Text("Este contacto está bloqueado").font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
            } else if authorizingID == selected.myaowId {
                ProgressView("Verificando contacto…").tint(MyaowColor.orange).font(.system(size: 12))
            } else if waiting {
                HStack(spacing: 8) {
                    ProgressView().tint(MyaowColor.orange)
                    Text("Esperando a \(selected.displayName)…").font(.system(size: 12))
                }
                Text("Debe tenerte agregado, permitir Radio y abrir esta sección cerca de ti.")
                    .font(.system(size: 11)).foregroundStyle(MyaowColor.textSecondary).multilineTextAlignment(.center)
            } else {
                Button {
                    contactError = nil
                    if !readyIDs.contains(selected.myaowId) { authorize(selected) }
                    else {
                        if !active { radio.activate() }
                        radio.transport.connect(contactID: selected.myaowId)
                    }
                } label: {
                    Label {
                        Text(readyIDs.contains(selected.myaowId) ? "Conectar con \(selected.displayName)" : "Permitir Radio con este contacto")
                    } icon: {
                        if readyIDs.contains(selected.myaowId) { RadioHandsetGlyph().frame(width: 16, height: 18) }
                        else { Image(systemName: "lock.open") }
                    }
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(MyaowColor.orange.opacity(0.12), in: Capsule()).foregroundStyle(MyaowColor.orange)
                }.disabled(authorizingID != nil)
            }
        } else {
            Text("Agrega a alguien en Tu gente para usar Radio.").font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
        }
    }
    private var contactsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Acceso a Radio").font(.system(size: 21, weight: .bold))
                Spacer()
                Text("\(contacts.count)").font(.system(size: 13)).foregroundStyle(MyaowColor.textSecondary)
            }.padding(.bottom, 7)
            if contacts.isEmpty {
                Text("Tu radio empieza con tu gente. Agrega un contacto desde la sección Tu gente; no mostramos personas desconocidas.")
                    .font(.system(size: 14)).foregroundStyle(MyaowColor.textSecondary).padding(.vertical, 16)
            }
            ForEach(contacts) { contact in
                HStack(spacing: 10) {
                    Button {
                        choose(contact)
                    } label: {
                        HStack(spacing: 12) {
                            avatar(contact, size: 46)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(contact.displayName).font(.system(size: 15, weight: .semibold))
                                Text(contactStatus(contact)).font(.system(size: 11))
                                    .foregroundStyle(partner?.contact.id == contact.myaowId ? MyaowColor.statusGreen : MyaowColor.textSecondary)
                            }
                            Spacer()
                            if selectedID == contact.myaowId { Image(systemName: "checkmark.circle.fill").foregroundStyle(MyaowColor.orange) }
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Seleccionar a \(contact.displayName). \(contactStatus(contact))")
                    if hasPermission(contact) {
                        Menu {
                            Button("Quitar permiso de Radio", role: .destructive) { revoke(contact) }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(MyaowColor.textSecondary).frame(width: 34, height: 44)
                        }.accessibilityLabel("Privacidad de Radio con \(contact.displayName)")
                    }
                }.padding(.vertical, 13)
                Rectangle().fill(MyaowColor.borderSubtle).frame(height: 0.5)
            }
        }
    }
    private func avatar(_ contact: ContactModel, size: CGFloat) -> some View {
        ProfileAvatarView(avatarUrl: contact.avatarUrl, catState: MyaowCatState(rawValue: contact.avatarCatState) ?? .friendly,
                          size: size, showMiniCat: false, animateTransition: false)
    }
    private func contactStatus(_ contact: ContactModel) -> String {
        if blockedIDs.contains(contact.myaowId) { return "Contacto bloqueado" }
        if partner?.contact.id == contact.myaowId { return "Conectado contigo" }
        if !hasPermission(contact) { return "Radio sin permiso" }
        if !readyIDs.contains(contact.myaowId) { return "Falta verificar su clave" }
        if radio.transport.nearby.contains(where: { $0.contact.id == contact.myaowId }) { return "Radio cercana · Conectar" }
        return "Radio permitida · Sin conexión"
    }
    private func hasPermission(_ contact: ContactModel) -> Bool {
        contact.allowsLocalRadio && contact.radioAuthorizationOwnerId == IdentityManager.shared.currentIdentity.myaowId
    }
    private func refreshAuthorization() {
        radio.deactivate()
        guard IdentityManager.shared.isInitialized,
              let key = try? SecureHex.decode(IdentityManager.shared.privateKeyHex, bytes: 32) else { readyIDs = []; return }
        let credentials = contacts.filter { hasPermission($0) && !blockedIDs.contains($0.myaowId) }.compactMap { contact -> RadioContactCredential? in
            guard let key = try? SecureMessagingService.shared.cachedPeerKey(for: contact.myaowId), key.count == 32 else { return nil }
            return RadioContactCredential(id: contact.myaowId, name: contact.displayName, publicKey: key)
        }
        readyIDs = Set(credentials.map(\.id))
        radio.transport.configure(privateKey: key, contacts: credentials)
        if selectedID != nil && selected == nil { selectedID = contacts.first?.myaowId }
    }
    private func authorize(_ contact: ContactModel) {
        guard authorizingID == nil, !blockedIDs.contains(contact.myaowId) else { contactError = "Este contacto está bloqueado."; return }
        authorizingID = contact.myaowId; contactError = nil
        let owner = IdentityManager.shared.currentIdentity.myaowId
        Task { @MainActor in
            defer { authorizingID = nil }
            do {
                _ = try await SecureMessagingService.shared.peerKey(for: contact.myaowId)
                guard IdentityManager.shared.currentIdentity.myaowId == owner,
                      contacts.contains(where: { $0.id == contact.id }), !blockedIDs.contains(contact.myaowId) else { return }
                contact.allowsLocalRadio = true
                contact.radioAuthorizationOwnerId = owner
                do { try modelContext.save() } catch { modelContext.rollback(); throw error }
                refreshAuthorization()
            } catch {
                contactError = "No pudimos verificar a \(contact.displayName). La primera vez necesitas conexión al servidor; después Radio usa la clave guardada sin Internet."
            }
        }
    }
    private func revoke(_ contact: ContactModel) {
        radio.deactivate(); contact.allowsLocalRadio = false; contact.radioAuthorizationOwnerId = ""
        do { try modelContext.save(); refreshAuthorization() }
        catch { modelContext.rollback(); contactError = "No pudimos guardar el cambio. Radio se ha apagado." }
    }
    private var help: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                RadioHandsetGlyph().frame(width: 38, height: 42).foregroundStyle(MyaowColor.orange)
                Text("Tu voz.\nSolo tu gente.").font(.system(size: 34, weight: .bold))
                Text("1. Elige a un contacto y permite Radio. La primera verificación de su clave requiere conexión al servidor.")
                Text("2. Tu contacto debe tenerte agregado y permitir Radio contigo. Ambos abran Radio cerca, con Wi-Fi y Bluetooth activados.")
                Text("3. Conecta y espera su aceptación. Mantén presionado para hablar; suelta para escuchar.")
                Text("La conversación es privada entre dos contactos. No hay canales públicos ni audio para desconocidos. Puedes quitar el permiso desde los tres puntos junto al contacto.")
                Text("En Por internet pueden conversar a distancia después de aceptar la invitación. En modo Cerca, después de verificar sus claves, la voz funciona localmente sin Internet. Mantengan Radio abierta: al salir o bloquear el teléfono se desconecta. El alcance depende del entorno.")
                    .foregroundStyle(MyaowColor.textSecondary)
                Button("Entendido") { showHelp = false }.font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(16).background(MyaowColor.orange, in: Capsule()).foregroundStyle(.black)
            }.font(.system(size: 14)).padding(28)
        }.background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary).presentationDragIndicator(.visible)
    }
}

/// Code-native symbol, consistent on every supported iOS version.
private struct RadioHandsetGlyph: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: w * 0.05).frame(width: w * 0.09, height: h * 0.30).offset(x: w * 0.27)
                RoundedRectangle(cornerRadius: w * 0.13).stroke(lineWidth: w * 0.07)
                    .frame(width: w * 0.66, height: h * 0.70).offset(x: w * 0.20, y: h * 0.27)
                RoundedRectangle(cornerRadius: w * 0.04).opacity(0.45)
                    .frame(width: w * 0.38, height: h * 0.17).offset(x: w * 0.34, y: h * 0.41)
                ForEach(0..<3, id: \.self) { line in
                    Capsule().frame(width: w * 0.25, height: h * 0.035).offset(x: w * 0.405, y: h * (0.69 + Double(line) * 0.075))
                }
                Capsule().frame(width: w * 0.08, height: h * 0.20).offset(x: w * 0.04, y: h * 0.45)
            }
        }.accessibilityHidden(true)
    }
}
