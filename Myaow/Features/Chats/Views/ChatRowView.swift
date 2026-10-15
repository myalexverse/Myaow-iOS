//
//  ChatRowView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public struct ChatRowView: View {
    @Query private var allContacts: [ContactModel]
    public let conversation: ConversationModel
    
    private var contactForConversation: ContactModel? {
        allContacts.first(where: {
            (!conversation.recipientMyaowId.isEmpty && $0.myaowId.localizedCaseInsensitiveCompare(conversation.recipientMyaowId) == .orderedSame) ||
            $0.displayName.localizedCaseInsensitiveCompare(conversation.title) == .orderedSame ||
            $0.myaowId.localizedCaseInsensitiveCompare(conversation.title) == .orderedSame
        })
    }
    
    private var contactCatState: MyaowCatState {
        let myId = IdentityManager.shared.currentIdentity.myaowId
        let myName = IdentityManager.shared.currentIdentity.displayName
        if (!conversation.recipientMyaowId.isEmpty && conversation.recipientMyaowId.localizedCaseInsensitiveCompare(myId) == .orderedSame) ||
           conversation.title.localizedCaseInsensitiveCompare(myName) == .orderedSame {
            return MyaowCatState(rawValue: IdentityManager.shared.currentIdentity.avatarStateName) ?? .friendly
        }
        if let contact = contactForConversation, let state = MyaowCatState(rawValue: contact.avatarCatState) {
            return state
        }
        return .friendly
    }
    
    public var body: some View {
        HStack(spacing: 14) {
            // 1. Sistema Visual de Avatares Myaow
            avatarForChat
            
            // 2. Jerarquía de Textos: Nombre -> Mensaje -> Hora
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.title)
                        .font(.system(size: 17, weight: conversation.unreadCount > 0 ? .bold : .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text(formattedTimestamp(conversation.lastMessageTimestamp))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(hex: "#8E8E93"))
                }
                
                HStack(alignment: .center) {
                    messageSnippetView
                    
                    Spacer()
                    
                    if conversation.unreadCount > 0 {
                        Text(conversation.unreadCount > 99 ? "99+" : "\(conversation.unreadCount)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(minWidth: 22, minHeight: 22)
                            .background(MyaowColor.orange)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .padding(.vertical, 17)
        .contentShape(Rectangle())
    }
    
    // MARK: - Snippet Inteligente con Iconos
    @ViewBuilder
    private var messageSnippetView: some View {
        let snippet = conversation.lastMessageSnippet.isEmpty ? "Sin mensajes aún" : conversation.lastMessageSnippet
        
        if conversation.messages.max(by: { $0.timestamp < $1.timestamp })?.messageTypeRaw == "image" {
            HStack(spacing: 5) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 11))
                    .foregroundColor(MyaowColor.orange)
                Text("Imagen")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(hex: "#9E9E9E"))
            }
        } else if snippet.contains("cifrado") || snippet.contains("🔑") {
            HStack(spacing: 4) {
                Text(snippet.replacingOccurrences(of: "🔑", with: "").trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(hex: "#9E9E9E"))
                    .lineLimit(1)
                
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#7A7A7A"))
            }
        } else {
            Text(snippet)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color(hex: "#9E9E9E"))
                .lineLimit(1)
        }
    }
    
    // MARK: - Sistema Visual de Avatares Myaow
    @ViewBuilder
    private var avatarForChat: some View {
        ZStack(alignment: .bottomTrailing) {
            ProfileAvatarView(
                avatarUrl: contactForConversation?.avatarUrl,
                avatarImageData: nil,
                catState: contactCatState,
                size: 54,
                showMiniCat: false,
                animateTransition: false
            )
            if MeshNetworkService.shared.connectedPeers.contains(where: { $0.myaowId == conversation.recipientMyaowId }) {
                Circle()
                    .fill(MyaowColor.statusGreen)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(MyaowColor.charcoal, lineWidth: 2))
                    .offset(x: -1, y: -1)
            }
        }
    }
    
    private func formattedTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if Calendar.current.isDateInYesterday(date) {
            return "Ayer"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM"
            return formatter.string(from: date)
        }
    }
}
