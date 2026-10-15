import SwiftUI

public struct CreateMissionSheetView: View {
    @Environment(\.dismiss) private var dismiss
    public let space: GroupSpaceModel
    public var onMissionCreated: (GroupMissionModel) -> Void
    public var onApplyTemplate: ([GroupMissionModel]) -> Void
    @State private var saving = false
    @State private var saveError: String?
    @State private var requestId = UUID().uuidString
    @State private var missionTitle = ""
    @State private var selectedAssignee = "self"
    @State private var customDate = Date().addingTimeInterval(3600)
    @State private var usesDate = true
    @State private var isKey = false
    @State private var cadence = "once"
    @State private var selectedDueLabel = "Hoy"
    @State private var selectedPriority: MissionPriority = .normal
    public init(space: GroupSpaceModel, prefilledTitle: String = "", onMissionCreated: @escaping (GroupMissionModel) -> Void, onApplyTemplate: @escaping ([GroupMissionModel]) -> Void = { _ in }) {
        self.space = space; self.onMissionCreated = onMissionCreated; self.onApplyTemplate = onApplyTemplate
        _missionTitle = State(initialValue: prefilledTitle)
    }
    private var assigneeName: String {
        selectedAssignee == "self" ? "Tú" : space.members.first { $0.myaowId == selectedAssignee }?.displayName ?? "Sin asignar"
    }
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            GroupEyebrow(title: space.title)
                            Text("El siguiente paso.").font(.system(size: 29, weight: .semibold)).tracking(-0.7)
                            Text("Claro, concreto y con responsable.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "checklist").font(.system(size: 28, weight: .light)).foregroundStyle(MyaowColor.orange).frame(width: 54, height: 54).background(MyaowColor.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                    }.padding(.top, 8)
                    VStack(alignment: .leading, spacing: 12) {
                        GroupEyebrow(title: "Qué hay que hacer")
                        TextField("Por ejemplo: preparar la propuesta", text: $missionTitle, axis: .vertical).lineLimit(2...4).font(.title3.weight(.medium)).padding(18)
                            .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(MyaowColor.borderSubtle))
                        Text("\(missionTitle.count)/240").font(.caption.monospacedDigit()).foregroundStyle(missionTitle.count > 240 ? MyaowColor.statusRed : MyaowColor.textSecondary).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    if missionTitle.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(["Preparar propuesta", "Revisar entrega", "Reunir referencias"], id: \.self) { title in
                                    Button(title) { missionTitle = title }.font(.caption).padding(12).background(MyaowColor.surface, in: Capsule()).tint(MyaowColor.orange)
                                }
                            }
                        }
                    }
                    GroupPanel {
                        HStack(spacing: 14) {
                            Image(systemName: "person.crop.circle").font(.title2).foregroundStyle(MyaowColor.orange)
                            VStack(alignment: .leading, spacing: 5) { GroupEyebrow(title: "Responsable"); Text(assigneeName).font(.subheadline.weight(.semibold)) }
                            Spacer()
                            Menu {
                                Picker("Responsable", selection: $selectedAssignee) {
                                    Text("Tú").tag("self")
                                    ForEach(space.members.filter { $0.myaowId != IdentityManager.shared.currentIdentity.myaowId }) { member in Text(member.displayName).tag(member.myaowId) }
                                    Text("Sin asignar").tag("Sin asignar")
                                }
                            } label: { Label("Cambiar", systemImage: "chevron.up.chevron.down").font(.caption.weight(.medium)).frame(minHeight: 44) }.tint(MyaowColor.orange)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        GroupEyebrow(title: "Para cuándo")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(["Hoy", "Mañana", "Esta semana", "Pronto"], id: \.self) { due in
                                Button { selectedDueLabel = due; usesDate = false } label: {
                                    HStack { Image(systemName: "calendar"); Text(due); Spacer(); if !usesDate && selectedDueLabel == due { Image(systemName: "checkmark") } }.font(.subheadline.weight(.medium)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundStyle(!usesDate && selectedDueLabel == due ? MyaowColor.orange : MyaowColor.textSecondary)
                                        .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(!usesDate && selectedDueLabel == due ? MyaowColor.orange.opacity(0.5) : MyaowColor.borderSubtle))
                                }.buttonStyle(.plain).accessibilityAddTraits(!usesDate && selectedDueLabel == due ? .isSelected : [])
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Fecha y hora exactas", isOn: $usesDate).tint(MyaowColor.orange)
                        if usesDate { DatePicker("Entrega", selection: $customDate, in: Date()..., displayedComponents: [.date, .hourAndMinute]).tint(MyaowColor.orange) }
                        Text("Zona horaria: \(TimeZone.current.identifier). El grupo verá el mismo vencimiento.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        Toggle("Tarea clave para el objetivo", isOn: $isKey).tint(MyaowColor.orange)
                        Picker("Ritmo de trabajo", selection: $cadence) {
                            Text("Puntual").tag("once"); Text("Diario").tag("daily"); Text("Semanal").tag("weekly")
                        }.tint(MyaowColor.orange)
                        if cadence != "once" { Text("Identifica la rutina del equipo. Cada entrega se completa por separado; no se crean copias automáticamente.").font(.caption).foregroundStyle(MyaowColor.textSecondary) }
                        GroupEyebrow(title: "Prioridad")
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { ForEach(MissionPriority.allCases) { priority in priorityButton(priority) } }
                            VStack(spacing: 8) { ForEach(MissionPriority.allCases) { priority in priorityButton(priority) } }
                        }
                    }
                    if let saveError { Label(saveError, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(MyaowColor.statusRed) }
                }.padding(24).disabled(saving)
            }.background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
                .safeAreaInset(edge: .bottom) {
                    Button(action: createMission) { HStack { if saving { ProgressView().tint(.black) }; Text(saving ? "Guardando…" : "Crear tarea") } }.buttonStyle(GroupPrimaryStyle())
                        .disabled(!space.canCreateTask(IdentityManager.shared.currentIdentity.myaowId) || saving || missionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || missionTitle.count > 240)
                        .opacity(missionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || missionTitle.count > 240 ? 0.5 : 1)
                        .padding(20).background(MyaowColor.charcoal)
                }
                .navigationTitle("Nueva tarea").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving).tint(MyaowColor.textSecondary) } }
        }.preferredColorScheme(.dark).interactiveDismissDisabled(saving).presentationDragIndicator(.visible)
    }
    private func priorityButton(_ priority: MissionPriority) -> some View {
        Button { selectedPriority = priority } label: {
            Label(priority.rawValue, systemImage: priority == .urgent ? "exclamationmark.circle" : priority == .high ? "flag" : "minus.circle")
                .font(.caption.weight(.medium)).padding(.horizontal, 12).frame(minHeight: 46).frame(maxWidth: .infinity)
                .foregroundStyle(selectedPriority == priority ? MyaowColor.textPrimary : MyaowColor.textSecondary)
                .background(selectedPriority == priority ? MyaowColor.surfaceElevated : MyaowColor.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selectedPriority == priority ? MyaowColor.orange.opacity(0.6) : MyaowColor.borderSubtle))
        }.buttonStyle(.plain).accessibilityAddTraits(selectedPriority == priority ? .isSelected : [])
    }
    private func createMission() {
        guard space.canCreateTask(IdentityManager.shared.currentIdentity.myaowId) else { saveError = "Solo los administradores pueden crear tareas en este grupo."; return }
        let cleaned = missionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 240 else { return }
        
        guard !saving else { return }
        saving = true
        Task {
            defer { saving = false }
            guard !DesignPreviewData.isEnabled else { saveError = "Esta es una vista de diseño con datos ficticios."; return }
            do {
                let own = IdentityManager.shared.currentIdentity
                let assignee: String? = selectedAssignee == "self" ? own.myaowId : selectedAssignee == "Sin asignar" ? nil : selectedAssignee
                let item = try await GroupTasksService.shared.createTask(groupId: space.id.uuidString,
                    title: cleaned, assigneeMyaowId: assignee, assigneeName: nil, dueLabel: usesDate ? "Pronto" : selectedDueLabel,
                    priority: selectedPriority.rawValue, createdByMyaowId: own.myaowId, requestId: requestId, dueAt: usesDate ? customDate : nil, dueTimezone: TimeZone.current.identifier, isKey: isKey, cadence: cadence)
                guard let mission = item.mission else { throw URLError(.cannotParseResponse) }
                onMissionCreated(mission)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch { saveError = error.localizedDescription }
        }
    }
}
