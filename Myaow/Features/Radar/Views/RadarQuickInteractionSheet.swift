//
//  RadarQuickInteractionSheet.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//  Rediseño Indie Studio v2
//

import SwiftUI
import SwiftData

// MARK: - Iconos Felinos Indie (Programáticos)
struct MyaowIndieIcon: View {
    let type: IndieIconType
    let size: CGFloat
    var color: Color = MyaowColor.orange
    
    enum IndieIconType {
        case zap         // Zarpazo eléctrico
        case purr        // Ronroneo
        case fish        // Pescadito
        case meow        // Miau fuerte
        case call        // Llamada
        case video       // Videollamada
        case chat        // Conversación
        case send        // Enviar
        case radio       // Walkie
        case fire        // Fuego
    }
    
    var body: some View {
        ZStack {
            // Base: silueta de orejas de gato sutil
            catEarsBase
                .opacity(0.15)
            
            // Icono principal
            iconOverlay
        }
        .frame(width: size, height: size)
    }
    
    private var catEarsBase: some View {
        Path { path in
            let w = size, h = size
            // Oreja izquierda
            path.move(to: CGPoint(x: w * 0.2, y: h * 0.55))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.15))
            path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.35))
            path.closeSubpath()
            // Oreja derecha
            path.move(to: CGPoint(x: w * 0.8, y: h * 0.55))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.15))
            path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.35))
            path.closeSubpath()
        }
        .fill(color)
    }
    
    @ViewBuilder
    private var iconOverlay: some View {
        switch type {
        case .zap:
            Image(systemName: "bolt.fill")
                .font(.system(size: size * 0.45, weight: .black))
                .foregroundColor(color)
        case .purr:
            // Ondas de ronroneo
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(color.opacity(0.3 + Double(i) * 0.2), lineWidth: 1.5)
                        .frame(width: size * (0.3 + CGFloat(i) * 0.15))
                }
                Image(systemName: "pawprint.fill")
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundColor(color)
            }
        case .fish:
            Image(systemName: "fish.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(color)
                .rotationEffect(.degrees(-15))
        case .meow:
            ZStack {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundColor(color)
            }
        case .call:
            Image(systemName: "phone.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(color)
        case .video:
            Image(systemName: "video.fill")
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(color)
        case .chat:
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: size * 0.32, weight: .bold))
                .foregroundColor(color)
        case .send:
            Image(systemName: "paperplane.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundColor(.white)
        case .radio:
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: size * 0.35, weight: .bold))
                .foregroundColor(color)
        case .fire:
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundColor(color)
        }
    }
}

// MARK: - Sheet Rediseñado
public struct RadarQuickInteractionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    public let node: UniverseContactNode
    public var onOpenChat: (ConversationModel) -> Void
    
    @State private var quickMessageText: String = ""
    @State private var interactionFeedbackMessage: String? = nil
    @State private var floatingEffectSymbol: String? = nil
    @State private var floatingEffectY: CGFloat = 0
    @State private var floatingEffectOpacity: Double = 0
    @State private var isSending: Bool = false
    @State private var selectedAction: Int? = nil
    
    public init(node: UniverseContactNode, onOpenChat: @escaping (ConversationModel) -> Void) {
        self.node = node
        self.onOpenChat = onOpenChat
    }
    
    private func getOrCreateConversation() -> ConversationModel {
        let descriptor = FetchDescriptor<ConversationModel>()
        let conversations = (try? modelContext.fetch(descriptor)) ?? []
        
        if let existing = conversations.first(where: {
            (!node.myaowId.isEmpty && $0.recipientMyaowId.localizedCaseInsensitiveCompare(node.myaowId) == .orderedSame) ||
            $0.title.localizedCaseInsensitiveCompare(node.displayName) == .orderedSame
        }) {
            return existing
        }
        
        let newConv = ConversationModel(
            title: node.displayName,
            recipientMyaowId: node.myaowId,
            isGroup: false,
            isMeshConnected: node.connectionType == .localMeshOffline
        )
        modelContext.insert(newConv)
        try? modelContext.save()
        return newConv
    }
    
    public var body: some View {
        ZStack {
            // Fondo con gradiente sutil
            LinearGradient(
                colors: [Color(hex: "#0D0D0F"), Color(hex: "#141416"), Color(hex: "#0D0D0F")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Drag handle
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                
                // MARK: - Header Card
                headerCard
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                
                // Banner de confirmación
                if let feedback = interactionFeedbackMessage {
                    feedbackBanner(feedback)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                
                // MARK: - Acciones Rápidas Grid
                quickActionsGrid
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                
                // MARK: - Mensaje Rápido
                quickMessageBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                
                // MARK: - Abrir Chat
                openChatButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
            }
            
            // Animación flotante
            if let symbol = floatingEffectSymbol {
                Text(symbol)
                    .font(.system(size: 52))
                    .offset(y: floatingEffectY)
                    .opacity(floatingEffectOpacity)
            }
        }
        .presentationDetents([.fraction(0.78)])
    }
    
    // MARK: - Header Card
    private var headerCard: some View {
        HStack(spacing: 14) {
            // Avatar con ring de estado
            ZStack {
                // Glow ring
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [node.connectionType.badgeColor.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 28,
                            endRadius: 48
                        )
                    )
                    .frame(width: 76, height: 76)
                
                MyaowCatView(
                    state: node.avatarState,
                    style: .darkOnOrange,
                    size: 56,
                    isInteractive: true
                )
                
                // Status dot
                Circle()
                    .fill(node.connectionType.badgeColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color(hex: "#0D0D0F"), lineWidth: 2.5))
                    .offset(x: 22, y: 22)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(node.displayName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(node.connectionType.badgeColor)
                        .frame(width: 6, height: 6)
                    
                    Text(node.moodDescription)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(MyaowColor.orange)
                    
                    Text("•")
                        .foregroundColor(Color.white.opacity(0.2))
                        .font(.system(size: 8))
                    
                    Text(node.connectionType.rawValue)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.4))
                }
                
                Text(node.myaowId)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.2))
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Acciones Rápidas (Grid 2x3)
    private var quickActionsGrid: some View {
        VStack(spacing: 8) {
            // Fila 1: Acciones principales
            HStack(spacing: 8) {
                actionCard(
                    icon: .call,
                    title: "Llamar",
                    subtitle: "Audio HD",
                    gradient: [Color(hex: "#1A2A1A"), Color(hex: "#0D150D")],
                    accentColor: Color(hex: "#4CAF50")
                ) {
                    CallSessionService.shared.startCall(contactName: node.displayName, myaowId: node.myaowId, type: .audio)
                    dismiss()
                }
                
                actionCard(
                    icon: .video,
                    title: "Video",
                    subtitle: "Face HD",
                    gradient: [Color(hex: "#1A1A2A"), Color(hex: "#0D0D15")],
                    accentColor: Color(hex: "#5C6BC0")
                ) {
                    CallSessionService.shared.startCall(contactName: node.displayName, myaowId: node.myaowId, type: .video)
                    dismiss()
                }
                
                actionCard(
                    icon: .radio,
                    title: "Radio",
                    subtitle: "Walkie",
                    gradient: [Color(hex: "#2A1A1A"), Color(hex: "#150D0D")],
                    accentColor: MyaowColor.orange
                ) {
                    // Open walkie talkie
                    triggerFeedback("🎙️ Radio activado")
                }
            }
            
            // Fila 2: Toques felinos
            HStack(spacing: 8) {
                nudgeCard(
                    icon: .zap,
                    title: "Zarpazo",
                    theme: "electric",
                    label: "¡⚡️ Zarpazo Eléctrico! ⚡️"
                )
                
                nudgeCard(
                    icon: .purr,
                    title: "Ronroneo",
                    theme: "cosmic",
                    label: "¡🐾 Ronroneo Cálido! 💖"
                )
                
                nudgeCard(
                    icon: .fish,
                    title: "Pescadito",
                    theme: "liquid",
                    label: "¡🐟 Pescadito! 🐟"
                )
                
                nudgeCard(
                    icon: .meow,
                    title: "¡Miau!",
                    theme: "classic",
                    label: "¡📢 MIAOW! 🐱"
                )
            }
        }
    }
    
    // MARK: - Action Card
    private func actionCard(
        icon: MyaowIndieIcon.IndieIconType,
        title: String,
        subtitle: String,
        gradient: [Color],
        accentColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            action()
        }) {
            VStack(spacing: 8) {
                MyaowIndieIcon(type: icon, size: 36, color: accentColor)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(accentColor.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(accentColor.opacity(0.15), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Nudge Card (versión compacta)
    private func nudgeCard(
        icon: MyaowIndieIcon.IndieIconType,
        title: String,
        theme: String,
        label: String
    ) -> some View {
        Button(action: {
            sendNudge(theme: theme, label: label)
        }) {
            VStack(spacing: 6) {
                MyaowIndieIcon(type: icon, size: 28, color: MyaowColor.orange)
                
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(MyaowColor.orange.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Mensaje Rápido Bar
    private var quickMessageBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(MyaowColor.orange.opacity(0.5))
                
                TextField("Mensaje cifrado rápido...", text: $quickMessageText)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            
            Button(action: sendQuickMessage) {
                MyaowIndieIcon(type: .send, size: 20)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [MyaowColor.orange, MyaowColor.orange.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            }
        }
    }
    
    // MARK: - Open Chat Button
    private var openChatButton: some View {
        Button(action: {
            let conv = getOrCreateConversation()
            dismiss()
            onOpenChat(conv)
        }) {
            HStack(spacing: 10) {
                MyaowIndieIcon(type: .chat, size: 22, color: .white)
                
                Text("Abrir Chat")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.3))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
    
    // MARK: - Feedback Banner
    private func feedbackBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(MyaowColor.orange)
            Text(message)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(MyaowColor.orange.opacity(0.15))
                .overlay(Capsule().stroke(MyaowColor.orange.opacity(0.3), lineWidth: 1))
        )
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Actions
    private func sendQuickMessage() {
        guard !quickMessageText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let textToSend = quickMessageText
        quickMessageText = ""
        
        let conv = getOrCreateConversation()
        let msg = MessageModel(
            conversationId: conv.id,
            senderId: IdentityManager.shared.currentIdentity.myaowId,
            senderName: IdentityManager.shared.currentIdentity.displayName,
            isOutgoing: true,
            text: textToSend,
            timestamp: Date(),
            deliveryStatusRaw: "sent",
            messageTypeRaw: "text"
        )
        modelContext.insert(msg)
        try? modelContext.save()
        
        OnlineMessagingService.shared.sendOnlineMessage(
            conversationId: conv.id,
            recipientMyaowId: node.myaowId,
            plaintext: textToSend
        ) { _ in }
        
        MyaowSoundEffectsService.shared.playMessageSentEffect()
        triggerFeedback("Mensaje enviado a \(node.displayName)")
    }
    
    private func sendNudge(theme: String, label: String) {
        let conv = getOrCreateConversation()
        let nudgePayload = "[NUDGE:\(theme)] \(label)"
        
        let msg = MessageModel(
            conversationId: conv.id,
            senderId: IdentityManager.shared.currentIdentity.myaowId,
            senderName: IdentityManager.shared.currentIdentity.displayName,
            isOutgoing: true,
            text: nudgePayload,
            timestamp: Date(),
            deliveryStatusRaw: "sent",
            messageTypeRaw: "nudge"
        )
        modelContext.insert(msg)
        try? modelContext.save()
        
        OnlineMessagingService.shared.sendOnlineMessage(
            conversationId: conv.id,
            recipientMyaowId: node.myaowId,
            plaintext: nudgePayload
        ) { _ in }
        
        // Sci-Fi sound based on theme
        switch theme {
        case "electric": SciFiSoundEngine.shared.playSound(.laserBlast)
        case "cosmic": SciFiSoundEngine.shared.playSound(.alienPurr)
        case "liquid": SciFiSoundEngine.shared.playSound(.teleport)
        case "classic": SciFiSoundEngine.shared.playSound(.godzillaRoar)
        default: MyaowSoundEffectsService.shared.playElectricSparkEffect()
        }
        
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        
        showFloatingSymbol(label.prefix(2).description)
        triggerFeedback("¡\(label.components(separatedBy: " ").dropFirst().joined(separator: " "))!")
    }
    
    private func showFloatingSymbol(_ symbol: String) {
        floatingEffectSymbol = symbol
        floatingEffectY = 40
        floatingEffectOpacity = 1.0
        
        withAnimation(.easeOut(duration: 1.2)) {
            floatingEffectY = -160
            floatingEffectOpacity = 0.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            if self.floatingEffectSymbol == symbol {
                self.floatingEffectSymbol = nil
            }
        }
    }
    
    private func triggerFeedback(_ message: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            interactionFeedbackMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                if self.interactionFeedbackMessage == message {
                    self.interactionFeedbackMessage = nil
                }
            }
        }
    }
}

// MARK: - Scale Button Style (Indie Press Effect)
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
