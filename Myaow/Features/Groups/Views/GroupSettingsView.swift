import SwiftUI

struct GroupSettingsView: View {
    @Binding var space: GroupSpaceModel
    var onLeave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var inviting = false
    @State private var leaving = false
    @State private var removal: SpaceMemberModel?
    @State private var busy = false
    @State private var error: String?
    private var own: String { IdentityManager.shared.currentIdentity.myaowId }
    private var isOwner: Bool { space.ownerMyaowId == own }
    private var canManage: Bool { isOwner || space.members.contains { $0.myaowId == own && ["Admin", "Creador", "Creadora"].contains($0.role) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    GroupPanel(accented: true) {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack(alignment: .top) {
                                GroupMascotBadgeView(category: space.category, size: 76).accessibilityHidden(true)
                                Spacer()
                                GroupBadge(title: "Por invitación", symbol: "lock", accent: true)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text(space.title).font(.system(size: 30, weight: .semibold)).tracking(-0.8)
                                Text(space.description.isEmpty ? "Un espacio para conversar y hacer que las cosas pasen." : space.description)
                                    .font(.subheadline).foregroundStyle(MyaowColor.textSecondary).lineSpacing(3)
                            }
                            HStack(spacing: 10) {
                                GroupBadge(title: space.category.rawValue, symbol: space.category.symbol)
                                GroupBadge(title: "\(space.memberCount) integrantes", symbol: "person.2")
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        GroupEyebrow(title: "El espacio")
                        GroupPanel {
                            VStack(spacing: 0) {
                                actionRow("Nombre y descripción", subtitle: canManage ? "La identidad de tu grupo" : "Solo administradores pueden editar", symbol: "pencil", enabled: canManage) { editing = true }
                                Divider().overlay(MyaowColor.borderSubtle).padding(.vertical, 14)
                                actionRow("Invitar a alguien", subtitle: canManage ? "Una invitación para una cuenta concreta" : "Solicita una invitación a tu administrador", symbol: "person.badge.plus", enabled: canManage) { inviting = true }
                            }
                        }
                    }
                    GroupPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            GroupEyebrow(title: "Permisos de tareas")
                            Picker("Quién puede trabajar en las tareas", selection: Binding(get: { space.taskPolicy }, set: { savePolicy($0) })) {
                                ForEach(GroupTaskPolicy.allCases, id: \.self) { policy in Text(policy.title).tag(policy) }
                            }.disabled(!canManage).tint(MyaowColor.orange)
                            Text(space.taskPolicy.detail).font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        HStack { GroupEyebrow(title: "Integrantes"); Spacer(); Text("\(space.members.count)").font(.caption.monospacedDigit()).foregroundStyle(MyaowColor.textSecondary) }
                        GroupPanel {
                            VStack(spacing: 18) {
                                if space.members.isEmpty {
                                    Text("Los integrantes aparecerán al conectar con el grupo.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                                }
                                ForEach(space.members) { member in
                                    memberRow(member)
                                    if member.id != space.members.last?.id { Divider().overlay(MyaowColor.borderSubtle) }
                                }
                            }
                        }
                        Text("Las funciones de administración dependen de tu rol. Los cambios se aplican después de que el servidor los confirme.")
                            .font(.caption).foregroundStyle(MyaowColor.textSecondary).lineSpacing(3)
                    }
                    GroupPanel {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "person.badge.shield.checkmark").font(.title2).foregroundStyle(MyaowColor.orange)
                            VStack(alignment: .leading, spacing: 7) {
                                Text("Tu grupo tiene límites claros.").font(.subheadline.weight(.semibold))
                                Text("Compartir el código no abre el grupo a cualquiera: solo la cuenta invitada puede aceptarlo.")
                                    .font(.caption).foregroundStyle(MyaowColor.textSecondary).lineSpacing(3)
                            }
                        }
                    }
                    if !isOwner {
                        Button(role: .destructive) { leaving = true } label: {
                            Label("Salir del grupo", systemImage: "rectangle.portrait.and.arrow.right").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(minHeight: 52)
                        }.tint(MyaowColor.statusRed)
                    } else {
                        Label("Eres quien creó este grupo", systemImage: "crown").font(.caption).foregroundStyle(MyaowColor.textSecondary).frame(maxWidth: .infinity)
                    }
                }.padding(24).padding(.bottom, 16)
            }
            .background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
            .navigationTitle("Configuración del grupo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.tint(MyaowColor.orange).disabled(busy) } }
            .disabled(busy)
            .overlay { if busy { ProgressView("Guardando cambios…").tint(MyaowColor.orange).padding(24).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20)) } }
            .sheet(isPresented: $editing) { GroupIdentityEditor(space: $space) }
            .sheet(isPresented: $inviting) { GroupInvitationSheet(groupId: space.id.uuidString, existingMemberIDs: Set(space.members.map(\.myaowId))) }
            .confirmationDialog("¿Salir de \(space.title)?", isPresented: $leaving, titleVisibility: .visible) {
                Button("Salir del grupo", role: .destructive) { performLeave() }
            } message: { Text("Dejarás de recibir nuevos mensajes y de acceder a las tareas del grupo. Necesitarás otra invitación para volver.") }
            .confirmationDialog("¿Retirar a \(removal?.displayName ?? "esta persona")?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } }), titleVisibility: .visible) {
                if let member = removal { Button("Retirar del grupo", role: .destructive) { remove(member) } }
            } message: { Text("Dejará de recibir nuevos mensajes y de acceder a las tareas de este grupo.") }
            .alert("No se guardó el cambio", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Entendido", role: .cancel) {}
            } message: { Text(error ?? "") }
        }.preferredColorScheme(.dark).interactiveDismissDisabled(busy).presentationDragIndicator(.visible)
    }
    private func actionRow(_ title: String, subtitle: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(MyaowColor.orange).frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(MyaowColor.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(MyaowColor.textSecondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: enabled ? "chevron.right" : "lock").font(.caption).foregroundStyle(MyaowColor.textSecondary)
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled)
    }
    private func memberRow(_ member: SpaceMemberModel) -> some View {
        HStack(spacing: 12) {
            MyaowCatView(state: member.catState, style: .darkOnOrange, size: 40, isInteractive: false).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(member.displayName + (member.myaowId == own ? " · Tú" : "")).font(.subheadline.weight(.medium))
                Text(member.myaowId == space.ownerMyaowId ? "Creador del grupo" : member.role).font(.caption).foregroundStyle(MyaowColor.textSecondary)
            }
            Spacer(minLength: 0)
            if canManage && member.myaowId != own && member.myaowId != space.ownerMyaowId && (isOwner || member.role == "Miembro") {
                Menu {
                    if isOwner && member.role == "Miembro" { Button("Hacer administrador", systemImage: "person.badge.key") { promote(member) } }
                    Button("Retirar del grupo", systemImage: "person.badge.minus", role: .destructive) { removal = member }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle()) }.tint(MyaowColor.textSecondary).accessibilityLabel("Administrar a \(member.displayName)")
            }
        }
    }
    private func savePolicy(_ policy: GroupTaskPolicy) {
        guard canManage, !busy, policy != space.taskPolicy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            guard !DesignPreviewData.isEnabled else { error = "Vista de diseño con datos ficticios."; return }
            if await GroupsNetworkService.shared.updateGroupInfo(groupId: space.id.uuidString, name: nil, description: nil, taskPolicy: policy) { space.taskPolicy = policy }
            else { error = GroupsNetworkService.shared.lastError }
        }
    }
    private func performLeave() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            guard !DesignPreviewData.isEnabled else { error = "Esta es una vista de diseño con datos ficticios."; return }
            if await GroupsNetworkService.shared.leaveGroup(groupId: space.id.uuidString) { dismiss(); onLeave() }
            else { error = GroupsNetworkService.shared.lastError ?? "No pudimos confirmar tu salida." }
        }
    }
    private func remove(_ member: SpaceMemberModel) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            guard !DesignPreviewData.isEnabled else { error = "Esta es una vista de diseño con datos ficticios."; return }
            if await GroupsNetworkService.shared.kickMember(groupId: space.id.uuidString, targetMyaowId: member.myaowId) {
                space.members.removeAll { $0.myaowId == member.myaowId }; space.memberCount = space.members.count
            } else { error = GroupsNetworkService.shared.lastError }
        }
    }
    private func promote(_ member: SpaceMemberModel) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            guard !DesignPreviewData.isEnabled else { error = "Esta es una vista de diseño con datos ficticios."; return }
            if await GroupsNetworkService.shared.promoteMember(groupId: space.id.uuidString, targetMyaowId: member.myaowId) {
                do { space.members = try await GroupDeliveryService.members(space.id.uuidString).map(\.model) }
                catch { self.error = "El rol se guardó, pero no pudimos actualizar la lista. Vuelve a abrir el grupo." }
            } else { error = GroupsNetworkService.shared.lastError }
        }
    }
}

private struct GroupIdentityEditor: View {
    @Binding var space: GroupSpaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    GroupMascotBadgeView(category: space.category, size: 80).frame(maxWidth: .infinity).padding(.vertical, 12)
                    GroupEyebrow(title: "Nombre del grupo")
                    TextField("Nombre", text: $name, axis: .vertical).font(.title3.weight(.medium)).padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 18))
                    GroupEyebrow(title: "Descripción")
                    TextField("Qué los reúne y qué quieren lograr", text: $description, axis: .vertical).lineLimit(4...7).padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 18))
                    Text("\(name.count)/80 · Descripción \(description.count)/1000").font(.caption.monospacedDigit()).foregroundStyle(name.count > 80 || description.count > 1000 ? MyaowColor.statusRed : MyaowColor.textSecondary)
                    if let error { Text(error).font(.subheadline).foregroundStyle(MyaowColor.statusRed) }
                    Button { save() } label: { HStack { if saving { ProgressView().tint(.black) }; Text(saving ? "Guardando…" : "Guardar cambios") } }.buttonStyle(GroupPrimaryStyle())
                        .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || description.count > 1000)
                }.padding(24).disabled(saving)
            }.background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
                .navigationTitle("Identidad del grupo").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) } }
                .onAppear { name = space.title; description = space.description }
        }.preferredColorScheme(.dark).interactiveDismissDisabled(saving)
    }
    private func save() {
        guard !saving else { return }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            guard !DesignPreviewData.isEnabled else { error = "Los cambios de esta vista no se guardan en el servidor."; return }
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let savedDescription = description
            if await GroupsNetworkService.shared.updateGroupInfo(groupId: space.id.uuidString, name: clean, description: savedDescription) { space.title = clean; space.description = savedDescription; dismiss() }
            else { error = GroupsNetworkService.shared.lastError }
        }
    }
}
