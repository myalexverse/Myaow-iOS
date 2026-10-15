import SwiftUI
import SwiftData

public enum GroupsFilter: String, CaseIterable, Identifiable {
    case all = "Todos", active = "Activos", completed = "Recuerdos"
    public var id: String { rawValue }
}

public struct GroupsListView: View {
    @State private var spaces: [GroupSpaceModel] = []
    @State private var showingJoin = false
    @State private var searchText = ""
    @State private var categoryFilter: SpaceCategory?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingCreateSpaceModal = false
    @State private var selectedSpaceForDetail: GroupSpaceModel?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var fetching = false
    public init() {}

    private var filteredSpaces: [GroupSpaceModel] {
        spaces.filter { (searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)) && (categoryFilter == nil || $0.category == categoryFilter) }
    }
    private func loadGroups() async {
        guard !fetching else { return }
        fetching = true
        isLoading = true
        defer { isLoading = false; fetching = false }
        if DesignPreviewData.isEnabled { spaces = DesignPreviewData.spaces; loadError = nil; return }
        let fetched = await GroupsNetworkService.shared.fetchMyGroups()
        loadError = GroupsNetworkService.shared.lastError
        guard loadError == nil else { return }
        spaces = fetched.compactMap { data in
            guard let idString = data["id"] as? String, let id = UUID(uuidString: idString) else { return nil }
            return GroupSpaceModel(id: id, title: data["name"] as? String ?? "Grupo",
                description: data["description"] as? String ?? "",
                category: SpaceCategory(rawValue: data["category"] as? String ?? "") ?? .general,
                memberCount: data["memberCount"] as? Int ?? 0, connectedCount: 0, isMeshActive: false,
                lastMessage: data["lastMessage"] as? String ?? "", lastMessageTime: "", pulseStatusText: "", streakDays: 0, ownerMyaowId: data["created_by"] as? String, taskPolicy: GroupTaskPolicy(rawValue: data["task_policy"] as? String ?? "assigned") ?? .assigned)
        }
    }
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    MyaowScreenHeader(title: "Grupos", subtitle: "Conversar es solo el principio.") {
                        MyaowIconAction(symbol: "plus", label: "Crear grupo", prominent: true) { showingCreateSpaceModal = true }
                    }
                    GroupPanel(accented: true) {
                        VStack(alignment: .leading, spacing: 22) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 12) {
                                    GroupEyebrow(title: "En buena compañía")
                                    Text("De la idea\nal siguiente paso.").font(.system(size: 29, weight: .semibold)).tracking(-0.9).fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                MyaowCatView(state: .curious, style: .darkOnOrange, size: 66, isInteractive: false).rotationEffect(.degrees(-8)).accessibilityHidden(true)
                            }
                            Text("Un lugar para repartir tareas, compartir avances y organizar lo que viene.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary).lineSpacing(3)
                            HStack(spacing: 8) {
                                GroupBadge(title: "Tareas", symbol: "checklist", accent: true)
                                GroupBadge(title: "Programar", symbol: "clock", accent: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }.padding(.horizontal, 24)
                    HStack {
                        GroupEyebrow(title: "Tus espacios")
                        if !isLoading { Text("\(spaces.count)").font(.caption.monospacedDigit()).foregroundStyle(MyaowColor.textSecondary) }
                        Spacer()
                        Button { showingJoin = true } label: { Label("Unirme", systemImage: "person.badge.key").font(.subheadline.weight(.medium)).frame(minHeight: 44) }.tint(MyaowColor.orange)
                    }.padding(.horizontal, 24)
                    MyaowSearchField(text: $searchText, placeholder: "Buscar un grupo").padding(.horizontal, 24)
                    if !spaces.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                categoryChip(nil)
                                ForEach(SpaceCategory.allCases.filter { category in spaces.contains { $0.category == category } }) { category in categoryChip(category) }
                            }.padding(.horizontal, 24)
                        }
                    }
                    if isLoading && spaces.isEmpty {
                        ProgressView("Cargando tus espacios…").tint(MyaowColor.orange).foregroundStyle(MyaowColor.textSecondary).frame(maxWidth: .infinity).padding(40)
                    } else {
                        if loadError != nil {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "wifi.exclamationmark").foregroundStyle(MyaowColor.orange)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("No pudimos actualizar los grupos.").font(.subheadline.weight(.medium))
                                    Button("Volver a intentar") { Task { await loadGroups() } }.font(.subheadline).tint(MyaowColor.orange)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20)).padding(.horizontal, 24)
                        }
                        if filteredSpaces.isEmpty && loadError == nil {
                            MyaowEmptyState(title: spaces.isEmpty ? "Todo empieza con tu gente." : "Sin grupos en esta vista.", message: spaces.isEmpty ? "Crea un espacio o acepta una invitación para empezar." : "Prueba otra categoría o un nombre diferente.", symbol: "person.3.sequence", actionTitle: spaces.isEmpty ? "Crear un grupo" : "Ver todos", action: { if spaces.isEmpty { showingCreateSpaceModal = true } else { searchText = ""; categoryFilter = nil } })
                        }
                        LazyVStack(spacing: 14) {
                            ForEach(filteredSpaces) { space in
                                Button { selectedSpaceForDetail = space } label: {
                                    GroupPanel {
                                        VStack(alignment: .leading, spacing: 18) {
                                            HStack(spacing: 14) {
                                                GroupMascotBadgeView(category: space.category, size: 54).accessibilityHidden(true)
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(space.title).font(.system(size: 19, weight: .semibold)).tracking(-0.3).foregroundStyle(MyaowColor.textPrimary)
                                                    Text(space.description.isEmpty ? space.category.rawValue : space.description).font(.subheadline).foregroundStyle(MyaowColor.textSecondary).lineLimit(2)
                                                }
                                                Spacer(minLength: 0)
                                                Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .medium)).foregroundStyle(MyaowColor.orange)
                                            }
                                            HStack(spacing: 10) {
                                                Label("\(space.memberCount) integrantes", systemImage: "person.2").font(.caption)
                                                Spacer()
                                                Label("Privado", systemImage: "lock").font(.caption)
                                            }.foregroundStyle(MyaowColor.textSecondary)
                                        }
                                    }
                                }.buttonStyle(.plain).accessibilityLabel("\(space.title), \(space.memberCount) integrantes. Abrir grupo")
                            }
                        }.padding(.horizontal, 24)
                    }
                }.padding(.bottom, 28).foregroundStyle(MyaowColor.textPrimary)
            }
            .refreshable { await loadGroups() }
            .background(AppAtmosphereStyle.page)
            .containerBackground(AppAtmosphereStyle.page, for: .navigation)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $selectedSpaceForDetail) { GroupSpaceDetailView(space: $0) }
            .sheet(isPresented: $showingCreateSpaceModal) { MyaowCreateGroupSheet { space in spaces.insert(space, at: 0) } }
            .sheet(isPresented: $showingJoin) { GroupInvitationSheet(onJoined: { Task { await loadGroups() } }) }
            .task { await loadGroups() }
            .onChange(of: OnlineMessagingService.shared.collaborationRevision) { _, _ in Task { await loadGroups() } }
            .onChange(of: selectedSpaceForDetail) { old, new in if old != nil && new == nil { Task { await loadGroups() } } }
            .onAppear {
                if DesignPreviewData.consumeLaunchRoute("--group-detail-preview") { selectedSpaceForDetail = DesignPreviewData.spaces.first }
                if DesignPreviewData.consumeLaunchRoute("--group-create-preview") { showingCreateSpaceModal = true }
            }
        }.preferredColorScheme(.dark)
    }
    private func categoryChip(_ category: SpaceCategory?) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { categoryFilter = category }
        } label: {
            Text(category?.rawValue ?? "Todos").font(.subheadline.weight(.medium))
                .foregroundStyle(categoryFilter == category ? MyaowColor.textPrimary : MyaowColor.textSecondary)
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background(categoryFilter == category ? MyaowColor.surfaceElevated : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(categoryFilter == category ? MyaowColor.orange.opacity(0.6) : MyaowColor.borderSubtle))
        }.buttonStyle(.plain).accessibilityAddTraits(categoryFilter == category ? .isSelected : [])
    }

}

private struct MyaowCreateGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = SpaceCategory.general
    @State private var isCreating = false
    @State private var error: String?
    var onCreated: (GroupSpaceModel) -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    MyaowCatView(state: .happy, style: .darkOnOrange, size: 80, isInteractive: false).frame(maxWidth: .infinity).padding(.top, 12)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Una idea. Tu equipo.").font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                        Text("Crea el espacio; después invita a cada persona y asigna el primer paso.").font(.system(size: 15)).foregroundStyle(MyaowColor.textSecondary)
                    }
                    TextField("Nombre del grupo", text: $name).font(.system(size: 18)).padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16)).autocorrectionDisabled()
                    GroupEyebrow(title: "Elige un ambiente")
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(SpaceCategory.allCases) { option in
                            Button { category = option } label: {
                                HStack { Image(systemName: option.symbol); Text(option.rawValue); Spacer(); if category == option { Image(systemName: "checkmark") } }
                                    .font(.subheadline.weight(.medium)).foregroundStyle(category == option ? MyaowColor.orange : MyaowColor.textSecondary).padding(16)
                                    .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16))
                                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(category == option ? MyaowColor.orange.opacity(0.5) : MyaowColor.borderSubtle))
                            }.buttonStyle(.plain).accessibilityAddTraits(category == option ? .isSelected : [])
                        }
                    }
                    Label("Solo entran las cuentas que invites", systemImage: "lock").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    if name.count > 80 { Text("Usa un nombre de hasta 80 caracteres.").font(.caption).foregroundStyle(MyaowColor.statusRed) }
                    if let error { Text(error).font(.system(size: 14)).foregroundStyle(MyaowColor.statusRed) }
                    Button {
                        isCreating = true
                        error = nil
                        Task { @MainActor in
                            defer { isCreating = false }
                            guard !DesignPreviewData.isEnabled else { error = "Esta es una vista de diseño. Conecta una cuenta real para crear el grupo."; return }
                            guard let raw = await GroupsNetworkService.shared.createGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines), category: category.rawValue), let id = UUID(uuidString: raw) else {
                                error = GroupsNetworkService.shared.lastError ?? "No pudimos crear el grupo. Intenta de nuevo."
                                return
                            }
                            onCreated(GroupSpaceModel(id: id, title: name, category: category, memberCount: 1, connectedCount: 0, isMeshActive: false, lastMessage: "", lastMessageTime: "", pulseStatusText: "", streakDays: 0, ownerMyaowId: IdentityManager.shared.currentIdentity.myaowId, taskPolicy: .open))
                            dismiss()
                        }
                    } label: {
                        HStack { Spacer(); if isCreating { ProgressView().tint(.black) }; Text(isCreating ? "Creando grupo…" : "Crear grupo"); Spacer() }
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.black).padding(18).background(MyaowColor.orange, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .disabled(isCreating || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80)
                    .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }.padding(24).foregroundStyle(MyaowColor.textPrimary).disabled(isCreating)
            }
            .background(MyaowColor.charcoal)
            .navigationTitle("Nuevo grupo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(isCreating).tint(MyaowColor.textSecondary) } }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isCreating)
    }
}

struct GroupInvitationSheet: View {
    @Environment(\.dismiss) private var dismiss
    var groupId: String? = nil
    var existingMemberIDs: Set<String> = []
    @Query(sort: \ContactModel.displayName) private var contacts: [ContactModel]
    @State private var contactSearch = ""
    @State private var invitedIDs: Set<String> = []
    var onJoined: (() -> Void)? = nil
    @State private var value = ""
    @State private var token: String?
    @State private var copied = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    GroupPanel(accented: true) {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Image(systemName: token == nil ? "person.badge.key" : "checkmark.seal").font(.system(size: 32, weight: .light)).foregroundStyle(MyaowColor.orange)
                                Spacer()
                                GroupBadge(title: "Acceso personal", symbol: "lock", accent: true)
                            }
                            Text(token != nil ? "Su lugar está reservado." : groupId == nil ? "Te estaban esperando." : "Invita a tu gente.").font(.system(size: 29, weight: .semibold)).tracking(-0.7)
                            Text(token != nil ? "Comparte este código con la cuenta que invitaste. Otra persona no podrá utilizarlo." : groupId == nil ? "Pega el código que te compartieron. La invitación debe estar dirigida a tu cuenta." : "Elige una cuenta concreta. La persona decide si quiere formar parte del grupo.")
                                .font(.subheadline).foregroundStyle(MyaowColor.textSecondary).lineSpacing(4)
                        }
                    }
                    if let token {
                        GroupEyebrow(title: "Código de invitación")
                        Text(token).font(.system(size: 16, weight: .medium, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).padding(20).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
                        HStack(spacing: 12) {
                            Button { UIPasteboard.general.string = token; copied = true } label: { Label(copied ? "Copiado" : "Copiar", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity).frame(minHeight: 52).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16)) }.tint(MyaowColor.textPrimary)
                            ShareLink(item: token) { Label("Compartir", systemImage: "square.and.arrow.up") }.buttonStyle(GroupPrimaryStyle())
                        }
                        Button("Invitar a otra persona") { invitedIDs.insert(value); self.token = nil; value = ""; copied = false; contactSearch = "" }.tint(MyaowColor.orange)
                        Label("Invitación creada para \(contacts.first { $0.myaowId == value }?.displayName ?? value)", systemImage: "person.crop.circle.badge.checkmark").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if groupId != nil { contactPicker }
                            GroupEyebrow(title: groupId == nil ? "Tu invitación" : "O introduce un usuario o ID")
                            TextField(groupId == nil ? "Pega el código aquí" : "@usuario exacto", text: $value).textInputAutocapitalization(.never).autocorrectionDisabled().padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 18))
                                .accessibilityLabel(groupId == nil ? "Código de invitación" : "Usuario invitado")
                            Text(groupId == nil ? "El código es personal y temporal." : "Necesitas permisos de administración para invitar.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        }
                        if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(MyaowColor.statusRed) }
                        Button(action: submit) { HStack { if busy { ProgressView().tint(.black) }; Text(busy ? "Comprobando…" : groupId == nil ? "Aceptar invitación" : "Crear invitación") } }.buttonStyle(GroupPrimaryStyle()).disabled(busy || value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .opacity(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    }
                }.padding(24).disabled(busy)
            }.background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
                .navigationTitle(groupId == nil ? "Unirme a un grupo" : "Invitar al grupo").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.disabled(busy).tint(MyaowColor.orange) } }
        }.preferredColorScheme(.dark).interactiveDismissDisabled(busy).presentationDragIndicator(.visible)
    }
    private var eligibleContacts: [ContactModel] {
        var seen = Set<String>()
        let own = IdentityManager.shared.currentIdentity.myaowId
        return contacts.filter {
            !$0.myaowId.isEmpty && $0.myaowId != own && !existingMemberIDs.contains($0.myaowId)
                && !invitedIDs.contains($0.myaowId) && !ContactBlockingService.shared.isBlocked($0.myaowId)
                && seen.insert($0.myaowId).inserted
                && (contactSearch.isEmpty || $0.displayName.localizedCaseInsensitiveContains(contactSearch) || $0.myaowId.localizedCaseInsensitiveContains(contactSearch))
        }
    }
    private var contactPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupEyebrow(title: "Elegir de Tu gente")
            TextField("Buscar contacto", text: $contactSearch).padding(14).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel("Buscar contacto para invitar")
            if eligibleContacts.isEmpty {
                Text("No hay contactos disponibles con esa búsqueda. También puedes usar un usuario o ID.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
            }
            ForEach(eligibleContacts.prefix(50)) { contact in
                Button { value = contact.myaowId; error = nil } label: {
                    HStack(spacing: 12) {
                        ProfileAvatarView(avatarUrl: contact.avatarUrl, avatarImageData: nil,
                            catState: MyaowCatState(rawValue: contact.avatarCatState) ?? .friendly, size: 42, showMiniCat: false, animateTransition: false)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contact.displayName).font(.subheadline.weight(.semibold))
                            Text(contact.myaowId).font(.caption2).foregroundStyle(MyaowColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: value == contact.myaowId ? "checkmark.circle.fill" : "circle").foregroundStyle(value == contact.myaowId ? MyaowColor.orange : MyaowColor.textSecondary)
                    }.padding(12).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityAddTraits(value == contact.myaowId ? .isSelected : [])
            }
        }
    }
    private func submit() {
        guard !busy else { return }
        busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            guard !DesignPreviewData.isEnabled else { error = "Las invitaciones se activan al conectar una cuenta real. Esta es una vista de diseño."; return }
            do {
                if let groupId {
                    let data = try await RelayAPI.request("/api/v1/groups/invite/create", method: "POST", body: ["groupId": groupId.lowercased(), "target": value.trimmingCharacters(in: .whitespacesAndNewlines)])
                    guard let code = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["token"] as? String, !code.isEmpty else { throw URLError(.cannotParseResponse) }
                    token = code
                } else {
                    _ = try await RelayAPI.request("/api/v1/groups/invite/accept", method: "POST", body: ["token": value.trimmingCharacters(in: .whitespacesAndNewlines)])
                    onJoined?(); dismiss()
                }
            } catch { self.error = error.localizedDescription }
        }
    }
}
