//
//  ContactsListView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public enum ContactConnectionSheet: Int, Identifiable {
    case handshake = 0
    case qrScanner = 1
    case myQR = 2
    case addById = 3
    
    public var id: Int { rawValue }
}

public struct ContactsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ContactModel.displayName) private var contacts: [ContactModel]
    
    @AppStorage("dismissed_tu_gente_edu_banner") private var isEduBannerDismissed: Bool = false
    
    @State private var searchText = ""
    @State private var activeSheet: ContactConnectionSheet? = nil
    @State private var manualMyaowId = ""
    @State private var selectedConversation: ConversationModel? = nil
    
    private var filteredContacts: [ContactModel] {
        if searchText.isEmpty {
            return contacts
        } else {
            return contacts.filter {
                $0.displayName.localizedCaseInsensitiveContains(searchText) ||
                $0.myaowId.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MyaowScreenHeader(title: "Tu gente", subtitle: "Las conexiones que sí importan.") {
                        Menu {
                            Button { activeSheet = .qrScanner } label: { Label("Escanear QR", systemImage: "qrcode.viewfinder") }
                            Button { activeSheet = .addById } label: { Label("Buscar por ID", systemImage: "at") }
                            Button { activeSheet = .handshake } label: { Label("Conectar en persona", systemImage: "hand.wave") }
                        } label: {
                            Image(systemName: "person.badge.plus").font(.system(size: 20)).foregroundStyle(.black)
                                .frame(width: 48, height: 48).background(MyaowColor.orange, in: RoundedRectangle(cornerRadius: 17))
                        }
                        .accessibilityLabel("Agregar contacto")
                    }
                    MyaowSearchField(text: $searchText, placeholder: "Buscar por nombre o ID")
                        .padding(.horizontal, 24)
                    if searchText.isEmpty {
                        HStack(spacing: 12) {
                            connectionTile("Mi código", subtitle: "Tu puerta de entrada", symbol: "qrcode", light: true) { activeSheet = .myQR }
                            connectionTile("Escanear", subtitle: "Conecta en un instante", symbol: "viewfinder") { activeSheet = .qrScanner }
                        }
                        .padding(.horizontal, 24)
                    }
                    MyaowSectionLabel(title: "Contactos", detail: "\(filteredContacts.count)")
                        .padding(.horizontal, 24)
                    if filteredContacts.isEmpty {
                        MyaowEmptyState(title: searchText.isEmpty ? "Encuentra a los tuyos." : "Sin coincidencias",
                            message: searchText.isEmpty ? "Comparte tu código o agrega el ID de alguien. Tú decides con quién conectar." : "Intenta con otro nombre o identificador.",
                            symbol: "person.2", actionTitle: searchText.isEmpty ? "Compartir mi código" : "Limpiar búsqueda",
                            action: { if searchText.isEmpty { activeSheet = .myQR } else { searchText = "" } })
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredContacts) { contact in
                                Button { openChatForContact(contact) } label: {
                                    VStack(spacing: 0) {
                                        TuGenteContactRowView(contact: contact)
                                        Rectangle().fill(MyaowColor.borderSubtle).frame(height: 0.5).padding(.leading, 70)
                                    }
                                    .padding(.horizontal, 24)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppAtmosphereStyle.page)
            .containerBackground(AppAtmosphereStyle.page, for: .navigation)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedConversation) { ChatDetailView(conversation: $0) }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .handshake: MyaowHandshakeModalView().presentationDetents([.large])
                case .qrScanner: QRScannerView()
                case .myQR: MyQRCodeView()
                case .addById: addByMyaowIdSheet
                }
            }
        }
    }

    private func connectionTile(_ title: String, subtitle: String, symbol: String, light: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 27, weight: .light))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 14))
                }
                .padding(.bottom, 16)
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).opacity(0.65)
            }
            .foregroundStyle(light ? MyaowColor.charcoal : MyaowColor.textPrimary)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(light ? MyaowColor.textPrimary : MyaowColor.surface, in: RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }

    private func openChatForContact(_ contact: ContactModel) {
        let descriptor = FetchDescriptor<ConversationModel>()
        let allConvs = (try? modelContext.fetch(descriptor)) ?? []
        
        if let existing = allConvs.first(where: { $0.recipientMyaowId == contact.myaowId || $0.title == contact.displayName }) {
            selectedConversation = existing
        } else {
            let newChat = ConversationModel(
                title: contact.displayName,
                recipientMyaowId: contact.myaowId,
                isGroup: false,
                unreadCount: 0,
                lastMessageSnippet: "Conversación iniciada",
                lastMessageTimestamp: Date(),
                isMeshConnected: contact.isMeshNearby,
                nodeCount: 1,
                participantNames: [contact.displayName]
            )
            modelContext.insert(newChat)
            try? modelContext.save()
            selectedConversation = newChat
        }
    }
    
    private var addByMyaowIdSheet: some View {
        ZStack {
            MyaowColor.charcoal.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Capsule().fill(MyaowColor.surfaceSecondary).frame(width: 36, height: 4).padding(.top, 12)
                
                Image(systemName: "at")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundColor(MyaowColor.orange)
                
                Text("Conectar por ID de Myaow")
                    .font(.myaowTitle)
                    .foregroundColor(MyaowColor.textPrimary)
                
                Text("Introduce el Myaow ID único para guardar un contacto. Podrás verificar su identidad al conectar.")
                    .font(.myaowBody)
                    .multilineTextAlignment(.center)
                    .foregroundColor(MyaowColor.textSecondary)
                    .padding(.horizontal, 24)
                
                TextField("Ej: MYAOW-ANA1", text: $manualMyaowId)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color(hex: "#18181A"))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .autocapitalization(.allCharacters)
                
                Spacer()
                
                MyaowPillButton("Guardar contacto", style: .primary, isFullWidth: true) {
                    let cleanedId = manualMyaowId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                    if cleanedId.range(of: "^MYAOW-[A-Z0-9]{4,32}$", options: .regularExpression) != nil {
                        if let existing = contacts.first(where: { $0.myaowId.caseInsensitiveCompare(cleanedId) == .orderedSame }) {
                            activeSheet = nil
                            openChatForContact(existing)
                            return
                        }
                        let newContact = ContactModel(
                            myaowId: cleanedId,
                            did: "did:myaow:\(cleanedId.lowercased())",
                            displayName: "Usuario \(cleanedId.suffix(4))",
                            avatarCatState: "Amigable",
                            isMeshNearby: false,
                            isVerified: false
                        )
                        modelContext.insert(newContact)
                        try? modelContext.save()
                        
                        activeSheet = nil
                        manualMyaowId = ""
                        openChatForContact(newContact)
                    }
                }
                .disabled(manualMyaowId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().range(of: "^MYAOW-[A-Z0-9]{4,32}$", options: .regularExpression) == nil)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.fraction(0.55)])
    }
}

#Preview {
    ContactsListView()
        .modelContainer(for: ContactModel.self, inMemory: true)
}
