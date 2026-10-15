//
//  NewChatModalView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public struct NewChatModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var contacts: [ContactModel]
    
    @State private var searchQuery: String = ""
    @State private var newContactMyaowId: String = ""
    @State private var newContactName: String = ""
    @State private var showingQRScanner = false
    @State private var directoryService = UserDirectoryService.shared
    @State private var isPerformingLookup = false
    
    public var onSelectConversation: ((ConversationModel) -> Void)?
    
    private var canCreateManualChat: Bool {
        !newContactName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        newContactMyaowId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .range(of: "^MYAOW-[A-Z0-9]{4,32}$", options: .regularExpression) != nil
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                MyaowColor.charcoal.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 18) {
                        // Barra de Búsqueda en el Directorio Público
                        MyaowSearchBar(
                            text: $searchQuery,
                            placeholder: "@usuario exacto o ID de Myaow"
                        )
                        .onChange(of: searchQuery) { _, newValue in
                            Task {
                                await directoryService.searchUsers(query: newValue)
                            }
                        }
                        
                        // Resultados de Búsqueda en Vivo del Directorio
                        if !directoryService.searchResults.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("USUARIOS ENCONTRADOS EN EL RELAY")
                                    .font(.myaowMicro)
                                    .foregroundColor(MyaowColor.orange)
                                    .padding(.horizontal, 4)
                                
                                ForEach(directoryService.searchResults) { user in
                                    Button(action: {
                                        openChatFromDirectoryUser(user)
                                    }) {
                                        HStack(spacing: 12) {
                                            MyaowAvatarView(
                                                source: .cat(state: .friendly, style: .darkOnOrange),
                                                size: 42,
                                                isOnlineMesh: user.isOnline,
                                                showStatusBadge: true
                                            )
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(user.displayName)
                                                    .font(.myaowHeadline)
                                                    .foregroundColor(MyaowColor.textPrimary)
                                                
                                                HStack(spacing: 6) {
                                                    Text(user.username.hasPrefix("@") ? user.username : "@\(user.username)")
                                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                                        .foregroundColor(MyaowColor.orange)
                                                    
                                                    Text("• \(user.myaowId)")
                                                        .font(.myaowMono)
                                                        .foregroundColor(MyaowColor.textTertiary)
                                                }
                                            }
                                            
                                            Spacer()
                                            
                                            HStack(spacing: 4) {
                                                Image(systemName: "lock.shield.fill")
                                                    .font(.system(size: 11))
                                                Text("Conectar")
                                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(MyaowColor.orange)
                                            .clipShape(Capsule())
                                        }
                                        .padding(12)
                                        .background(MyaowColor.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        
                        // Conexión rápida por QR
                        MyaowCard(padding: 14) {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(MyaowColor.orange.opacity(0.15))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "qrcode.viewfinder")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(MyaowColor.orange)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Escanear Código QR")
                                        .font(.myaowHeadline)
                                        .foregroundColor(MyaowColor.textPrimary)
                                    Text("Handshake físico bilateral presencial")
                                        .font(.myaowCaption)
                                        .foregroundColor(MyaowColor.textSecondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(MyaowColor.textTertiary)
                            }
                        }
                        .onTapGesture {
                            showingQRScanner = true
                        }
                        
                        // Añadir por Myaow ID
                        MyaowCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("AÑADIR MANUALMENTE POR ID")
                                    .font(.myaowMicro)
                                    .foregroundColor(MyaowColor.textSecondary)
                                
                                TextField("Nombre (ej. Elena R.)", text: $newContactName)
                                    .font(.myaowBody)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(MyaowColor.surfaceSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                TextField("ID Myaow (ej. MYAOW-9X2Y)", text: $newContactMyaowId)
                                    .font(.myaowMono)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(MyaowColor.surfaceSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                
                                MyaowPillButton("Iniciar Conversación Cifrada", icon: "paperplane.fill", isFullWidth: true) {
                                    createAndOpenChat()
                                }
                                .disabled(!canCreateManualChat)
                                .opacity(canCreateManualChat ? 1 : 0.5)
                                Text("Escribe el ID que te compartió tu contacto, por ejemplo MYAOW-9X2Y.")
                                    .font(.myaowCaption)
                                    .foregroundStyle(MyaowColor.textSecondary)
                            }
                        }
                        
                        // Contactos Locales
                        if !contacts.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("CONTACTOS DISPONIBLES")
                                    .font(.myaowMicro)
                                    .foregroundColor(MyaowColor.textSecondary)
                                    .padding(.horizontal, 4)
                                
                                ForEach(contacts) { contact in
                                    Button(action: {
                                        openChatForContact(contact)
                                    }) {
                                        HStack(spacing: 12) {
                                            MyaowAvatarView(
                                                source: .cat(state: .friendly, style: .darkOnOrange),
                                                size: 40,
                                                isOnlineMesh: contact.isMeshNearby
                                            )
                                            
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(contact.displayName)
                                                    .font(.myaowHeadline)
                                                    .foregroundColor(MyaowColor.textPrimary)
                                                Text(contact.myaowId)
                                                    .font(.myaowMono)
                                                    .foregroundColor(MyaowColor.textSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "bubble.right.fill")
                                                .foregroundColor(MyaowColor.orange)
                                        }
                                        .padding(12)
                                        .background(MyaowColor.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Nuevo Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .foregroundColor(MyaowColor.orange)
                }
            }
            .fullScreenCover(isPresented: $showingQRScanner) {
                QRScannerView()
            }
        }
    }
    
    private func openExistingConversation(for myaowId: String) -> Bool {
        let existing = (try? modelContext.fetch(FetchDescriptor<ConversationModel>())) ?? []
        guard let conversation = existing.first(where: {
            !$0.isGroup && ($0.recipientMyaowId.caseInsensitiveCompare(myaowId) == .orderedSame ||
                (myaowId == "MYAOW-TEAM" && $0.recipientMyaowId.isEmpty && $0.title == "Myaow Team"))
        }) else { return false }
        dismiss()
        onSelectConversation?(conversation)
        return true
    }

    private func openChatFromDirectoryUser(_ user: DirectoryUserResult) {
        if openExistingConversation(for: user.myaowId) { return }
        let newChat = ConversationModel(
            title: user.displayName,
            recipientMyaowId: user.myaowId,
            isGroup: false,
            unreadCount: 0,
            lastMessageSnippet: "Envía el primer mensaje",
            lastMessageTimestamp: Date(),
            isMeshConnected: user.isOnline,
            nodeCount: 1,
            participantNames: [user.displayName]
        )
        
        modelContext.insert(newChat)
        try? modelContext.save()
        
        dismiss()
        onSelectConversation?(newChat)
    }
    
    private func createAndOpenChat() {
        guard !newContactName.isEmpty else { return }
        let idString = newContactMyaowId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard idString.range(of: "^MYAOW-[A-Z0-9]{4,32}$", options: .regularExpression) != nil else { return }
        if openExistingConversation(for: idString) { return }
        
        let newChat = ConversationModel(
            title: newContactName,
            recipientMyaowId: idString,
            isGroup: false,
            unreadCount: 0,
            lastMessageSnippet: "Conversación cifrada iniciada",
            lastMessageTimestamp: Date(),
            isMeshConnected: true,
            nodeCount: 1,
            participantNames: [newContactName]
        )
        
        modelContext.insert(newChat)
        try? modelContext.save()
        
        dismiss()
        onSelectConversation?(newChat)
    }
    
    private func openChatForContact(_ contact: ContactModel) {
        if openExistingConversation(for: contact.myaowId) { return }
        let newChat = ConversationModel(
            title: contact.displayName,
            recipientMyaowId: contact.myaowId,
            isGroup: false,
            unreadCount: 0,
            lastMessageSnippet: "Conversación cifrada iniciada",
            lastMessageTimestamp: Date(),
            isMeshConnected: contact.isMeshNearby,
            nodeCount: 1,
            participantNames: [contact.displayName]
        )
        modelContext.insert(newChat)
        try? modelContext.save()
        
        dismiss()
        onSelectConversation?(newChat)
    }
}
