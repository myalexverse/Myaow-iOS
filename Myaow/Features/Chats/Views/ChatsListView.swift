import SwiftUI
import SwiftData

public struct ChatsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ConversationModel.lastMessageTimestamp, order: .reverse) private var conversations: [ConversationModel]
    @AppStorage("myaow_inbox_pinned") private var pinnedIDs = ""
    @AppStorage("myaow_inbox_archived") private var archivedIDs = ""
    @State private var searchText = ""
    @State private var selectedFilter = "Todos"
    @State private var showingNewChatSheet = false
    @State private var selectedConversation: ConversationModel?
    @State private var showingMyQR = false
    @State private var saveError = false

    private func contains(_ storage: String, _ id: String) -> Bool { storage.split(separator: ",").contains(Substring(id)) }
    private func toggled(_ storage: String, _ id: String) -> String {
        var ids = Set(storage.split(separator: ",").map(String.init))
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        return ids.sorted().joined(separator: ",")
    }
    private var unreadCount: Int { conversations.filter { $0.unreadCount > 0 && !contains(archivedIDs, $0.id) }.count }
    private var filteredConversations: [ConversationModel] {
        conversations.filter { conversation in
            let archived = contains(archivedIDs, conversation.id)
            guard selectedFilter == "Archivados" ? archived : !archived else { return false }
            if selectedFilter == "No leídos" && conversation.unreadCount == 0 { return false }
            if selectedFilter == "Grupos" && !conversation.isGroup { return false }
            return searchText.isEmpty || conversation.title.localizedCaseInsensitiveContains(searchText) ||
                conversation.messages.contains { $0.text.localizedCaseInsensitiveContains(searchText) }
        }.sorted {
            let leftPinned = contains(pinnedIDs, $0.id), rightPinned = contains(pinnedIDs, $1.id)
            return leftPinned != rightPinned ? leftPinned : $0.lastMessageTimestamp > $1.lastMessageTimestamp
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .center) {
                        MyaowWordmarkView(fontSize: 30, textColor: MyaowColor.textPrimary)
                            .accessibilityLabel("Myaow")
                        Spacer()
                        MyaowIconAction(symbol: "qrcode", label: "Mi código QR") { showingMyQR = true }
                        MyaowIconAction(symbol: "square.and.pencil", label: "Nuevo mensaje", prominent: true) { showingNewChatSheet = true }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Conversaciones")
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-1.4)
                            .foregroundStyle(MyaowColor.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        HStack(spacing: 7) {
                            Circle().fill(OnlineMessagingService.shared.status == .online ? MyaowColor.statusGreen : MyaowColor.textTertiary).frame(width: 5, height: 5)
                            Text(unreadCount == 1 ? "1 conversación por leer" : unreadCount > 0 ? "\(unreadCount) conversaciones por leer" : "Un lugar para tu gente.")
                                .font(.system(size: 14))
                                .foregroundStyle(MyaowColor.textSecondary)
                        }
                    }
                    .padding(.horizontal, 24)

                    if let error = OnlineMessagingService.shared.authenticationError {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(error).font(.system(size: 14)).foregroundStyle(MyaowColor.textSecondary)
                            Button("Reintentar conexión") { OnlineMessagingService.shared.reconnect() }
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(MyaowColor.orange)
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 24)
                    }

                    MyaowSearchField(text: $searchText, placeholder: "Personas y mensajes")
                        .padding(.horizontal, 24)
                    MyaowFilterTabs(labels: ["Todos", "No leídos", "Grupos", "Archivados"], selection: $selectedFilter)

                    if filteredConversations.isEmpty {
                        MyaowEmptyState(
                            title: searchText.isEmpty ? (selectedFilter == "Todos" ? "Todo empieza con un hola." : "Todo al día.") : "Sin coincidencias",
                            message: searchText.isEmpty ? "Abre una conversación, comparte una idea o simplemente pregunta cómo va el día." : "Prueba con otro nombre o una palabra del mensaje.",
                            actionTitle: searchText.isEmpty ? "Escribir un mensaje" : "Limpiar búsqueda",
                            action: { if searchText.isEmpty { showingNewChatSheet = true } else { searchText = "" } }
                        )
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredConversations) { conversation in
                                Button { selectedConversation = conversation } label: {
                                    VStack(spacing: 0) {
                                        HStack(spacing: 7) {
                                            ChatRowView(conversation: conversation)
                                            if contains(pinnedIDs, conversation.id) {
                                                Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(MyaowColor.textTertiary)
                                            }
                                        }
                                        if !searchText.isEmpty,
                                           let result = conversation.messages.first(where: { $0.text.localizedCaseInsensitiveContains(searchText) }) {
                                            Text(result.text).font(.system(size: 13)).foregroundStyle(MyaowColor.textSecondary)
                                                .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 70).padding(.bottom, 10)
                                        }
                                        Rectangle().fill(MyaowColor.borderSubtle).frame(height: 0.5).padding(.leading, 70)
                                    }
                                    .padding(.horizontal, 24)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { pinnedIDs = toggled(pinnedIDs, conversation.id) } label: {
                                        Label(contains(pinnedIDs, conversation.id) ? "Desfijar conversación" : "Fijar conversación", systemImage: "pin")
                                    }
                                    Button { archivedIDs = toggled(archivedIDs, conversation.id) } label: {
                                        Label(contains(archivedIDs, conversation.id) ? "Volver a la bandeja" : "Archivar", systemImage: "archivebox")
                                    }
                                    Button {
                                        conversation.unreadCount = conversation.unreadCount > 0 ? 0 : 1
                                        do { try modelContext.save() } catch { saveError = true }
                                    } label: {
                                        Label(conversation.unreadCount > 0 ? "Marcar como leído" : "Marcar como no leído", systemImage: "envelope.badge")
                                    }
                                }
                            }
                        }
                    }
                    if !conversations.isEmpty && searchText.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.draw")
                            Text("Mantén presionada una conversación para organizarla.")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(MyaowColor.textTertiary)
                        .padding(.horizontal, 28)
                        .padding(.top, 2)
                    }
                }
                .padding(.bottom, 26)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppAtmosphereStyle.page)
            .containerBackground(AppAtmosphereStyle.page, for: .navigation)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedConversation) { conversation in
                if conversation.isGroup, let id = UUID(uuidString: conversation.id) {
                    GroupSpaceDetailView(space: GroupSpaceModel(id: id, title: conversation.title, memberCount: 0,
                        connectedCount: 0, isMeshActive: false, lastMessage: conversation.lastMessageSnippet, streakDays: 0))
                } else { ChatDetailView(conversation: conversation) }
            }
            .onAppear {
                if DesignPreviewData.consumeLaunchRoute("--chat-detail-preview") {
                    selectedConversation = ProcessInfo.processInfo.arguments.contains("--chat-scroll-check")
                        ? conversations.first { $0.id == "layout-check-direct" }
                        : conversations.first { !$0.isGroup }
                }
            }
            .sheet(isPresented: $showingNewChatSheet) {
                NewChatModalView { selectedConversation = $0 }
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingMyQR) { MyQRCodeView() }
            .alert("No se pudo guardar el cambio", isPresented: $saveError) { Button("Entendido", role: .cancel) {} }
        }
    }
}
