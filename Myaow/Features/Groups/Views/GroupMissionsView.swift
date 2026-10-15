import SwiftUI
import Combine

public enum MissionsFilter: String, CaseIterable, Identifiable {
    case all = "Todas", mine = "Mis pendientes", pending = "Por empezar", active = "En marcha", today = "Para hoy", overdue = "Vencidas", unassigned = "Sin responsable", key = "Claves", daily = "Diarias", weekly = "Semanales", urgent = "Prioridad", completed = "Completadas"
    public var id: String { rawValue }
}

public struct GroupMissionsView: View {
    @Binding public var space: GroupSpaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedFilter: MissionsFilter = .all
    @State private var search = ""
    @State private var selectedTask: GroupMissionModel?
    @State private var taskDraft: GroupMissionDraft?
    @State private var operationError: String?
    @State private var updating = Set<UUID>()
    @State private var deletion: GroupMissionModel?
    @State private var loading = false
    @State private var showingIdeas = false
    @State private var suggestedTitle = ""
    @State private var showMembers = false
    @State private var focusDate = Date()
    @State private var focusRequest = UUID()
    @Environment(\.scenePhase) private var scenePhase
    public init(space: Binding<GroupSpaceModel>) { _space = space }
    private var own: String { IdentityManager.shared.currentIdentity.myaowId }
    private var isAdmin: Bool { space.ownerMyaowId == own || space.members.contains { $0.myaowId == own && ["Admin", "Creador", "Creadora"].contains($0.role) } }
    private var displayed: [GroupMissionModel] {
        GroupTaskFocus.ordered(space.missions, now: focusDate).filter { mission in
            guard search.isEmpty || mission.title.localizedCaseInsensitiveContains(search) || (mission.assigneeDisplayName?.localizedCaseInsensitiveContains(search) ?? false) else { return false }
            return switch selectedFilter {
            case .key: mission.isKey
            case .daily: mission.cadence == "daily"
            case .weekly: mission.cadence == "weekly"
            case .all: true
            case .mine: !mission.isCompleted && mission.assigneeMyaowId == own
            case .pending: GroupTaskFocus.lane(mission) == .pending
            case .today: GroupTaskFocus.dueToday(mission, now: focusDate)
            case .overdue: GroupTaskFocus.overdue(mission, now: focusDate)
            case .unassigned: !mission.isCompleted && (mission.assigneeMyaowId?.isEmpty ?? true)
            case .active: !mission.isCompleted && mission.progress > 0
            case .urgent: !mission.isCompleted && mission.priority != .normal
            case .completed: mission.isCompleted
            }
        }
    }
    private func canEdit(_ task: GroupMissionModel) -> Bool { space.canUpdateTask(task, actor: own) }
    private func canDelete(_ task: GroupMissionModel) -> Bool { space.canDeleteTask(task, actor: own) }

    public var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupProjectPanel(space: $space)
                focusBoard
                nextStep
                DisclosureGroup(isExpanded: $showMembers) { memberProgress } label: {
                    Label("Distribución del equipo", systemImage: "person.2").font(.subheadline.weight(.semibold)).foregroundStyle(MyaowColor.textPrimary)
                }.tint(MyaowColor.orange)
                Button { suggestedTitle = ""; showingIdeas = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "lightbulb.max").font(.title2).foregroundStyle(MyaowColor.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Activen la siguiente idea").font(.subheadline.weight(.semibold))
                            Text("Cuatro preguntas para pasar del chat a la acción.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        }
                        Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(MyaowColor.orange)
                    }.padding(18).background(MyaowColor.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain)
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(MyaowColor.textSecondary)
                    TextField("Buscar tarea o responsable", text: $search).font(.subheadline)
                }.padding(14).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16)).id("task-list")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(MissionsFilter.allCases) { filter in
                            Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedFilter = filter } } label: {
                                Text(filter.rawValue).font(.subheadline.weight(.medium)).padding(.horizontal, 15).frame(minHeight: 44)
                                    .foregroundStyle(selectedFilter == filter ? MyaowColor.textPrimary : MyaowColor.textSecondary)
                                    .background(selectedFilter == filter ? MyaowColor.surfaceElevated : MyaowColor.surface, in: Capsule())
                                    .overlay(Capsule().strokeBorder(selectedFilter == filter ? MyaowColor.orange.opacity(0.6) : .clear))
                            }.buttonStyle(.plain).accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
                        }
                    }
                }
                if let operationError {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No pudimos actualizar las tareas", systemImage: "exclamationmark.circle").font(.subheadline.weight(.semibold))
                        Text(operationError).font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        Button("Volver a intentar") { Task { await reload() } }.font(.subheadline).tint(MyaowColor.orange)
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 18))
                }
                if loading && space.missions.isEmpty { ProgressView("Cargando tareas…").frame(maxWidth: .infinity).padding(24).tint(MyaowColor.orange) }
                else if displayed.isEmpty && operationError == nil {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: selectedFilter == .completed ? "checkmark.seal" : "list.bullet.clipboard").font(.system(size: 32, weight: .light)).foregroundStyle(MyaowColor.orange)
                        Text(search.isEmpty ? "Nada pendiente en esta vista." : "No encontramos esa tarea.").font(.title3.weight(.semibold))
                        Text(search.isEmpty ? "Cambia el filtro para explorar el plan del equipo o prepara el siguiente paso." : "Prueba con otra palabra o con el nombre de la persona responsable.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary).lineSpacing(3)
                        Button("Ver todas las tareas") { search = ""; selectedFilter = .all }.tint(MyaowColor.orange)

                    }.padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    taskSection("Necesitan atención", tasks: displayed.filter { GroupTaskFocus.overdue($0, now: focusDate) })
                    taskSection("Para hoy", tasks: displayed.filter { GroupTaskFocus.dueToday($0, now: focusDate) })
                    taskSection("Próximos pasos", tasks: displayed.filter { !$0.isCompleted && !GroupTaskFocus.dueToday($0, now: focusDate) && !GroupTaskFocus.overdue($0, now: focusDate) })
                    taskSection("Completadas", tasks: displayed.filter(\.isCompleted))
                }
            }.padding(20).padding(.bottom, 12)
        }
        .onChange(of: focusRequest) { _, _ in
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo("task-list", anchor: .top) }
        }
        }
        .background(Color.clear).foregroundStyle(MyaowColor.textPrimary)
        .safeAreaInset(edge: .bottom) {
            Button { suggestedTitle = ""; taskDraft = GroupMissionDraft(title: "") } label: { Label("Nueva tarea", systemImage: "plus") }.buttonStyle(GroupPrimaryStyle()).disabled(!space.canCreateTask(own)).padding(.horizontal, 20).padding(.vertical, 12).background(MyaowColor.charcoal.opacity(0.94))
        }
        .refreshable { await reload() }
        .task { await reload() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in focusDate = date }
        .onChange(of: scenePhase) { _, phase in if phase == .active { focusDate = Date() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in focusDate = Date() }
        .onChange(of: GroupTasksService.shared.revision) { _, _ in Task { await reload() } }
        .sheet(item: $selectedTask) { selected in MissionDetailView(space: $space, taskID: selected.id) }
        .sheet(item: $taskDraft) { draft in CreateMissionSheetView(space: space, prefilledTitle: draft.title, onMissionCreated: { task in space.missions.removeAll { $0.id == task.id }; space.missions.append(task) }) }
        .sheet(isPresented: $showingIdeas, onDismiss: {
            if !suggestedTitle.isEmpty { taskDraft = GroupMissionDraft(title: suggestedTitle) }
        }) {
            GroupIdeaGuideView(canCreate: space.canCreateTask(own)) { suggestedTitle = $0 }
        }
        .confirmationDialog("¿Eliminar esta tarea?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
            if let task = deletion { Button("Eliminar tarea", role: .destructive) { delete(task) } }
        } message: { Text("La tarea dejará de estar disponible para todos los integrantes.") }
    }
    private func applyFocus(_ filter: MissionsFilter) {
        search = ""; focusRequest = UUID()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedFilter = filter }
    }
    private var focusBoard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupEyebrow(title: "El tablero del equipo")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 10)], spacing: 10) {
                ForEach(GroupTaskFocus.Lane.allCases, id: \.self) { lane in
                    let count = space.missions.filter { GroupTaskFocus.lane($0) == lane }.count
                    let filter: MissionsFilter = lane == .pending ? .pending : lane == .active ? .active : .completed
                    Button { applyFocus(filter) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: lane.symbol).foregroundStyle(lane == .completed ? MyaowColor.statusGreen : MyaowColor.orange)
                            Text("\(count)").font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(lane.rawValue).font(.caption.weight(.medium)).foregroundStyle(MyaowColor.textSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                            .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selectedFilter == filter ? MyaowColor.orange : .clear))
                    }.buttonStyle(.plain).accessibilityLabel("\(count) tareas: \(lane.rawValue). Filtrar")
                        .accessibilityAddTraits(selectedFilter == filter ? .isSelected : [])
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { attentionButtons }
                VStack(alignment: .leading) { attentionButtons }
            }.font(.caption.weight(.medium)).buttonStyle(.bordered).tint(MyaowColor.orange)
        }
    }
    @ViewBuilder private var attentionButtons: some View {
        Button { applyFocus(.today) } label: {
            Label("Hoy · \(space.missions.filter { GroupTaskFocus.dueToday($0, now: focusDate) }.count)", systemImage: "sun.max")
        }
        Button { applyFocus(.unassigned) } label: {
            Label("Sin responsable · \(space.missions.filter { !$0.isCompleted && ($0.assigneeMyaowId?.isEmpty ?? true) }.count)", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
    @ViewBuilder private var nextStep: some View {
        if let next = GroupTaskFocus.ordered(space.missions.filter { !$0.isCompleted && $0.assigneeMyaowId == own }, now: focusDate).first {
            Button { selectedTask = next } label: {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "scope").font(.title2).foregroundStyle(MyaowColor.orange)
                    VStack(alignment: .leading, spacing: 7) {
                        GroupEyebrow(title: "Tu siguiente paso")
                        Text(next.title).font(.headline).multilineTextAlignment(.leading)
                        Text("\(next.dueText) · \(next.progress)% de avance").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    }
                    Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption)
                }.padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
        }
    }
    private var memberProgress: some View {
        GroupPanel {
            VStack(alignment: .leading, spacing: 18) {
                GroupEyebrow(title: "Avance por integrante")
                Text("Promedio del avance de sus tareas asignadas. Todas las tareas pesan igual.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                ForEach(space.members) { member in
                    let tasks = space.missions.filter { $0.assigneeMyaowId == member.myaowId }
                    let percent = tasks.isEmpty ? 0 : tasks.reduce(0) { $0 + $1.progress } / tasks.count
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text(member.displayName); Spacer(); Text(tasks.isEmpty ? "Sin tareas" : "\(percent)%").monospacedDigit() }.font(.subheadline)
                        ProgressView(value: Double(percent), total: 100).tint(MyaowColor.orange)
                        Text("\(tasks.filter(\.isCompleted).count) de \(tasks.count) terminadas").font(.caption2).foregroundStyle(MyaowColor.textSecondary)
                    }.accessibilityElement(children: .combine)
                }
                let unassigned = space.missions.filter { $0.assigneeMyaowId == nil }.count
                if unassigned > 0 { Text("\(unassigned) tareas sin responsable; sí cuentan en el avance del proyecto.").font(.caption).foregroundStyle(MyaowColor.textSecondary) }
            }
        }
    }
    private func metric(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(value).font(.title2.weight(.semibold)).monospacedDigit(); Text(label).font(.caption).foregroundStyle(MyaowColor.textSecondary) }
    }
    @ViewBuilder private func taskSection(_ title: String, tasks: [GroupMissionModel]) -> some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack { GroupEyebrow(title: title); Spacer(); Text("\(tasks.count)").font(.caption.monospacedDigit()).foregroundStyle(MyaowColor.textSecondary) }
                ForEach(tasks) { task in
                    taskRow(task).contextMenu {
                        if canEdit(task) { Button(task.isCompleted ? "Marcar pendiente" : "Completar tarea", systemImage: "checkmark.circle") { toggle(task) } }
                        if canDelete(task) { Button("Eliminar tarea", systemImage: "trash", role: .destructive) { deletion = task } }
                    }
                }
            }
        }
    }
    private func taskRow(_ task: GroupMissionModel) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { toggle(task) } label: {
                Group {
                    if updating.contains(task.id) { ProgressView().tint(MyaowColor.orange) }
                    else { Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").font(.system(size: 24, weight: .light)).foregroundStyle(task.isCompleted ? MyaowColor.statusGreen : MyaowColor.textSecondary) }
                }.frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!canEdit(task) || updating.contains(task.id))
                .accessibilityLabel(task.isCompleted ? "Reabrir: \(task.title)" : "Completar: \(task.title)")
            VStack(alignment: .leading, spacing: 10) {
                Button { selectedTask = task } label: {
                    HStack(alignment: .top) {
                        Text(task.title).font(.system(size: 16, weight: .medium)).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("Abrir tarea: \(task.title)")
                if GroupTaskFocus.overdue(task, now: focusDate) {
                    Label("Fecha vencida", systemImage: "calendar.badge.exclamationmark").font(.caption.weight(.semibold)).foregroundStyle(MyaowColor.statusRed)
                }
                Text(task.isCompleted ? "Entrega terminada" : "Ver detalles y añadir evidencia").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                    Text(task.assigneeMyaowId == own ? "Tú" : task.assigneeDisplayName ?? "Sin asignar").lineLimit(1)
                    if task.isKey { Label("Clave", systemImage: "scope").foregroundStyle(MyaowColor.orange) }
                }.font(.caption).foregroundStyle(MyaowColor.textSecondary)
                Label(task.dueText, systemImage: "calendar").font(.caption).foregroundStyle(MyaowColor.textSecondary).fixedSize(horizontal: false, vertical: true)
                if RelayEndpoint(OnlineMessagingService.shared.relayHost)?.supabaseAPIURL != nil {
                    HStack(spacing: 10) {
                        ProgressView(value: Double(task.progress), total: 100).tint(MyaowColor.orange)
                        Menu {
                            ForEach([0, 25, 50, 75, 100], id: \.self) { value in
                                Button(value == 0 ? "Pendiente" : value == 100 ? "Completada" : "Avance: \(value)%") { updateProgress(task, value: value) }
                            }
                        } label: {
                            Text("\(task.progress)%").font(.caption.monospacedDigit().weight(.semibold)).frame(minWidth: 44, minHeight: 44)
                        }.tint(MyaowColor.orange).disabled(!canEdit(task) || updating.contains(task.id))
                            .accessibilityLabel("Actualizar avance de \(task.title): \(task.progress) por ciento")
                    }
                }
                if task.isCompleted, let name = task.completedByDisplayName {
                    Text("Completada por \(name)").font(.caption).foregroundStyle(MyaowColor.statusGreen)
                } else if task.priority != .normal {
                    Label(task.priority.rawValue, systemImage: task.priority == .urgent ? "exclamationmark.circle" : "flag").font(.caption.weight(.medium)).foregroundStyle(task.priority == .urgent ? MyaowColor.statusRed : MyaowColor.orange)
                }
            }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).background(MyaowColor.surface.opacity(task.isCompleted ? 0.65 : 1), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MyaowColor.borderSubtle))
    }
    private func toggle(_ task: GroupMissionModel) {
        if !task.isCompleted { selectedTask = task; return }
        guard canEdit(task), updating.insert(task.id).inserted else { return }
        Task { @MainActor in
            defer { updating.remove(task.id) }
            guard !DesignPreviewData.isEnabled else { operationError = "Esta es una vista de diseño con datos ficticios."; return }
            do {
                let identity = IdentityManager.shared.currentIdentity
                try await GroupTasksService.shared.completeTask(taskId: task.id.uuidString, completedByMyaowId: identity.myaowId, completedByName: identity.displayName, completed: !task.isCompleted)
                if let updated = GroupTasksService.shared.tasks.first(where: { $0.id.lowercased() == task.id.uuidString.lowercased() })?.mission, let index = space.missions.firstIndex(where: { $0.id == task.id }) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { space.missions[index] = updated }
                }
                operationError = nil
            } catch { operationError = error.localizedDescription }
        }
    }
    private func updateProgress(_ task: GroupMissionModel, value: Int) {
        if value == 100 { selectedTask = task; return }
        guard canEdit(task), updating.insert(task.id).inserted else { return }
        Task { @MainActor in
            defer { updating.remove(task.id) }
            guard !DesignPreviewData.isEnabled else { return }
            do {
                if let updated = try await GroupTasksService.shared.updateProgress(taskId: task.id.uuidString, progress: value),
                   let index = space.missions.firstIndex(where: { $0.id == task.id }) { space.missions[index] = updated }
                operationError = nil
            } catch { operationError = error.localizedDescription }
        }
    }
    private func delete(_ task: GroupMissionModel) {
        guard canDelete(task), updating.insert(task.id).inserted else { return }
        Task { @MainActor in
            defer { updating.remove(task.id) }
            guard !DesignPreviewData.isEnabled else { operationError = "Esta es una vista de diseño con datos ficticios."; return }
            do { try await GroupTasksService.shared.deleteTask(taskId: task.id.uuidString); space.missions.removeAll { $0.id == task.id }; operationError = nil }
            catch { operationError = error.localizedDescription }
        }
    }
    private func reload() async {
        guard !DesignPreviewData.isEnabled, !loading else { return }
        loading = true
        defer { loading = false }
        do { space.missions = try await GroupTasksService.shared.fetchTasks(groupId: space.id.uuidString).compactMap(\.mission); if let policy = GroupTasksService.shared.policies[space.id.uuidString.lowercased()] { space.taskPolicy = policy }; operationError = nil }
        catch { operationError = error.localizedDescription }
    }
}

private struct GroupMissionDraft: Identifiable {
    let id = UUID()
    let title: String
}
