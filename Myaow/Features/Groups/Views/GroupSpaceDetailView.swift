//
//  GroupSpaceDetailView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public enum SpaceTab: String, CaseIterable, Identifiable {
    case chat = "Chat"
    case missions = "Tareas"
    case resources = "Archivos"
    
    public var id: String { rawValue }
}

public struct GroupSpaceDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var groupMessages: [MessageModel]
    @State private var nearLatestMessage = true
    @State private var visibleMessageID: String?
    @FocusState private var composerFocused: Bool
    @Query private var conversations: [ConversationModel]
    @State private var sendError = ""
    @State private var errorTitle = "Mensaje sin enviar"
    @State private var groupRefreshFailed = false
    @Environment(\.dismiss) private var dismiss
    @State public var space: GroupSpaceModel
    
    @State private var selectedTab: SpaceTab = .chat
    @State private var inputText: String = ""
    @State private var pickedMedia: [ChatMediaSelection] = []
    @State private var showingMediaComposer = false
    @State private var showingMaullidos = false
    @State private var selectedMedia: MessageModel?
    @State private var showingInviteSheet: Bool = false
    @State private var showingSettings = false
    @State private var decorationTarget: ConversationModel?
    @State private var groupWasLeft = false
    @State private var showingCreateMissionSheet: Bool = false
    @State private var showingScheduledList = false
    @State private var showingScheduleSheet: Bool = false
    @State private var suggestedMissionPrompt: String? = nil
    @State private var sendUnavailable = false
    @State private var refreshingGroup = false
    
    public init(space: GroupSpaceModel) {
        self._space = State(initialValue: space)
        self._groupMessages = Query(ChatHistoryQuery.descriptor(conversationID: space.id.uuidString))
    }
    
    public var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // 1. Header del Espacio con Progreso Colectivo
                spaceHeaderView

                if groupRefreshFailed {
                    HStack {
                        Text("No pudimos actualizar el grupo. Tu historial sigue disponible.")
                        Spacer(minLength: 8)
                        Button("Reintentar") { Task { await refreshGroup() } }
                            .disabled(refreshingGroup)
                    }
                    .font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    .padding(12).background(MyaowColor.surface)
                }
                
                // 2. Selector de las 3 Capas: 💬 Conversación | 🎯 Misiones | 📦 Recursos
                tabSelectorBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                
                // 3. Contenido de la Pestaña Activa
                TabView(selection: $selectedTab) {
                    chatTabContent
                        .tag(SpaceTab.chat)
                    
                    GroupMissionsView(space: $space)
                        .tag(SpaceTab.missions)
                    
                    resourcesTabContent
                        .tag(SpaceTab.resources)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .modifier(ConversationDecorationModifier(conversation: conversations.first { $0.isGroup && $0.id.lowercased() == space.id.uuidString.lowercased() }))
        .sheet(item: $decorationTarget) { ConversationDecorationPicker(conversation: $0) }
        .containerBackground(.clear, for: .navigation)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert(errorTitle, isPresented: $sendUnavailable) {
            Button("Entendido", role: .cancel) {}
        } message: { Text(sendError) }
        .sheet(isPresented: $showingMaullidos) {
            MyaowMaullidosDeckView { sound in
                guard MyaowNudgeService.shared.cooldownSeconds == 0 else { return false }
                let saved = enqueue(text: sound.wireText, type: "nudge")
                if saved { MyaowNudgeService.shared.startCooldown() }
                return saved
            }
        }
        .sheet(isPresented: $showingMediaComposer, onDismiss: { pickedMedia = [] }) {
            MediaComposerSheetView(items: pickedMedia, onSend: sendMedia)
        }
        .fullScreenCover(item: $selectedMedia) { message in
            if message.messageTypeRaw == "rawFile" { DocumentAttachmentView(message: message) }
            else { FullScreenMediaViewer(message: message) }
        }
        .sheet(isPresented: $showingSettings, onDismiss: { if groupWasLeft { dismiss() } }) { GroupSettingsView(space: $space, onLeave: { groupWasLeft = true }) }
        .sheet(isPresented: $showingInviteSheet) {
            GroupInvitationSheet(groupId: space.id.uuidString, existingMemberIDs: Set(space.members.map(\.myaowId)))
        }
        .sheet(isPresented: $showingCreateMissionSheet) {
            CreateMissionSheetView(
                space: space,
                prefilledTitle: suggestedMissionPrompt ?? "",
                onMissionCreated: { newMission in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        space.missions.append(newMission)
                        suggestedMissionPrompt = nil
                    }
                }
            )
        }
        .sheet(isPresented: $showingScheduledList) { ScheduledMessagesListView(conversationId: space.id.uuidString) }
        .sheet(isPresented: $showingScheduleSheet) {
            ScheduleMessageModalView(
                messageText: inputText,
                recipientName: space.title
            ) { scheduledDate in
                try await ScheduledMessagesService.shared.scheduleMessage(
                    conversationId: space.id.uuidString,
                    recipientName: space.title,
                    text: inputText,
                    date: scheduledDate, groupId: space.id.uuidString
                )
                inputText = ""
            }
        }
        .task { await refreshGroup() }
        .onChange(of: OnlineMessagingService.shared.collaborationRevision) { _, _ in Task { await refreshGroup() } }
        .onAppear {
            MyaowBackendEngine.shared.retryPendingMessages(force: true)
            OnlineMessagingService.shared.setConversationVisible(space.id.uuidString, visible: true)
            TabBarManager.shared.hide()
            if DesignPreviewData.isEnabled {
                if DesignPreviewData.consumeLaunchRoute("--group-settings-preview") { showingSettings = true }
                if DesignPreviewData.consumeLaunchRoute("--group-tasks-preview") { selectedTab = .missions }
                if DesignPreviewData.consumeLaunchRoute("--group-new-task-preview") { showingCreateMissionSheet = true }
                if DesignPreviewData.consumeLaunchRoute("--group-invite-preview") { showingInviteSheet = true }
            }
        }
        .onDisappear {
            OnlineMessagingService.shared.setConversationVisible(space.id.uuidString, visible: false)
            TabBarManager.shared.show()
        }
    }

    private func refreshGroup() async {
        guard !DesignPreviewData.isEnabled, !refreshingGroup else { return }
        refreshingGroup = true
        defer { refreshingGroup = false }
        do {
            space.members = try await GroupDeliveryService.members(space.id.uuidString).map(\.model)
            space.memberCount = space.members.count
            space.missions = try await GroupTasksService.shared.fetchTasks(groupId: space.id.uuidString).compactMap(\.mission)
            if let policy = GroupTasksService.shared.policies[space.id.uuidString.lowercased()] { space.taskPolicy = policy }
            groupRefreshFailed = false
        } catch {
            if (error as? SupabaseHTTPError)?.status == 403 { dismiss() }
            else { groupRefreshFailed = true }
        }
        await ScheduledMessagesService.shared.refresh()
    }
    
    // MARK: - Header
    private var spaceHeaderView: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44).contentShape(Rectangle()) }.tint(MyaowColor.textPrimary).accessibilityLabel("Volver a grupos")
            Button { showingSettings = true } label: {
                HStack(spacing: 12) {
                    GroupMascotBadgeView(category: space.category, size: 46).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(space.title).font(.system(size: 18, weight: .semibold)).tracking(-0.3).lineLimit(1).foregroundStyle(MyaowColor.textPrimary)
                        Text("\(space.memberCount) integrantes · \(space.category.rawValue)").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    }
                }
            }.buttonStyle(.plain).accessibilityLabel("Información de \(space.title)")
            Spacer(minLength: 0)
            Menu {
                Button("Configuración", systemImage: "slider.horizontal.3") { showingSettings = true }
                Button("Decorar chat", systemImage: "paintpalette") { openDecoration() }
            } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44).background(MyaowColor.surface, in: Circle()) }.tint(MyaowColor.textPrimary).accessibilityLabel("Opciones del grupo")
        }.padding(.horizontal, 12).padding(.vertical, 12).background(MyaowColor.charcoal)
    }
    private func openDecoration() {
        let conversation = conversations.first { $0.isGroup && $0.id.lowercased() == space.id.uuidString.lowercased() }
            ?? ConversationModel(id: space.id.uuidString, title: space.title, isGroup: true)
        if conversation.modelContext == nil { modelContext.insert(conversation) }
        do { try modelContext.save(); decorationTarget = conversation }
        catch { modelContext.rollback(); errorTitle = "No pudimos abrir la decoración"; sendError = error.localizedDescription; sendUnavailable = true }
    }
    private var tabSelectorBar: some View {
        HStack(spacing: 6) {
            ForEach(SpaceTab.allCases) { tab in
                Button { selectedTab = tab } label: {
                    VStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Text(tab.rawValue).font(.subheadline.weight(selectedTab == tab ? .semibold : .medium))
                            if tab == .missions && space.pendingMissionsCount > 0 { Text("\(space.pendingMissionsCount)").font(.caption2.monospacedDigit()).padding(.horizontal, 6).padding(.vertical, 3).background(MyaowColor.orange.opacity(0.15), in: Capsule()) }
                        }.frame(minHeight: 24)
                        Capsule().fill(selectedTab == tab ? MyaowColor.orange : .clear).frame(height: 3)
                    }.frame(maxWidth: .infinity).padding(.top, 8).foregroundStyle(selectedTab == tab ? MyaowColor.textPrimary : MyaowColor.textSecondary).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
    }

    // MARK: - Tab 1: Chat (Conversación con Detección de Misiones)
    private var chatTabContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    // Banner de Celebración si se completó algo recientemente
                    if let lastCompleted = space.missions.first(where: { $0.isCompleted }) {
                        completedMissionBanner(mission: lastCompleted)
                            .padding(.horizontal, 16)
                    }
                    
                    // Mensajes del Espacio
                    if groupMessages.isEmpty { sampleSpaceMessages.padding(.horizontal, 16) }
                    ForEach(groupMessages) { message in
                        groupBubble(message)
                            .id(message.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.bottom, 16)
            }
            .scrollPosition(id: $visibleMessageID, anchor: .bottom)
            .modifier(ChatTimelineBehavior(followsLatest: $nearLatestMessage))
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
            .accessibilityAction(named: "Cerrar teclado") { composerFocused = false }
            .overlay(alignment: .bottomTrailing) {
                if !nearLatestMessage && !groupMessages.isEmpty {
                    Button { nearLatestMessage = true; visibleMessageID = groupMessages.last?.id } label: {
                        Label("Recientes", systemImage: "arrow.down").font(.caption.weight(.semibold))
                            .padding(12).background(MyaowColor.surfaceElevated, in: Capsule())
                    }.tint(MyaowColor.orange).padding(12)
                }
            }
            .onChange(of: groupMessages.last?.id, initial: true) { _, latestID in
                if nearLatestMessage || groupMessages.last?.isOutgoing == true {
                    nearLatestMessage = true
                    visibleMessageID = latestID
                }
            }
            
            // Detección Inteligente de Misión en Mensajes
            if let prompt = suggestedMissionPrompt {
                suggestedMissionBanner(title: prompt)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            
            // Input Bar del Espacio
            spaceInputBar
        }
    }
    
    private func completedMissionBanner(mission: GroupMissionModel) -> some View {
        HStack(spacing: 10) {
            MyaowCatView(state: .party, style: .darkOnOrange, size: 28, isInteractive: false)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("🎉 ¡Misión cumplida!")
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .foregroundColor(MyaowColor.orange)
                
                Text("\(mission.completedByDisplayName ?? "Alguien") completó “\(mission.title)”")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Text("🎉")
                .font(.system(size: 18))
        }
        .padding(10)
        .background(Color(hex: "#1F1A14"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyaowColor.orange.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func suggestedMissionBanner(title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundColor(MyaowColor.orange)
            
            VStack(alignment: .leading, spacing: 1) {
                Text("¿Crear misión?")
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .foregroundColor(MyaowColor.orange)
                
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .default))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                guard space.canCreateTask(IdentityManager.shared.currentIdentity.myaowId) else { return }
                showingCreateMissionSheet = true
            }) {
                Text("Crear")
                    .font(.system(size: 12, weight: .bold, design: .default))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(MyaowColor.orange)
                    .clipShape(Capsule())
            }
            
            Button(action: {
                withAnimation {
                    suggestedMissionPrompt = nil
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(MyaowColor.textTertiary)
                    .padding(4)
            }
        }
        .padding(10)
        .background(MyaowColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MyaowColor.orange.opacity(0.4), lineWidth: 1)
        )
    }
    
    // MARK: - Empty Chat State
    private var sampleSpaceMessages: some View {
        VStack(spacing: 16) {
            MyaowCatView(state: .curious, style: .darkOnOrange, size: 48, isInteractive: true)
            
            Text("Aún no hay mensajes")
                .font(.system(size: 15, weight: .semibold, design: .default))
                .foregroundColor(.white)
            
            Text("Empieza la conversación. Los mensajes se guardan para quienes estén desconectados.")
                .font(.system(size: 13, weight: .regular, design: .default))
                .foregroundColor(Color.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
        .padding(.horizontal, 20)
    }
    
    private func groupBubble(_ message: MessageModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !message.isOutgoing {
                Text(message.senderName).font(.caption.weight(.semibold)).foregroundStyle(MyaowColor.orange)
                    .padding(.leading, 54)
            }
            MessageBubbleView(message: message, onMediaTapped: { selectedMedia = message }, onNudgeTapped: { showingMaullidos = true }, onReact: { emoji in
                guard let conversation = conversations.first(where: { $0.id.lowercased() == space.id.uuidString.lowercased() && $0.isGroup }) else { return }
                do {
                    let own = IdentityManager.shared.currentIdentity
                    try MessageReactionStore.enqueue(message: message, emoji: emoji, conversation: conversation,
                        actor: own.myaowId, name: own.displayName, context: modelContext)
                    MyaowBackendEngine.shared.retryPendingMessages(force: true)
                } catch { errorTitle = "No se pudo reaccionar"; sendError = error.localizedDescription; sendUnavailable = true }
            })
        }
    }

    // MARK: - Input Bar
    private var spaceInputBar: some View {
        VStack(spacing: 6) {
            let scheduled = ScheduledMessagesService.shared.scheduledMessagesFor(conversationId: space.id.uuidString).filter { !$0.isSent }
            if let first = scheduled.first {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 11))
                        .foregroundColor(MyaowColor.orange)
                    
                    Text("\(scheduled.count) programado(s) · \(first.state == "delivered" ? "Entregado" : first.state == "queued" ? "En el servidor" : first.state == "attention" ? "Necesita revisión" : first.scheduledDate.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11, weight: .medium, design: .default))
                        .foregroundColor(Color(hex: "#C7C7CC"))
                    
                    Spacer()
                    
                    Button("Cancelar") {
                        Task {
                            do { try await ScheduledMessagesService.shared.cancelScheduledMessage(id: first.id) }
                            catch { errorTitle = "No se pudo cancelar"; sendError = error.localizedDescription; sendUnavailable = true }
                        }
                    }
                    .font(.system(size: 11, weight: .bold, design: .default))
                    .foregroundColor(MyaowColor.orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(Color(hex: "#221A14"))
                .clipShape(Capsule())
                .padding(.horizontal, 14)
            }
            
            HStack(spacing: 16) {
                Button { showingCreateMissionSheet = true } label: { Label("Nueva tarea", systemImage: "checkmark.circle") }.disabled(!space.canCreateTask(IdentityManager.shared.currentIdentity.myaowId))
                Button { showingScheduledList = true } label: { Label("Programados", systemImage: "clock") }
                Spacer(minLength: 0)
            }.font(.caption.weight(.medium)).foregroundStyle(MyaowColor.orange)
                .padding(.horizontal, 20).padding(.vertical, 8)
            if groupMessages.contains(where: { $0.isOutgoing && [.queued, .sending].contains($0.deliveryStatus) }) {
                HStack {
                    Label("Envío pendiente · reintento automático", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Button("Reintentar") { MyaowBackendEngine.shared.retryPendingMessages(force: true) }
                }.font(.caption).foregroundStyle(MyaowColor.textSecondary).padding(.horizontal, 20)
            }
            ChatInputBarView(conversationId: space.id.uuidString, recipientMyaowId: "", replyingToMessage: .constant(nil),
                focus: $composerFocused,
                onSendMessage: { enqueue(text: $0) },
                onSendVoice: { duration, _, data in
                    guard let data else { return }
                    let durationText = String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
                    _ = enqueue(text: "Nota de voz (\(durationText))", type: "voice", data: data)
                }, onShowNudgeDeck: { showingMaullidos = true },
                onShowScheduleSheet: { text in inputText = text; showingScheduleSheet = true },
                onPickedMedia: { items in pickedMedia = items; showingMediaComposer = true },
                onSendSticker: { enqueue(text: $0, type: "sticker") },
                onSendCustomSticker: { data in enqueue(text: CustomStickerImage.caption, type: "image", data: data) },
                onPickedFile: { data, name in _ = enqueue(text: String(name.prefix(180)), type: "rawFile", data: data) })
        }
    }

    @discardableResult private func enqueue(text: String, type: String = "text", data: Data? = nil) -> Bool {
        errorTitle = "Mensaje sin enviar"
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard text.utf8.count <= 64 * 1024, data.map({ !$0.isEmpty && $0.count <= SupabaseMediaClient.maximumPlaintextBytes }) ?? true else {
            sendError = "Elige un archivo de hasta 10 MB o un mensaje más corto."; sendUnavailable = true; return false
        }
        let own = IdentityManager.shared.currentIdentity
        let conversation = conversations.first { $0.id.lowercased() == space.id.uuidString.lowercased() && $0.isGroup }
            ?? ConversationModel(id: space.id.uuidString, title: space.title, isGroup: true)
        if conversation.modelContext == nil { modelContext.insert(conversation) }
        conversation.title = space.title
        let message = MessageModel(conversationId: conversation.id, senderId: own.myaowId, senderName: own.displayName,
            isOutgoing: true, text: text, deliveryStatusRaw: "queued", messageTypeRaw: type, mediaData: data, moderationStatusRaw: "approved")
        conversation.messages.append(message)
        conversation.lastMessageSnippet = text; conversation.lastMessageTimestamp = Date()
        do { try modelContext.save() }
        catch { modelContext.rollback(); sendError = "No pudimos guardar el mensaje. Inténtalo de nuevo."; sendUnavailable = true; return false }
        MyaowBackendEngine.shared.retryPendingMessages(force: true)
        return true
    }
    private func sendMedia(_ payloads: [MediaAttachmentPayload]) -> Bool {
        let own = IdentityManager.shared.currentIdentity
        let conversation = conversations.first { $0.id.lowercased() == space.id.uuidString.lowercased() && $0.isGroup }
            ?? ConversationModel(id: space.id.uuidString, title: space.title, isGroup: true)
        do {
            try OutgoingAttachmentStore.enqueue(payloads.map { OutgoingAttachment(data: $0.data, isVideo: $0.isVideo, caption: $0.caption) },
                conversation: conversation, senderID: own.myaowId, senderName: own.displayName, context: modelContext)
            MyaowBackendEngine.shared.retryPendingMessages(force: true)
            return true
        } catch { return false }
    }

    // MARK: - Tab 3: Recursos (Archivos + Personas)
    private var resourcesTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Archivos Compartidos
                VStack(alignment: .leading, spacing: 10) {
                    Text("ARCHIVOS Y DOCUMENTOS")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundColor(MyaowColor.orange)
                        .padding(.horizontal, 20)
                    
                    let attachments = groupMessages.filter { ["image", "video", "voice", "rawFile"].contains($0.messageTypeRaw) }
                    if attachments.isEmpty {
                        ContentUnavailableView("Todo lo compartido, aquí", systemImage: "folder",
                            description: Text("Las fotos, videos, notas de voz y documentos del chat aparecerán en este espacio."))
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(attachments.reversed()) { message in groupBubble(message) }
                        }
                    }
                }
                .padding(.top, 14)
                
                // 2. Miembros del Espacio
                VStack(alignment: .leading, spacing: 10) {
                    Text("MIEMBROS (\(space.members.count))")
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundColor(MyaowColor.orange)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 8) {
                        ForEach(space.members) { member in
                            HStack(spacing: 12) {
                                MyaowCatView(state: member.catState, style: .darkOnOrange, size: 36, isInteractive: false)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(member.displayName)
                                            .font(.system(size: 14, weight: .bold, design: .default))
                                            .foregroundColor(.white)
                                        
                                        if member.role == "Organizador" || member.role == "Creadora" {
                                            Text(member.role)
                                                .font(.system(size: 9, weight: .bold, design: .default))
                                                .foregroundColor(MyaowColor.orange)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(MyaowColor.orange.opacity(0.15))
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    Text(member.role)
                                        .font(.system(size: 11, weight: .medium, design: .default))
                                        .foregroundColor(MyaowColor.textSecondary)
                                }
                                
                                Spacer()
                                

                            }
                            .padding(12)
                            .background(MyaowColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 20)
                        }
                    }
                }
                
                // Botón Invitar
                Button(action: {
                    showingSettings = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Administrar el grupo")
                    }
                    .font(.system(size: 14, weight: .bold, design: .default))
                    .foregroundColor(MyaowColor.orange)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: "#1E1E22"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
    }
}
