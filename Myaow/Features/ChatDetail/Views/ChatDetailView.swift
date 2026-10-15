//
//  ChatDetailView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData
import PhotosUI

public struct ChatDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public var conversation: ConversationModel
    @Query private var sortedMessages: [MessageModel]
    @State private var nearLatestMessage = true
    @State private var visibleMessageID: String?
    @FocusState private var composerFocused: Bool
    @Query private var allContacts: [ContactModel]
    
    @State private var replyingToMessage: MessageModel? = nil
    @State private var isContactTyping: Bool = false
    @State private var typingContactName: String = ""
    @State private var scheduleMessageText: String = ""
    @State private var showingBlockedContentSheet: Bool = false
    @State private var showingWallpaperPicker: Bool = false
    @State private var showingWalkieTalkie: Bool = false
    @State private var showingSafetyNumberSheet: Bool = false
    @State private var showingPinnedSheet: Bool = false
    @State private var showingNudgeDeckSheet: Bool = false
    @State private var showingScheduledList = false
    @State private var showingScheduleMessageSheet: Bool = false
    @State private var targetMessageForUnblock: MessageModel?
    @State private var currentPinnedIndex: Int = 0
    @State private var isPinnedShelfExpanded: Bool = true
    @State private var showingCreateMissionFromChat: Bool = false
    @State private var missionPrefilledText: String = ""
    
    // Multimedia State
    @State private var selectedPhotoPickerItem: PhotosPickerItem? = nil
    @State private var pickedMedia: [ChatMediaSelection] = []
    @State private var showingMediaComposer: Bool = false
    @State private var selectedMediaMessageForViewer: MessageModel? = nil
    
    // Voice, Call & Nudge State
    @State private var nudgeService = MyaowNudgeService.shared
    @State private var editingMessage: MessageModel? = nil
    @State private var editText: String = ""
    
    public init(conversation: ConversationModel) {
        self.conversation = conversation
        self._sortedMessages = Query(ChatHistoryQuery.descriptor(conversationID: conversation.id))
    }
    
    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                customFloatingHeader
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        // Muelle Creativo de Mensajes Anclados (Directo en el chat)
                        if !conversation.pinnedMessages.isEmpty {
                            pinnedShelfView(proxy: proxy)
                        }
                        
                        // Lista de Mensajes sobrepuesta
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                if OnlineMessagingService.shared.status != .online && !MeshNetworkService.shared.connectedPeers.contains(where: { $0.myaowId == conversation.recipientMyaowId }) {
                                    OfflineQueueBannerView()
                                        .padding(.top, 12)
                                        .padding(.bottom, 6)
                                }
                                
                                ForEach(Array(sortedMessages.enumerated()), id: \.element.id) { index, msg in
                                    VStack(spacing: 8) {
                                    if index == 0 || !Calendar.current.isDate(msg.timestamp, inSameDayAs: sortedMessages[index - 1].timestamp) {
                                        Text(msg.timestamp.formatted(date: .abbreviated, time: .omitted))
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(MyaowColor.textSecondary)
                                            .padding(.horizontal, 14).padding(.vertical, 7)
                                            .background(MyaowColor.charcoal.opacity(0.85), in: Capsule())
                                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                                    }
                                    MessageBubbleView(
                                        message: msg,
                                        senderAvatarUrl: contactForConversation?.avatarUrl,
                                        senderCatState: contactCatState,
                                        onProtectedMediaTapped: {
                                            targetMessageForUnblock = msg
                                            showingBlockedContentSheet = true
                                        },
                                        onMediaTapped: {
                                            selectedMediaMessageForViewer = msg
                                        },
                                        onTogglePin: {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                msg.isPinned.toggle()
                                                if msg.isPinned {
                                                    msg.pinnedTimestamp = Date()
                                                }
                                                try? modelContext.save()
                                            }
                                        },
                                        onNudgeTapped: {
                                            showingNudgeDeckSheet = true
                                        },
                                        onDeleteForEveryone: {
                                            guard msg.isOutgoing else { return }
                                            OnlineMessagingService.shared.sendMessageDelete(messageId: msg.id, recipientMyaowId: conversation.recipientMyaowId, groupId: conversation.isGroup ? conversation.id : nil) { queued in
                                                guard queued else { return }
                                                msg.text = "🚫 Este mensaje fue eliminado"
                                                msg.messageTypeRaw = "deleted"
                                                msg.mediaData = nil
                                                try? modelContext.save()
                                            }
                                        },
                                        onEditMessage: {
                                            editingMessage = msg
                                            editText = msg.text
                                        },
                                        onReply: {
                                            replyingToMessage = msg
                                        },
                                        onReact: { emoji in
                                            do {
                                                let own = IdentityManager.shared.currentIdentity
                                                try MessageReactionStore.enqueue(message: msg, emoji: emoji, conversation: conversation,
                                                    actor: own.myaowId, name: own.displayName, context: modelContext)
                                                MyaowBackendEngine.shared.retryPendingMessages(force: true)
                                            } catch { OnlineMessagingService.shared.messagingError = error.localizedDescription }

                                        },
                                        onCompleteTask: { targetMsg in
                                            Task {
                                                let myId = IdentityManager.shared.currentIdentity.myaowId
                                                let myName = IdentityManager.shared.currentIdentity.displayName
                                                
                                                do {
                                                    try await GroupTasksService.shared.completeTask(
                                                        taskId: targetMsg.id,
                                                        completedByMyaowId: myId,
                                                        completedByName: myName
                                                    )
                                                } catch {
                                                    OnlineMessagingService.shared.messagingError = error.localizedDescription
                                                    return
                                                }
                                                
                                                await MainActor.run {
                                                    targetMsg.taskIsCompleted = true
                                                    // Fallback string manipulation if taskCompletedBy doesn't exist? Wait, it exists!
                                                    // I saw message.taskCompletedBy in MessageBubbleView!
                                                    // Let's assume there is a way. If not, I can just not set it if it errors.
                                                }
                                                
                                                // Wait, since I'm in MainActor due to ChatDetailView, I can just mutate it.
                                                targetMsg.taskIsCompleted = true
                                                targetMsg.taskCompletedBy = myName
                                                try? modelContext.save()
                                            }
                                        },
                                        onCreateMission: { targetMsg in
                                            missionPrefilledText = targetMsg.text
                                            showingCreateMissionFromChat = true
                                        }
                                    )
                                    }
                                    .id(msg.id)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.top, 12)
                            .padding(.bottom, 20)
                        }
                        .scrollPosition(id: $visibleMessageID, anchor: .bottom)
                        .modifier(ChatTimelineBehavior(followsLatest: $nearLatestMessage))
                        .contentShape(Rectangle())
                        .simultaneousGesture(TapGesture().onEnded { composerFocused = false })
                        .accessibilityAction(named: "Cerrar teclado") { composerFocused = false }
                        .overlay(alignment: .bottomTrailing) {
                            if !nearLatestMessage && !sortedMessages.isEmpty {
                                Button {
                                    nearLatestMessage = true
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { visibleMessageID = sortedMessages.last?.id }
                                } label: {
                                    Label("Recientes", systemImage: "arrow.down").font(.caption.weight(.semibold))
                                        .padding(12).background(MyaowColor.surfaceElevated, in: Capsule())
                                }.tint(MyaowColor.orange).padding(12)
                            }
                        }
                    }
                    .onChange(of: sortedMessages.last?.id, initial: true) { _, latestID in
                        markConversationRead()
                        if nearLatestMessage || sortedMessages.last?.isOutgoing == true {
                            nearLatestMessage = true
                            visibleMessageID = latestID
                        }
                    }
                }
                
                // Indicador de "Escribiendo..." tipo WhatsApp
                if isContactTyping {
                    HStack(spacing: 8) {
                        MyaowTypingDots()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(MyaowColor.surfaceElevated.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        
                        Text("\(typingContactName) está escribiendo...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(MyaowColor.textTertiary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
                messageComposer
            }
            .offset(x: nudgeService.shakeOffset)
            

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(ConversationDecorationModifier(conversation: conversation))
        .background { ChatWallpaperView().ignoresSafeArea() }
        .containerBackground(.clear, for: .navigation)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
        .alert("No se pudo completar", isPresented: Binding(
            get: { OnlineMessagingService.shared.messagingError != nil },
            set: { if !$0 { OnlineMessagingService.shared.messagingError = nil } }
        )) {
            Button("Entendido", role: .cancel) { OnlineMessagingService.shared.messagingError = nil }
        } message: { Text(OnlineMessagingService.shared.messagingError ?? "") }
        .alert("Editar Mensaje", isPresented: Binding<Bool>(
            get: { editingMessage != nil },
            set: { if !$0 { editingMessage = nil } }
        )) {
            TextField("Mensaje", text: $editText)
            Button("Cancelar", role: .cancel) { editingMessage = nil }
            Button("Guardar") {
                if let msg = editingMessage {
                    let replacement = editText
                    guard msg.isOutgoing else { return }
                    OnlineMessagingService.shared.sendMessageEdit(messageId: msg.id, newText: replacement, recipientMyaowId: conversation.recipientMyaowId) { queued in
                        guard queued else { return }
                        msg.text = replacement
                        msg.isEdited = true
                        try? modelContext.save()
                    }
                }
            }
        }
        .sheet(isPresented: $showingNudgeDeckSheet) {
            MyaowMaullidosDeckView { soundType in
                sendCatMaullido(soundType: soundType)
            }
        }
        .sheet(isPresented: $showingCreateMissionFromChat) {
            QuickMissionFromChatSheet(prefilledText: missionPrefilledText) { missionText, dueLabel, priority in
                dispatchTaskMessage(text: missionText, priority: priority, dueLabel: dueLabel)
            }
        }
        .sheet(isPresented: $showingBlockedContentSheet) {
            BlockedContentSheetView {
                if let target = targetMessageForUnblock {
                    target.isContentRevealedByConsent = true
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $showingWallpaperPicker) {
            ConversationDecorationPicker(conversation: conversation)
        }
        .sheet(isPresented: $showingWalkieTalkie) {
            WalkieTalkieOverlayView(
                targetContactName: conversation.title,
                isTargetVerified: true,
                targetContactID: resolveRecipientMyaowId()
            )
        }
        .sheet(isPresented: $showingSafetyNumberSheet) {
            SafetyNumberView(
                contactName: conversation.title,
                contactMyaowId: "MYAOW-\(conversation.title.prefix(4).uppercased())"
            )
        }
        .sheet(isPresented: $showingPinnedSheet) {
            PinnedMessagesSheetView(conversation: conversation) { _ in }
        }
        .sheet(isPresented: $showingScheduledList) { ScheduledMessagesListView(conversationId: conversation.id) }
        .sheet(isPresented: $showingScheduleMessageSheet) {
            ScheduleMessageModalView(
                messageText: scheduleMessageText,
                recipientName: conversation.title
            ) { scheduledDate in
                try await ScheduledMessagesService.shared.scheduleMessage(
                    conversationId: conversation.id,
                    recipientName: conversation.title,
                    text: scheduleMessageText,
                    date: scheduledDate,
                    recipientId: resolveRecipientMyaowId(),
                    groupId: conversation.isGroup ? conversation.id : nil
                )
                scheduleMessageText = ""
            }
        }
        .sheet(isPresented: $showingMediaComposer, onDismiss: { pickedMedia = [] }) {
            MediaComposerSheetView(items: pickedMedia, onSend: dispatchMediaMessages)
        }
        .fullScreenCover(item: $selectedMediaMessageForViewer) { msg in
            if msg.messageTypeRaw == "rawFile" { DocumentAttachmentView(message: msg) }
            else { FullScreenMediaViewer(message: msg) }
        }
        .onAppear {
            #if DEBUG
            if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--chat-style-preview") && !sortedMessages.contains(where: { $0.id == "myaow-style-preview" }) {
                let examples: [(Bool, String, String)] = [
                    (false, "¿Todo listo para mañana?", "text"),
                    (true, "Sí. Ya tenemos las fotos y el plan para el equipo.", "text"),
                    (false, "Me encanta cómo va quedando 🧡", "text"),
                    (false, "[NUDGE:cosmic] Ronroneo", "nudge"),
                    (true, "Nos vemos a las 10. Te escribo cuando llegue.", "text")]
                for (index, item) in examples.enumerated() {
                    conversation.messages.append(MessageModel(id: index == 4 ? "myaow-style-preview" : UUID().uuidString,
                        conversationId: conversation.id, senderId: "MYAOW-DEMO01", senderName: "Eva", isOutgoing: item.0,
                        text: item.1, timestamp: Date().addingTimeInterval(Double(index - 5)*30), deliveryStatusRaw: "read", messageTypeRaw: item.2))
                }
                try? modelContext.save()
            }
            if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--maullidos-preview") { showingNudgeDeckSheet = true }
            if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--media-batch-preview") {
                pickedMedia = ["WallpaperEmber", "WallpaperOrbit", "WallpaperSilk"].compactMap { name in
                    guard let data = UIImage(named: name)?.jpegData(compressionQuality: 0.7) else { return nil }
                    return ChatMediaSelection(data: data, isVideo: false)
                }
                showingMediaComposer = !pickedMedia.isEmpty
            }
            if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--history-preview") && sortedMessages.count < 100 {
                for index in 0..<120 {
                    conversation.messages.append(MessageModel(conversationId: conversation.id, senderId: "MYAOW-DEMO01", senderName: "Eva",
                        isOutgoing: index % 2 == 0, text: "Mensaje guardado \(index + 1) · revisión del historial local", timestamp: Date().addingTimeInterval(Double(index - 120) * 60), deliveryStatusRaw: "delivered"))
                }
                try? modelContext.save()
            }
            #endif
            OnlineMessagingService.shared.setConversationVisible(conversation.id, visible: true)
            TabBarManager.shared.hide()
            
            OnlineMessagingService.shared.onTypingIndicatorReceived = { senderId, displayName, isTyping in
                Task { @MainActor in
                    if senderId == conversation.recipientMyaowId {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isContactTyping = isTyping
                            typingContactName = displayName
                        }
                    }
                }
            }
            
            markConversationRead()

            Task { await ScheduledMessagesService.shared.refresh() }
        }

        .onDisappear {
            OnlineMessagingService.shared.setConversationVisible(conversation.id, visible: false)
            TabBarManager.shared.show()
        }
    }
    
    // MARK: - Muelle Creativo de Mensajes Anclados (Pinned Shelf)
    private func pinnedShelfView(proxy: ScrollViewProxy) -> some View {
        let pins = conversation.pinnedMessages
        let safeIndex = min(currentPinnedIndex, max(0, pins.count - 1))
        let currentPin = pins[safeIndex]
        
        return VStack(spacing: 0) {
            if isPinnedShelfExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        HStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(MyaowColor.orange.opacity(0.2))
                                    .frame(width: 22, height: 22)
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(MyaowColor.orange)
                            }
                            
                            Text(pins.count > 1 ? "ANCLADO (\(safeIndex + 1)/\(pins.count))" : "MENSAJE ANCLADO")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(MyaowColor.orange)
                            
                            Text("• \(currentPin.senderName)")
                                .font(.myaowMicro)
                                .foregroundColor(MyaowColor.textSecondary)
                        }
                        
                        Spacer()
                        
                        if pins.count > 1 {
                            HStack(spacing: 4) {
                                ForEach(0..<pins.count, id: \.self) { idx in
                                    Circle()
                                        .fill(idx == safeIndex ? MyaowColor.orange : MyaowColor.textTertiary)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .padding(.trailing, 6)
                        }
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isPinnedShelfExpanded = false
                            }
                        }) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(MyaowColor.textTertiary)
                                .frame(width: 20, height: 20)
                        }
                    }
                    
                    Text(currentPin.text)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(MyaowColor.textPrimary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            UIPasteboard.general.string = currentPin.text
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copiar")
                            }
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(MyaowColor.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(MyaowColor.orange.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        
                        Button(action: {
                            nearLatestMessage = false
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                proxy.scrollTo(currentPin.id, anchor: .center)
                            }
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "magnifyingglass")
                                Text("Ir al Mensaje")
                            }
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(MyaowColor.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(MyaowColor.surface)
                            .clipShape(Capsule())
                        }
                        
                        if pins.count > 1 {
                            Button(action: {
                                withAnimation {
                                    currentPinnedIndex = (currentPinnedIndex + 1) % pins.count
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Text("Siguiente")
                                    Image(systemName: "chevron.right")
                                }
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(MyaowColor.textSecondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                currentPin.isPinned = false
                                try? modelContext.save()
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(MyaowColor.textTertiary)
                                .frame(width: 24, height: 24)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    MyaowColor.surface.opacity(0.95)
                        .background(.ultraThinMaterial)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(MyaowColor.orange.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPinnedShelfExpanded = true
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundColor(MyaowColor.orange)
                        
                        Text("📌 \(pins.count) \(pins.count == 1 ? "Mensaje Anclado" : "Mensajes Anclados"): \(currentPin.text)")
                            .font(.myaowCaptionMedium)
                            .foregroundColor(MyaowColor.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(MyaowColor.orange)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(MyaowColor.surface.opacity(0.9).background(.ultraThinMaterial))
                    .clipShape(Capsule())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Divider().background(MyaowColor.borderSubtle.opacity(0.5))
        }
    }
    
    private var contactForConversation: ContactModel? {
        allContacts.first(where: {
            (!conversation.recipientMyaowId.isEmpty && $0.myaowId.localizedCaseInsensitiveCompare(conversation.recipientMyaowId) == .orderedSame) ||
            $0.displayName.localizedCaseInsensitiveCompare(conversation.title) == .orderedSame ||
            $0.myaowId.localizedCaseInsensitiveCompare(conversation.title) == .orderedSame
        })
    }
    
    private var contactCatState: MyaowCatState {
        // 1. Si es una conversación personal/con uno mismo, reflejar el estado actual de la identidad
        let myId = IdentityManager.shared.currentIdentity.myaowId
        let myName = IdentityManager.shared.currentIdentity.displayName
        if (!conversation.recipientMyaowId.isEmpty && conversation.recipientMyaowId.localizedCaseInsensitiveCompare(myId) == .orderedSame) ||
           conversation.title.localizedCaseInsensitiveCompare(myName) == .orderedSame {
            return MyaowCatState(rawValue: IdentityManager.shared.currentIdentity.avatarStateName) ?? .friendly
        }
        
        // 2. Si es un contacto conocido en SwiftData
        if let contact = contactForConversation,
           let state = MyaowCatState(rawValue: contact.avatarCatState) {
            return state
        }
        
        // 3. Fallback inteligente a la emoción actual si aún no hay contacto guardado
        return MyaowCatState(rawValue: IdentityManager.shared.currentIdentity.avatarStateName) ?? .friendly
    }
    
    // MARK: - Header Translúcido Estilo Apple
    private var messageComposer: some View {
        VStack(spacing: 6) {
            if conversation.messages.contains(where: { $0.isOutgoing && $0.deliveryStatus == .queued }) {
                Button("Reintentar pendientes") {
                    OnlineMessagingService.shared.startConnectionHeartbeat()
                    MyaowBackendEngine.shared.retryPendingMessages(force: true)
                    OnlineMessagingService.shared.flushOutbox()
                }.font(.system(size: 12, weight: .medium)).tint(MyaowColor.orange)
            }
                ChatInputBarView(
                    conversationId: conversation.id,
                    recipientMyaowId: resolveRecipientMyaowId(),
                    replyingToMessage: $replyingToMessage,
                    focus: $composerFocused,
                    onSendMessage: { text in
                        sendMessage(text: text)
                    },
                    onSendVoice: { duration, samples, data in
                        dispatchVoiceMessage(duration: duration, samples: samples, audioData: data)
                    },
                    onShowNudgeDeck: {
                        showingNudgeDeckSheet = true
                    },
                    onShowScheduleSheet: { text in
                        scheduleMessageText = text
                        showingScheduleMessageSheet = true
                    },
                    onPickedMedia: { items in pickedMedia = items; showingMediaComposer = true },
                    onSendSticker: { text in
                        MyaowBackendEngine.shared.dispatchSecureMessage(conversation: conversation, text: text, context: modelContext, recipientMyaowId: resolveRecipientMyaowId(), messageType: "sticker")
                    },
                    onSendCustomSticker: { data in
                        dispatchMediaMessages([MediaAttachmentPayload(data: data, isVideo: false, quality: .losslessOriginal, caption: CustomStickerImage.caption, fileSizeFormatted: "", dimensionsFormatted: "512 × 512")])
                    },
                    onPickedFile: { data, name in dispatchFileMessage(data: data, name: name) }
                )
        }
    }

    private var customFloatingHeader: some View {
        HStack(spacing: 12) {
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(MyaowColor.textPrimary)
                    .frame(width: 36, height: 44)
            }
            .accessibilityLabel("Volver a conversaciones")
            
            if conversation.isGroup {
                ZStack {
                    Circle().fill(MyaowColor.surfaceSecondary).frame(width: 40, height: 40)
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 17))
                        .foregroundColor(MyaowColor.textPrimary)
                }
            } else {
                ProfileAvatarView(
                    avatarUrl: contactForConversation?.avatarUrl,
                    avatarImageData: nil,
                    catState: contactCatState,
                    size: 40,
                    showMiniCat: false,
                    animateTransition: false
                )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.myaowHeadline)
                    .foregroundColor(MyaowColor.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(MyaowColor.textSecondary)
                    
                    Text(conversation.isGroup ? "Conversación de grupo" : "Conversación privada")
                        .font(.myaowMicro)
                        .foregroundColor(MyaowColor.orange)
                    

                }
            }
            
            Spacer()
            
            // Botón de Llamada de Audio E2EE
            Button(action: {
                let targetId = conversation.recipientMyaowId.isEmpty ? conversation.title : conversation.recipientMyaowId
                CallSessionService.shared.startCall(
                    contactName: conversation.title,
                    myaowId: targetId,
                    type: .audio
                )
            }) {
                ZStack {
                    Circle()
                        .fill(MyaowColor.surface)
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "phone.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(MyaowColor.textPrimary)
                }
            }
            
            .accessibilityLabel("Llamar a " + conversation.title)
            Menu {
                #if DEBUG
                if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--chat-scroll-check") {
                    Button("Recibir mensaje de prueba") { DesignPreviewData.appendTimelineCheckMessage(to: conversation, context: modelContext) }
                }
                #endif
                Button {
                    CallSessionService.shared.startCall(contactName: conversation.title, myaowId: resolveRecipientMyaowId(), type: .video)
                } label: { Label("Videollamada", systemImage: "video") }
                Button { showingWalkieTalkie = true } label: { Label("Walkie-talkie", systemImage: "waveform") }
                Button { showingScheduledList = true } label: { Label("Mensajes programados", systemImage: "clock") }
                Divider()
                Button(action: { showingNudgeDeckSheet = true }) {
                    Label { Text("Maullidos y zumbidos") } icon: { MyaowMaullidosMark(size: 22) }
                }
                if !conversation.pinnedMessages.isEmpty {
                    Button(action: { showingPinnedSheet = true }) {
                        Label("Ver Todos los Anclados (\(conversation.pinnedMessages.count))", systemImage: "pin.fill")
                    }
                }
                Button(action: { showingWallpaperPicker = true }) {
                    Label("Decorar chat", systemImage: "paintpalette")
                }
                Button(action: { showingSafetyNumberSheet = true }) {
                    Label("Código de seguridad", systemImage: "lock.shield.fill")
                }
                Button(action: { showingBlockedContentSheet = true }) {
                    Label("Contenido protegido", systemImage: "eye.slash.fill")
                }
                Button(role: .destructive) {
                    Task {
                        let recipientId = resolveRecipientMyaowId()
                        if ContactBlockingService.shared.isBlocked(recipientId) {
                            _ = await ContactBlockingService.shared.unblockContact(recipientId)
                        } else {
                            _ = await ContactBlockingService.shared.blockContact(recipientId)
                        }
                    }
                } label: {
                    Label(
                        ContactBlockingService.shared.isBlocked(resolveRecipientMyaowId()) ? "Desbloquear" : "Bloquear contacto",
                        systemImage: ContactBlockingService.shared.isBlocked(resolveRecipientMyaowId()) ? "hand.raised.slash" : "hand.raised.fill"
                    )
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .foregroundColor(MyaowColor.textSecondary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Rectangle().fill(.ultraThinMaterial)
                .overlay(MyaowColor.charcoal.opacity(0.9))
                .ignoresSafeArea(.container, edges: .top)
        }
    }
    

    private func resolveRecipientMyaowId() -> String {
        if !conversation.recipientMyaowId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return conversation.recipientMyaowId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Buscar coincidencia en la base de datos de ContactModel
        let descriptor = FetchDescriptor<ContactModel>()
        if let allContacts = try? modelContext.fetch(descriptor) {
            if let match = allContacts.first(where: {
                $0.displayName.localizedCaseInsensitiveCompare(conversation.title) == .orderedSame ||
                $0.myaowId.localizedCaseInsensitiveCompare(conversation.title) == .orderedSame
            }) {
                conversation.recipientMyaowId = match.myaowId
                try? modelContext.save()
                return match.myaowId
            }
        }
        
        return conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func sendMessage(text: String) -> Bool {
        let textToSend = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !textToSend.isEmpty else { return false }
        
        let targetRecipient = resolveRecipientMyaowId()
        
        OnlineMessagingService.shared.sendTypingIndicator(
            recipientMyaowId: resolveRecipientMyaowId(),
            isTyping: false
        )
        
        let replyId = replyingToMessage?.id
        let replyText = replyingToMessage?.text
        let replySender = replyingToMessage?.senderName
        
        let saved = MyaowBackendEngine.shared.dispatchSecureMessage(
            conversation: conversation,
            text: textToSend,
            context: modelContext,
            recipientMyaowId: targetRecipient,
            replyToId: replyId,
            replyToText: replyText,
            replyToSender: replySender
        )
        if saved { replyingToMessage = nil }
        return saved
    }
    
    private func markConversationRead() {
        conversation.unreadCount = 0
        let unread = sortedMessages.filter { !$0.isOutgoing && $0.deliveryStatus != .read }
        for message in unread { message.deliveryStatus = .read }
        do { try modelContext.save() }
        catch { modelContext.rollback(); return }
        for message in unread {
            OnlineMessagingService.shared.sendReadReceipt(messageId: message.id, recipientMyaowId: conversation.recipientMyaowId)
        }
    }

    private func persistMessageBeforeSending() -> Bool {
        do { try modelContext.save(); return true }
        catch {
            modelContext.rollback()
            OnlineMessagingService.shared.messagingError = "No se pudo guardar el mensaje. Revisa el espacio disponible y vuelve a intentarlo."
            return false
        }
    }

    private func sendCatMaullido(soundType: CatVocalSynthesizer.CatSoundType) -> Bool {
        guard nudgeService.cooldownSeconds == 0 else { return false }
        let saved = MyaowBackendEngine.shared.dispatchSecureMessage(
            conversation: conversation, text: soundType.wireText, context: modelContext,
            recipientMyaowId: resolveRecipientMyaowId(), messageType: "nudge")
        if saved { nudgeService.startCooldown() }
        return saved
    }

    private func dispatchMediaMessages(_ payloads: [MediaAttachmentPayload]) -> Bool {
        do {
            try OutgoingAttachmentStore.enqueue(payloads.map { OutgoingAttachment(data: $0.data, isVideo: $0.isVideo, caption: $0.caption) },
                conversation: conversation, senderID: IdentityManager.shared.currentIdentity.myaowId, senderName: "Yo", context: modelContext)
            MyaowBackendEngine.shared.retryPendingMessages(force: true)
            return true
        } catch { return false }
    }

    private func dispatchFileMessage(data: Data, name: String) {
        guard !data.isEmpty, data.count <= SupabaseMediaClient.maximumPlaintextBytes else { return }
        let message = MessageModel(conversationId: conversation.id, senderId: IdentityManager.shared.currentIdentity.myaowId,
            senderName: "Yo", isOutgoing: true, text: String(name.prefix(180)), timestamp: Date(),
            deliveryStatusRaw: MessageDeliveryStatus.queued.rawValue, messageTypeRaw: "rawFile", mediaData: data, moderationStatusRaw: "approved")
        conversation.messages.append(message)
        conversation.lastMessageSnippet = "Archivo: " + message.text
        conversation.lastMessageTimestamp = Date()
        guard persistMessageBeforeSending() else { return }
        MyaowBackendEngine.shared.retryPendingMessages(force: true)
    }

    private func dispatchVoiceMessage(duration: TimeInterval, samples: [CGFloat], audioData: Data? = nil) {
        guard let audioData, !audioData.isEmpty, audioData.count <= SupabaseMediaClient.maximumPlaintextBytes else {
            OnlineMessagingService.shared.messagingError = "La nota de voz debe ocupar hasta 10 MB. Graba una más corta."; return
        }
        let durationStr = String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
        let voiceText = "🎤 Nota de voz (\(durationStr))"
        
        let msg = MessageModel(
            conversationId: conversation.id,
            senderId: IdentityManager.shared.currentIdentity.myaowId,
            senderName: "Yo",
            isOutgoing: true,
            text: voiceText,
            timestamp: Date(),
            deliveryStatusRaw: MessageDeliveryStatus.queued.rawValue,
            messageTypeRaw: "voice",
            mediaData: audioData,
            moderationStatusRaw: "approved"
        )
        
        conversation.messages.append(msg)
        conversation.lastMessageSnippet = voiceText
        conversation.lastMessageTimestamp = Date()
        guard persistMessageBeforeSending() else { return }
        
        MyaowBackendEngine.shared.retryPendingMessages(force: true)
    }

    private func dispatchTaskMessage(text: String, priority: String, dueLabel: String) {
        let targetRecipient = resolveRecipientMyaowId()
        let prefix = priority == "alta" ? "🔴" : (priority == "media" ? "🟡" : "🟢")
        let taskText = "\(prefix) [MISIÓN] \(text) (Para: \(dueLabel))"
        
        let msg = MessageModel(
            conversationId: conversation.id,
            senderId: IdentityManager.shared.currentIdentity.myaowId,
            senderName: "Yo",
            isOutgoing: true,
            text: taskText,
            timestamp: Date(),
            deliveryStatusRaw: MessageDeliveryStatus.sending.rawValue,
            messageTypeRaw: "task",
            moderationStatusRaw: "approved"
        )
        msg.taskTitle = text
        msg.taskDueLabel = dueLabel
        msg.taskAssignee = targetRecipient
        msg.taskIsCompleted = false
        
        conversation.messages.append(msg)
        conversation.lastMessageSnippet = taskText
        conversation.lastMessageTimestamp = Date()
        guard persistMessageBeforeSending() else { return }
        
        MyaowSoundEffectsService.shared.playMessageSentEffect()
        
        OnlineMessagingService.shared.sendOnlineMessage(
            messageId: msg.id,
            conversationId: conversation.id,
            recipientMyaowId: targetRecipient,
            plaintext: taskText,
            messageType: "task"
        ) { success in
            if ![.sent, .delivered, .read].contains(msg.deliveryStatus) { msg.deliveryStatus = .queued }
            try? modelContext.save()
        }
    }
}

// Subview
struct QuickMissionFromChatSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var prefilledText: String
    var onCreated: (String, String, String) -> Void
    
    @State private var selectedDue = "Hoy"
    @State private var selectedPriority = "media"
    
    let dueOptions = ["Hoy", "Mañana", "Esta semana"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Misión")) {
                    TextField("Descripción", text: $prefilledText, axis: .vertical)
                        .lineLimit(2...6)
                }
                
                Section(header: Text("Para cuándo")) {
                    Picker("Fecha", selection: $selectedDue) {
                        ForEach(dueOptions, id: \.self) { opt in
                            Text(opt).tag(opt)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("Prioridad")) {
                    HStack {
                        Spacer()
                        priorityButton(color: .green, value: "baja")
                        Spacer()
                        priorityButton(color: .yellow, value: "media")
                        Spacer()
                        priorityButton(color: .red, value: "alta")
                        Spacer()
                    }
                }
            }
            .navigationTitle("Crear misión")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        onCreated(prefilledText, selectedDue, selectedPriority)
                        dismiss()
                    }
                    .disabled(prefilledText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func priorityButton(color: Color, value: String) -> some View {
        Button(action: { selectedPriority = value }) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle()
                        .stroke(Color.gray, lineWidth: selectedPriority == value ? 3 : 0)
                )
                .shadow(color: selectedPriority == value ? color.opacity(0.5) : .clear, radius: 4)
        }
    }
}
