//
//  OnboardingRegistrationView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import PhotosUI
import AuthenticationServices

public struct OnboardingRegistrationView: View {
    @State private var currentStep: Int = 0
    
    // Perfil Form State
    @State private var betaInvite = ""
    private var requiresBetaInvite: Bool { Bundle.main.object(forInfoDictionaryKey: "MyaowBetaInviteRequired") as? String == "YES" }
    @State private var displayName: String = ""
    @State private var customUsername: String = ""
    @State private var isUsernameManuallyEdited: Bool = false
    @State private var selectedCatState: MyaowCatState = .friendly
    @State private var usePhotoGallery: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedPhotoData: Data? = nil
    
    private var generatedMyaowId: String { IdentityManager.shared.currentIdentity.myaowId }
    @State private var appleSignInManager = AppleSignInManager.shared
    
    @State private var usernameCheckTask: Task<Void, Never>?
    @State private var usernameMessage: String?
    @State private var registrationError: String?
    @State private var isSubmitting = false
    @State private var isLoadingPhoto = false
    @State private var relayAddress = OnlineMessagingService.shared.relayHost
    @State private var showsServerSettings = false

    @State private var isUsernameAvailable: Bool? = nil
    @State private var isCheckingUsername: Bool = false
    
    private var selectableEmotions: [MyaowCatState] {
        [.happy, .purring, .playful, .curious, .busy, .thinking, .bored, .gossiping, .cool, .hungry, .inLove, .sad, .angry, .exhausted, .party, .ninja, .calm, .surprised, .friendly, .neutral]
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Barra de progreso superior
                progressBar
                    .padding(.top, 16)
                    .padding(.horizontal, 24)
                
                if currentStep > 0 {
                    HStack {
                        Button { currentStep -= 1 } label: {
                            Label("Atrás", systemImage: "arrow.left")
                        }
                        .disabled(isSubmitting)
                        Spacer()
                        Text("0\(currentStep + 1) / 03")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(MyaowColor.textSecondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                Group {
                    switch currentStep {
                    case 0: step0WelcomeView
                    case 1: step1ProfileView
                    default: step2IdentityReadyView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            }
        }
        .onDisappear { usernameCheckTask?.cancel() }
        .alert("No pudimos continuar", isPresented: Binding(
            get: { registrationError != nil },
            set: { if !$0 { registrationError = nil } }
        )) {
            Button("Entendido", role: .cancel) { registrationError = nil }
        } message: {
            Text(registrationError ?? "")
        }
    }
    
    // MARK: - Barra de Progreso
    private var progressBar: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { index in
                Capsule()
                    .fill(index <= currentStep ? MyaowColor.orange : MyaowColor.surfaceSecondary)
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.25), value: currentStep)
            }
        }
    }
    
    // MARK: - Paso 0: Bienvenida
    private var step0WelcomeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    MyaowWordmarkView(fontSize: 30, textColor: .white)
                    Spacer()
                    Text("TU MUNDO. TU SEÑAL.")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(MyaowColor.textSecondary)
                }
                MyaowEditorialHero()
                    .frame(height: 270)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tu mundo,\nmás cerca.")
                        .font(.system(size: 42, weight: .semibold))
                        .tracking(-1.5)
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Un espacio para hablar a tu manera. Sin compartir tu número de teléfono.")
                        .font(.myaowBody)
                        .foregroundStyle(MyaowColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 16) {
                    Label("Sin teléfono", systemImage: "person.crop.circle")
                    Label("Conexión local", systemImage: "antenna.radiowaves.left.and.right")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(MyaowColor.textSecondary)

                VStack(spacing: 12) {
                    MyaowPillButton("Crear mi identidad", icon: "arrow.right", style: .primary, isFullWidth: true) {
                        currentStep = 1
                    }
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        if case .failure(let error) = result {
                            if (error as? ASAuthorizationError)?.code != .canceled {
                                registrationError = "Apple no pudo completar el acceso. Intenta de nuevo o crea tu identidad manualmente."
                            }
                            return
                        }
                        appleSignInManager.handleAuthorizationResult(result: result) { resolvedName, _ in
                            displayName = resolvedName
                            customUsername = sanitizeHandle(resolvedName)
                            currentStep = 1
                        }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(Capsule())
                }
                Text("Tu gato. Tu personalidad. Tu Myaow.")
                    .font(.myaowCaption)
                    .foregroundStyle(MyaowColor.textTertiary)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }

    private func welcomeFeatureRow(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(MyaowColor.surface)
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MyaowColor.orange)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.myaowBodyMedium)
                    .foregroundColor(MyaowColor.textPrimary)
                Text(desc)
                    .font(.myaowCaption)
                    .foregroundColor(MyaowColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }
    
    // MARK: - Paso 1: Configurar Perfil
    private var step1ProfileView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Tu Perfil")
                        .font(.system(size: 26, weight: .bold, design: .default))
                        .foregroundColor(MyaowColor.textPrimary)
                    
                    Text("Elige tu foto de perfil o personaliza tu avatar Myaow.")
                        .font(.myaowBody)
                        .foregroundColor(MyaowColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)
                
                // Avatar Principal
                ZStack {
                    if let data = selectedPhotoData, usePhotoGallery {
                        MyaowAvatarView(source: .data(data), size: 100)
                    } else {
                        MyaowCatView(state: selectedCatState, style: .darkOnOrange, size: 100, isInteractive: false)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(MyaowColor.orange, lineWidth: 3)
                )
                .shadow(color: MyaowColor.orange.opacity(0.25), radius: 10, x: 0, y: 4)
                
                // Toggle entre Mascota y Galería
                HStack(spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            usePhotoGallery = false
                        }
                        // Don't clear selectedPhotoData — preserve it for switching back
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "pawprint.fill")
                            Text("Mascota")
                        }
                        .font(.myaowCaptionMedium)
                        .foregroundColor(!usePhotoGallery ? .white : MyaowColor.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(!usePhotoGallery ? MyaowColor.orange : MyaowColor.surface)
                        .clipShape(Capsule())
                    }
                    
                    // Galería button: if photo already selected, just toggle back
                    Button(action: {
                        if selectedPhotoData != nil {
                            // Photo already loaded, just switch to it
                            withAnimation(.easeInOut(duration: 0.2)) {
                                usePhotoGallery = true
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text(selectedPhotoData != nil ? "Tu Foto" : "Galería")
                        }
                        .font(.myaowCaptionMedium)
                        .foregroundColor(usePhotoGallery ? .white : MyaowColor.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(usePhotoGallery ? MyaowColor.orange : MyaowColor.surface)
                        .clipShape(Capsule())
                    }
                    .overlay {
                        // Invisible PhotosPicker on top to allow picking a new photo
                        if selectedPhotoData == nil {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                Color.clear
                            }
                        }
                    }
                    
                    // Separate change photo button if already has photo
                    if selectedPhotoData != nil {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                                .font(.system(size: 14))
                                .foregroundColor(MyaowColor.textSecondary)
                                .padding(8)
                                .background(MyaowColor.surface)
                                .clipShape(Circle())
                        }
                    }
                }
                .onChange(of: selectedPhotoItem) { _, newItem in
                    Task { @MainActor in
                        isLoadingPhoto = true
                        defer { isLoadingPhoto = false }
                        do {
                            guard let data = try await newItem?.loadTransferable(type: Data.self),
                                  let image = UIImage(data: data) else { return }
                            guard selectedPhotoItem == newItem else { return }
                            let ratio = min(1, 1024 / max(image.size.width, image.size.height))
                            let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
                            let format = UIGraphicsImageRendererFormat()
                            format.scale = 1
                            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                                image.draw(in: CGRect(origin: .zero, size: size))
                            }
                            selectedPhotoData = resized.jpegData(compressionQuality: 0.82)
                            usePhotoGallery = true
                        } catch {
                            registrationError = "No pudimos cargar esa foto. Elige otra imagen."
                        }
                    }
                }
                
                // Selector de Estados de Mascota
                if !usePhotoGallery {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ESTADO DE ÁNIMO DE LA MASCOTA")
                            .font(.myaowMicro)
                            .foregroundColor(MyaowColor.textSecondary)
                            .padding(.horizontal, 4)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(selectableEmotions) { state in
                                    emotionCell(state: state)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                // Campos de Entrada: Nombre & Username Automático
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TU NOMBRE PÚBLICO")
                            .font(.myaowMicro)
                            .foregroundColor(MyaowColor.textSecondary)
                            .padding(.horizontal, 4)
                        
                        TextField("Ej: Alex Doven", text: $displayName)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                            .font(.myaowBody)
                            .foregroundColor(MyaowColor.textPrimary)
                            .padding(14)
                            .background(MyaowColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(MyaowColor.borderSubtle, lineWidth: 1)
                            )
                            .onChange(of: displayName) { _, newName in
                                if !isUsernameManuallyEdited {
                                    let sanitized = sanitizeHandle(newName)
                                    customUsername = sanitized
                                }
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("NOMBRE DE USUARIO")
                                .font(.myaowMicro)
                                .foregroundColor(MyaowColor.textSecondary)
                            
                            Spacer()
                            
                            if !isUsernameManuallyEdited && !customUsername.isEmpty {
                                Text("Automático ✨")
                                    .font(.system(size: 10, weight: .medium, design: .default))
                                    .foregroundColor(MyaowColor.orange)
                            }
                        }
                        .padding(.horizontal, 4)
                        
                        HStack(spacing: 4) {
                            Text("@")
                                .font(.myaowBodyMedium)
                                .foregroundColor(MyaowColor.orange)
                            
                            TextField("usuario", text: $customUsername)
                                .font(.myaowBody)
                                .foregroundColor(MyaowColor.textPrimary)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .onChange(of: customUsername) { _, newValue in
                                    // Si el usuario escribe manualmente algo diferente al cálculo automático
                                    let autoExpected = sanitizeHandle(displayName)
                                    if customUsername != autoExpected && !customUsername.isEmpty {
                                        isUsernameManuallyEdited = true
                                    }
                                    checkUsernameAvailability(newValue)
                                }
                            
                            if isCheckingUsername {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else if let available = isUsernameAvailable, !customUsername.isEmpty {
                                Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(available ? .green : .red)
                            }
                        }
                        .padding(14)
                        .background(MyaowColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(MyaowColor.borderSubtle, lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 20)
                
                if let usernameMessage {
                    Text(usernameMessage)
                        .font(.myaowCaption)
                        .foregroundStyle(isUsernameAvailable == false ? Color.red : MyaowColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                }
                if isLoadingPhoto { ProgressView("Preparando foto…") }
                #if DEBUG
                serverSettings
                    .padding(.horizontal, 20)
                #endif

                MyaowPillButton(
                    displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Continuar sin nombre" : "Continuar",
                    icon: "arrow.right",
                    style: .primary,
                    isFullWidth: true
                ) {
                    customUsername = RegistrationInput.normalizedUsername(customUsername)
                    withAnimation { currentStep = 2 }
                }
                .disabled(!canContinue || isLoadingPhoto)
                .opacity(canContinue && !isLoadingPhoto ? 1 : 0.5)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { checkUsernameAvailability(customUsername) }
    }
    
    // MARK: - Paso 2: Identidad Creada & Llave QR
    private var step2IdentityReadyView: some View {
        ScrollView {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 64))
                    .foregroundColor(MyaowColor.orange)
                
                Text("Tu identidad, a tu manera.")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundColor(MyaowColor.textPrimary)
                
                Text("Revisa tu perfil. Al continuar lo registraremos para que tu gente pueda encontrarte.")
                    .font(.myaowBody)
                    .multilineTextAlignment(.center)
                    .foregroundColor(MyaowColor.textSecondary)
                    .padding(.horizontal, 24)
            }
            
            // Tarjeta de Identidad Resumen
            MyaowCard {
                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        if let data = selectedPhotoData, usePhotoGallery {
                            MyaowAvatarView(source: .data(data), size: 54)
                        } else {
                            MyaowAvatarView(source: .cat(state: selectedCatState, style: .darkOnOrange), size: 54)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Usuario Myaow" : displayName)
                                .font(.myaowBodyMedium)
                                .foregroundColor(MyaowColor.textPrimary)
                            
                            if !customUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("@\(customUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
                                    .font(.myaowCaption)
                                    .foregroundColor(MyaowColor.orange)
                            }
                            
                            Text(generatedMyaowId)
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(MyaowColor.textTertiary)
                        }
                        Spacer()
                    }
                    
                    Divider().background(MyaowColor.borderSubtle)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(MyaowColor.orange)
                        Text("Tu identificador se conserva en este dispositivo")
                            .font(.myaowMicro)
                            .foregroundColor(MyaowColor.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            if requiresBetaInvite {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tu invitación a la beta").font(.myaowCaptionMedium).foregroundStyle(MyaowColor.textSecondary)
                    TextField("Código de invitación", text: $betaInvite)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.myaowBody).padding(14).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 14))
                    Text("Usa el código que recibiste con tu invitación.").font(.myaowCaption).foregroundStyle(MyaowColor.textTertiary)
                }.padding(.horizontal, 24).padding(.bottom, 16)
            }
            MyaowPillButton(isSubmitting ? "Creando tu identidad…" : "Empezar a chatear", icon: "arrow.right", style: .primary, isFullWidth: true) {
                submitRegistration()
            }
            .disabled(isSubmitting)
            .opacity(isSubmitting ? 0.6 : 1)
            .padding(.horizontal, 24)
            .padding(.bottom, 8)

            if !requiresBetaInvite {
            Button("Empezar sin conexión") {
                let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                IdentityManager.shared.isDirectoryRegistrationPending = true
                IdentityManager.shared.completeRegistration(
                    displayName: name.isEmpty ? "Usuario Myaow" : name,
                    customUsername: nil,
                    avatarStateName: selectedCatState.rawValue,
                    avatarImageData: usePhotoGallery ? selectedPhotoData : nil
                )
                OnlineMessagingService.shared.reconnect()
            }
            .disabled(isSubmitting)
            .font(.myaowCaptionMedium)
            .foregroundStyle(MyaowColor.textSecondary)
            Text("Usarás tu ID y el perfil se registrará cuando haya conexión. El nombre de usuario elegido no se guardará ni se reservará en este modo.")
                .font(.myaowCaption)
                .foregroundStyle(MyaowColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
            }
        }
        .padding(.top, 28)
        }
    }

    private var canContinue: Bool {
        let value = RegistrationInput.normalizedUsername(customUsername)
        return value.isEmpty || (RegistrationInput.isValidUsername(value) && !isCheckingUsername && isUsernameAvailable != false)
    }

    private var serverSettings: some View {
        DisclosureGroup("Conexión al servidor", isExpanded: $showsServerSettings) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Usa la dirección del servidor Myaow de tu red. La búsqueda de usuarios necesita conexión.")
                    .font(.myaowCaption)
                TextField("https://servidor", text: $relayAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .padding(12)
                    .background(MyaowColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Button("Guardar y comprobar") {
                    guard RelayEndpoint(relayAddress) != nil else {
                        registrationError = "Escribe una dirección de servidor válida."
                        return
                    }
                    OnlineMessagingService.shared.relayHost = relayAddress.trimmingCharacters(in: .whitespacesAndNewlines)
                    checkUsernameAvailability(customUsername)
                }
            }
            .padding(.top, 10)
        }
        .font(.myaowCaption)
        .foregroundStyle(MyaowColor.textSecondary)
        .tint(MyaowColor.orange)
    }

    private func submitRegistration() {
        guard !isSubmitting, canContinue else { return }
        isSubmitting = true
        Task { @MainActor in
            defer { isSubmitting = false }
            var draft = IdentityManager.shared.currentIdentity
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = RegistrationInput.normalizedUsername(customUsername)
            draft.displayName = name.isEmpty ? "Usuario Myaow" : name
            draft.customUsername = username.isEmpty ? nil : username
            draft.avatarStateName = selectedCatState.rawValue
            draft.avatarImageData = usePhotoGallery ? selectedPhotoData : nil
            guard await UserDirectoryService.shared.registerIdentityOnServer(identity: draft, betaInvite: betaInvite) else {
                registrationError = UserDirectoryService.shared.registrationError ?? "No pudimos completar el registro. Intenta de nuevo."
                return
            }
            IdentityManager.shared.isDirectoryRegistrationPending = false
            IdentityManager.shared.completeRegistration(
                displayName: draft.displayName,
                customUsername: draft.customUsername,
                avatarStateName: draft.avatarStateName,
                avatarImageData: draft.avatarImageData
            )
            OnlineMessagingService.shared.reconnect()
            APNsNotificationManager.shared.requestNotificationPermissions()
        }
    }

    // MARK: - Sanitizer Helper
    private func sanitizeHandle(_ text: String) -> String {
        RegistrationInput.suggestedUsername(text)
    }
    
    private func emotionCell(state: MyaowCatState) -> some View {
        let isSelected = selectedCatState == state
        return VStack(spacing: 8) {
            MyaowCatView(state: state, style: .darkOnOrange, size: 52, isInteractive: false)
                .scaleEffect(isSelected ? 1.05 : 1.0)
                .allowsHitTesting(false) // Don't let cat steal taps
            
            Text(state.displayName)
                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .default))
                .foregroundColor(isSelected ? MyaowColor.orange : MyaowColor.textSecondary)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(isSelected ? MyaowColor.surfaceElevated : MyaowColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? MyaowColor.orange : MyaowColor.borderSubtle, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? MyaowColor.orange.opacity(0.25) : Color.clear, radius: 8, x: 0, y: 4)
        .contentShape(Rectangle()) // Makes entire area tappable
        .onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            selectedCatState = state
        }
    }
    
    // MARK: - Username Validation
    private func checkUsernameAvailability(_ username: String) {
        usernameCheckTask?.cancel()
        isCheckingUsername = false
        isUsernameAvailable = nil
        usernameMessage = nil
        let cleanUsername = RegistrationInput.normalizedUsername(username)
        guard !cleanUsername.isEmpty else { return }
        guard RegistrationInput.isValidUsername(cleanUsername) else {
            isUsernameAvailable = false
            usernameMessage = "Usa de 3 a 30 letras, números o guion bajo."
            return
        }
        isCheckingUsername = true
        usernameCheckTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(400))
                let available = try await UserDirectoryService.shared.usernameAvailability(cleanUsername)
                try Task.checkCancellation()
                guard RegistrationInput.normalizedUsername(customUsername) == cleanUsername else { return }
                isUsernameAvailable = available
                usernameMessage = available ? "Disponible. Lo reservaremos al completar tu registro." : "Ese nombre ya está en uso. Prueba con otro."
                isCheckingUsername = false
            } catch {
                guard !Task.isCancelled, RegistrationInput.normalizedUsername(customUsername) == cleanUsername else { return }
                isCheckingUsername = false
                usernameMessage = "No pudimos comprobarlo. Lo verificaremos al registrar tu perfil."
            }
        }
    }

}

#Preview {
    OnboardingRegistrationView()
}
