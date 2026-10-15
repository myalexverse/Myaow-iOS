//
//  MessageBubbleView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct MessageBubbleView: View {
    @State private var showingReactions = false
    @State private var playbackError: String?
    public let message: MessageModel
    public var senderAvatarUrl: String?
    public var senderCatState: MyaowCatState
    public var onProtectedMediaTapped: (() -> Void)?
    public var onMediaTapped: (() -> Void)?
    public var onTogglePin: (() -> Void)?
    public var onNudgeTapped: (() -> Void)?
    public var onDeleteForEveryone: (() -> Void)?
    public var onEditMessage: (() -> Void)?
    public var onReply: (() -> Void)?
    public var onReact: ((String) -> Void)?
    public var onCompleteTask: ((MessageModel) -> Void)?
    public var onCreateMission: ((MessageModel) -> Void)?
    
    public init(
        message: MessageModel,
        senderAvatarUrl: String? = nil,
        senderCatState: MyaowCatState = .friendly,
        onProtectedMediaTapped: (() -> Void)? = nil,
        onMediaTapped: (() -> Void)? = nil,
        onTogglePin: (() -> Void)? = nil,
        onNudgeTapped: (() -> Void)? = nil,
        onDeleteForEveryone: (() -> Void)? = nil,
        onEditMessage: (() -> Void)? = nil,
        onReply: (() -> Void)? = nil,
        onReact: ((String) -> Void)? = nil,
        onCompleteTask: ((MessageModel) -> Void)? = nil,
        onCreateMission: ((MessageModel) -> Void)? = nil
    ) {
        self.message = message
        self.senderAvatarUrl = senderAvatarUrl
        self.senderCatState = senderCatState
        self.onProtectedMediaTapped = onProtectedMediaTapped
        self.onMediaTapped = onMediaTapped
        self.onTogglePin = onTogglePin
        self.onNudgeTapped = onNudgeTapped
        self.onDeleteForEveryone = onDeleteForEveryone
        self.onEditMessage = onEditMessage
        self.onReply = onReply
        self.onReact = onReact
        self.onCompleteTask = onCompleteTask
        self.onCreateMission = onCreateMission
    }
    
    private var isMediaMessage: Bool {
        message.messageTypeRaw == "image" || message.messageTypeRaw == "video"
    }
    
    private var decorationNotice: String {
        guard let event = ChatDecorationEvent.decode(message.decorationJSON) else { return message.text }
        return message.isOutgoing ? "Elegiste \(event.decoration.title) para este chat." : "\(message.senderName) eligió \(event.decoration.title)."
    }
    public var body: some View {
        VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 0) {
        HStack {
            if message.messageTypeRaw == "theme-v1" {
                Spacer(minLength: 16)
                VStack(spacing: 5) {
                    Label(decorationNotice, systemImage: "paintpalette")
                        .font(.caption).multilineTextAlignment(.center)
                    MyaowDeliveryStatusIndicator(status: message.deliveryStatus, isSender: message.isOutgoing)
                }.foregroundStyle(MyaowColor.textSecondary).padding(12).background(MyaowColor.charcoal.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
                Spacer(minLength: 16)
            } else if message.messageTypeRaw == "task" {
                Spacer()
                taskBubbleContent
                Spacer()
            } else if message.messageTypeRaw == "nudge" {
                if message.isOutgoing { Spacer(minLength: 38) }
                nudgeBubbleContent
                if !message.isOutgoing { Spacer(minLength: 38) }
            } else if message.messageTypeRaw == "image", message.text == CustomStickerImage.caption,
                      message.isOutgoing || message.moderationStatusRaw != "blurred" || message.isContentRevealedByConsent,
                      let data = message.mediaData {
                if message.isOutgoing { Spacer(minLength: 44) }
                VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 6) {
                    MyaowAsyncThumbnailView(data: data, maxDimension: 512, cornerRadius: 0, contentMode: .fit)
                        .frame(width: 190, height: 190)
                    HStack(spacing: 5) {
                        Text(timeString(message.timestamp)).font(.caption2).foregroundStyle(MyaowColor.textSecondary)
                        MyaowDeliveryStatusIndicator(status: message.deliveryStatus, isSender: message.isOutgoing)
                    }
                }
                if !message.isOutgoing { Spacer(minLength: 44) }
            } else if message.messageTypeRaw == "sticker", let sticker = MyaowSticker.match(message.text) {
                if message.isOutgoing { Spacer(minLength: 44) }
                VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 6) {
                    if !message.isOutgoing { Text(message.senderName).font(.caption).foregroundStyle(MyaowColor.textSecondary) }
                    MyaowStickerArtwork(sticker: sticker, size: 148)
                    HStack(spacing: 5) {
                        Text(timeString(message.timestamp)).font(.myaowMicro).foregroundStyle(MyaowColor.textSecondary)
                        MyaowDeliveryStatusIndicator(status: message.deliveryStatus, isSender: message.isOutgoing)
                    }

                }
                if !message.isOutgoing { Spacer(minLength: 44) }
            } else if message.isOutgoing {
                Spacer(minLength: 44)
                outgoingBubble
            } else {
                incomingBubble
                Spacer(minLength: 44)
            }
        }
        if message.messageTypeRaw != "deleted" { reactionsView.padding(.horizontal, message.isOutgoing ? 16 : 48) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .onTapGesture(count: 2) {
            if onReact != nil && message.messageTypeRaw != "deleted" { showingReactions = true }
        }
        .sheet(isPresented: $showingReactions) {
            MessageReactionPicker(message: message) { emoji in
                onReact?(emoji)
                UISelectionFeedbackGenerator().selectionChanged()
                showingReactions = false
            }
        }
        .alert("No se pudo reproducir", isPresented: Binding(get: { playbackError != nil }, set: { if !$0 { playbackError = nil } })) {
            Button("Entendido", role: .cancel) { playbackError = nil }
        } message: { Text(playbackError ?? "") }
        .contextMenu {
            if message.messageTypeRaw != "nudge" {
                if let onTogglePin {
                    Button(action: onTogglePin) { Label(message.isPinned ? "Desanclar mensaje" : "Anclar mensaje", systemImage: "pin") }
                }
                if let onReply { Button(action: onReply) { Label("Responder", systemImage: "arrowshape.turn.up.left") } }
                if onReact != nil && message.messageTypeRaw != "deleted" {
                    Button { showingReactions = true } label: { Label("Reaccionar", systemImage: "face.smiling") }
                }
                Button(action: {
                    UIPasteboard.general.string = message.text
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }) {
                    Label("Copiar Texto", systemImage: "doc.on.doc")
                }
                
                if message.isOutgoing && message.messageTypeRaw != "deleted", let onDeleteForEveryone {
                    Button(role: .destructive, action: {
                        onDeleteForEveryone()
                    }) {
                        Label("Eliminar para todos", systemImage: "trash.fill")
                    }
                    
                    if message.messageTypeRaw == "text", let onEditMessage {
                        Button(action: {
                            onEditMessage()
                        }) {
                            Label("Editar mensaje", systemImage: "pencil")
                        }
                    }
                }
                
                if message.messageTypeRaw == "text", let onCreateMission {
                    Button(action: {
                        onCreateMission(message)
                    }) {
                        Label("Crear misión", systemImage: "checkmark.circle")
                    }
                }
            }
        }
    }
    
    // MARK: - Outgoing (Apple Crystal Liquid Glass - Naranja Myaow)
    private var outgoingBubble: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if message.messageTypeRaw == "voice" {
                VoiceMessageBubbleView(message: message, isOutgoing: true)
            } else if message.messageTypeRaw == "rawFile", let data = message.mediaData {
                    documentBubble(bytes: data.count)
                } else if isMediaMessage && message.mediaData != nil {
                mediaBubbleContent(isOutgoing: true)
            } else {
                textBubbleContent(isOutgoing: true)
            }
            if ["voice", "rawFile"].contains(message.messageTypeRaw) {
                HStack(spacing: 5) {
                    Text(message.deliveryStatus.labelText)
                    Text(timeString(message.timestamp))
                    MyaowDeliveryStatusIndicator(status: message.deliveryStatus, isSender: true)
                }
                .font(.myaowMicro).foregroundStyle(MyaowColor.textSecondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(message.deliveryStatus.labelText + ", " + timeString(message.timestamp))
            }
        }
    }
    
    // MARK: - Incoming (Apple Crystal Liquid Glass - Obsidian)
    private var incomingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ProfileAvatarView(
                avatarUrl: senderAvatarUrl,
                avatarImageData: nil,
                catState: senderCatState,
                size: 28,
                showMiniCat: false,
                animateTransition: false
            )
            
            VStack(alignment: .leading, spacing: 4) {
                if message.moderationStatusRaw == "blurred" && !message.isContentRevealedByConsent {
                    ProtectedMediaBubbleView(message: message) {
                        onProtectedMediaTapped?()
                    }
                } else if message.messageTypeRaw == "voice" {
                    VoiceMessageBubbleView(message: message, isOutgoing: false)
                } else if message.messageTypeRaw == "rawFile", let data = message.mediaData {
                    documentBubble(bytes: data.count)
                } else if isMediaMessage && message.mediaData != nil {
                    mediaBubbleContent(isOutgoing: false)
                } else {
                    textBubbleContent(isOutgoing: false)
                }
            }
        }
    }
    
    private func documentBubble(bytes: Int) -> some View {
        Button { onMediaTapped?() } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.fill").font(.title2).foregroundStyle(MyaowColor.orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text(message.text).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)).font(.caption).foregroundStyle(MyaowColor.textSecondary)
                }
                Image(systemName: "arrow.up.right").font(.caption)
            }.padding(16).background(MyaowColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).accessibilityLabel("Abrir archivo: \(message.text)")
    }

    // Readable text, quiet metadata, and a consistent silhouette for both senders.
    private func textBubbleContent(isOutgoing: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if let replyText = message.replyToText {
                HStack(spacing: 9) {
                    Capsule().fill(MyaowColor.orange).frame(width: 3)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.replyToSender ?? "Respuesta").font(.caption.weight(.semibold)).foregroundStyle(MyaowColor.orange)
                        Text(replyText).font(.subheadline).foregroundStyle(MyaowColor.textSecondary).lineLimit(2)
                    }
                }.fixedSize(horizontal: false, vertical: true).padding(10)
                    .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            Text(message.text)
                .font(.system(size: 16)).lineSpacing(3)
                .foregroundStyle(message.messageTypeRaw == "deleted" ? MyaowColor.textSecondary : MyaowColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                if message.isEdited { Text("Editado") }
                if message.isPinned { Image(systemName: "pin.fill").foregroundStyle(MyaowColor.orange) }
                Text(timeString(message.timestamp)).monospacedDigit()
                if isOutgoing { MyaowDeliveryStatusIndicator(status: message.deliveryStatus, isSender: true) }
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(MyaowColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
        .background(crystalLiquidBackground(isOutgoing: isOutgoing))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: isOutgoing ? 20 : 6,
                                          bottomTrailingRadius: isOutgoing ? 6 : 20, topTrailingRadius: 20))
        .overlay(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: isOutgoing ? 20 : 6,
                                       bottomTrailingRadius: isOutgoing ? 6 : 20, topTrailingRadius: 20)
            .stroke(isOutgoing ? MyaowColor.orange.opacity(0.16) : Color.white.opacity(0.07), lineWidth: 0.75))
    }

    // MARK: - Media Bubble Content (Fotos & Videos HD)
    private func mediaBubbleContent(isOutgoing: Bool) -> some View {
        Button(action: {
            onMediaTapped?()
        }) {
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 6) {
                if let replyText = message.replyToText {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(message.replyToSender ?? "")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(MyaowColor.orange)
                        Text(replyText)
                            .font(.system(size: 11))
                            .foregroundColor(isOutgoing ? Color.white.opacity(0.7) : MyaowColor.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(isOutgoing ? Color.white.opacity(0.1) : MyaowColor.orange.opacity(0.1))
                    .cornerRadius(8)
                }
                
                ZStack(alignment: .bottomTrailing) {
                    if let data = message.mediaData {
                        MyaowAsyncThumbnailView(data: data, maxDimension: 480, cornerRadius: 14, isVideo: message.messageTypeRaw == "video")
                            .frame(width: 240, height: 180)
                            .clipped()
                    } else {
                        mediaFallbackPlaceholder
                    }
                    
                    if message.messageTypeRaw == "video" {
                        ZStack {
                            Circle().fill(Color.black.opacity(0.6)).frame(width: 44, height: 44)
                            Image(systemName: "play.fill").font(.system(size: 18)).foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    
                    // Badge HD
                    HStack(spacing: 3) {
                        Image(systemName: "sparkles").font(.system(size: 8))
                        Text("HD").font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(6)
                }
                
                if !message.text.isEmpty && message.text != "Archivo adjunto protegido" && message.text != "Fotografía HD" && message.text != "Video HD" {
                    Text(message.text)
                        .font(.myaowBody)
                        .foregroundColor(isOutgoing ? .white : MyaowColor.textPrimary)
                        .padding(.horizontal, 4)
                }
                
                HStack(spacing: 4) {
                    if message.isPinned {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundColor(isOutgoing ? .white.opacity(0.9) : MyaowColor.orange)
                    }
                    
                    Text(timeString(message.timestamp))
                        .font(.myaowMicro)
                        .foregroundColor(isOutgoing ? Color.white.opacity(0.8) : MyaowColor.textTertiary)
                    
                    if isOutgoing {
                        MyaowDeliveryStatusIndicator(status: message.deliveryStatus, isSender: true)
                    }
                }
                .padding(.horizontal, 4)
                
                }
            .padding(6)
            .background(crystalLiquidBackground(isOutgoing: isOutgoing))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isOutgoing ? Color.white.opacity(0.3) : Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var mediaFallbackPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(MyaowColor.surfaceSecondary)
                .frame(width: 220, height: 160)
            VStack(spacing: 6) {
                Image(systemName: message.messageTypeRaw == "video" ? "video.fill" : "photo.fill")
                    .font(.system(size: 32))
                    .foregroundColor(MyaowColor.orange)
                Text(message.messageTypeRaw == "video" ? "Video Protegido" : "Imagen HD")
                    .font(.myaowMicro)
                    .foregroundColor(MyaowColor.textSecondary)
            }
        }
    }
    
    private var detectedNudgeTheme: NudgeTheme {
        for theme in NudgeTheme.allCases {
            if message.text.contains(theme.rawValue) {
                return theme
            }
        }
        return .electric
    }
    
    // MARK: - Task Bubble
    private var taskBubbleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.taskIsCompleted {
                // Completed
                HStack {
                    Text("🎉 ¡Misión cumplida!")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(MyaowColor.orange)
                    Spacer()
                }
                Text(message.taskTitle ?? "Misión")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .strikethrough()
                    .foregroundColor(.white)
                Text("\(message.taskCompletedBy ?? "") lo hizo. ✨")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
            } else {
                // Not completed
                HStack {
                    Text("✓ MISIÓN")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(MyaowColor.orange)
                    Spacer()
                    Circle()
                        .fill(taskPriorityColor)
                        .frame(width: 8, height: 8)
                }
                Text(message.taskTitle ?? "Misión")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("👤 \(message.taskAssignee ?? "")  ·  📅 \(message.taskDueLabel ?? "")")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(Color.gray)
                
                Button(action: {
                    onCompleteTask?(message)
                }) {
                    Text("Completar")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(MyaowColor.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MyaowColor.orange, lineWidth: 1)
                        )
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(hex: "#18181A"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(message.taskIsCompleted ? Color.green.opacity(0.6) : MyaowColor.orange.opacity(0.6), lineWidth: 1.5)
        )
        .shadow(color: message.taskIsCompleted ? Color.green.opacity(0.2) : Color.clear, radius: 8, x: 0, y: 0)
        .frame(maxWidth: 280)
        .padding(.vertical, 6)
    }
    
    private var taskPriorityColor: Color {
        let text = message.text.lowercased()
        if text.contains("alta") || text.contains("urgente") {
            return .red
        } else if text.contains("media") {
            return .yellow
        } else {
            return .green
        }
    }
    
    // MARK: - Maullido sound sticker
    private var nudgeBubbleContent: some View {
        let sound = CatVocalSynthesizer.CatSoundType.from(message: message.text) ?? .classic
        return VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 6) {
            if !message.isOutgoing {
                Text(message.senderName).font(.caption.weight(.medium))
                    .foregroundStyle(MyaowColor.textSecondary).lineLimit(1)
            }
            MyaowMaullidoStickerView(sound: sound) { playbackError = $0 }
            HStack(spacing: 5) {
                Text(timeString(message.timestamp)).monospacedDigit()
                MyaowDeliveryStatusIndicator(status: message.deliveryStatus, isSender: message.isOutgoing)
            }.font(.system(size: 10)).foregroundStyle(MyaowColor.textSecondary)
            if !message.isOutgoing, let onNudgeTapped {
                Button(action: onNudgeTapped) {
                    Label("Responder", systemImage: "arrowshape.turn.up.left")
                        .font(.system(size: 11, weight: .medium)).frame(minHeight: 44)
                }.buttonStyle(.plain).foregroundStyle(MyaowColor.textSecondary)
                    .accessibilityLabel("Responder con un maullido")
            }
        }.frame(width: 216).padding(.vertical, 6)
    }

    // MARK: - Crystal Liquid Glass Shaders & Colors
    @ViewBuilder
    private func crystalLiquidBackground(isOutgoing: Bool) -> some View {
        (isOutgoing ? Color(hex: "34251C") : Color(hex: "1C1E22"))
    }
    
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    @ViewBuilder
    private var reactionsView: some View {
        if let reactions = message.parsedReactions, !reactions.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) { reactionBadges(reactions) }
                ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 5) { reactionBadges(reactions) } }
            }.padding(.top, 5)
        }
    }
    @ViewBuilder private func reactionBadges(_ reactions: [String: [String]]) -> some View {
        ForEach(reactions.keys.sorted(), id: \.self) { emoji in
            let mine = reactions[emoji]?.contains(IdentityManager.shared.currentIdentity.myaowId) == true
            Button { showingReactions = true } label: {
                HStack(spacing: 5) {
                    Text(emoji).font(.system(size: 17))
                    Text("\(reactions[emoji]?.count ?? 0)").font(.caption.weight(.semibold)).monospacedDigit()
                }.padding(.horizontal, 10).frame(minHeight: 36)
                    .foregroundStyle(mine ? MyaowColor.orange : MyaowColor.textSecondary)
                    .background(mine ? MyaowColor.orange.opacity(0.12) : MyaowColor.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(mine ? MyaowColor.orange.opacity(0.5) : MyaowColor.borderSubtle))
            }.buttonStyle(.plain).disabled(onReact == nil)
                .accessibilityLabel("\(emoji), \(reactions[emoji]?.count ?? 0) reacciones\(mine ? ", incluida la tuya" : "")")
        }
    }
}

private struct MessageReactionPicker: View {
    let message: MessageModel
    let select: (String) -> Void
    private let emojis = ["❤️", "😹", "🔥", "👍", "👏", "😮", "🥹", "😂", "😿", "😻", "✨", "✅", "🎉", "💯", "🤔", "👀", "🙌", "💪", "🤢", "🤮", "😒", "🙄", "😡", "💔", "😭", "🤯", "🫠", "🤤", "🫶", "👎"]
    private var ownReaction: String? {
        message.parsedReactions?.first { $0.value.contains(IdentityManager.shared.currentIdentity.myaowId) }?.key
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Dilo a tu manera.").font(.title2.weight(.semibold))
                        Text("Elige una reacción. Tócala otra vez para quitarla.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                    }
                    Spacer()
                    MyaowCatView(state: .playful, style: .darkOnOrange, size: 44, isInteractive: false)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button { select(emoji) } label: {
                            Text(emoji).font(.system(size: 28)).frame(maxWidth: .infinity).frame(height: 52)
                                .background(ownReaction == emoji ? MyaowColor.orange.opacity(0.18) : MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ownReaction == emoji ? MyaowColor.orange : .clear))
                        }.buttonStyle(.plain).accessibilityLabel(emoji).accessibilityAddTraits(ownReaction == emoji ? .isSelected : [])
                    }
                }
                if let ownReaction {
                    Button { select(ownReaction) } label: { Label("Quitar mi reacción \(ownReaction)", systemImage: "minus.circle").frame(minHeight: 44) }.tint(MyaowColor.orange)
                }
            }.padding(24)
        }.background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
    }
}
