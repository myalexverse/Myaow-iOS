import SwiftUI

struct MissionPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    let task: GroupMissionModel
    let members: [SpaceMemberModel]
    @State private var assignee: String
    var saved: (GroupMissionModel) -> Void
    @State private var date: Date
    @State private var hasDate: Bool
    @State private var isKey: Bool
    @State private var cadence: String
    @State private var busy = false
    @State private var error: String?
    init(task: GroupMissionModel, members: [SpaceMemberModel], saved: @escaping (GroupMissionModel) -> Void) {
        self.task = task; self.members = members; self.saved = saved
        _assignee = State(initialValue: task.assigneeMyaowId ?? "")
        _date = State(initialValue: task.dueAt ?? Date()); _hasDate = State(initialValue: task.dueAt != nil)
        _isKey = State(initialValue: task.isKey); _cadence = State(initialValue: task.cadence)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(task.title).font(.headline) }
                Section("Responsable") {
                    Picker("Persona a cargo", selection: $assignee) {
                        Text("Sin asignar").tag("")
                        ForEach(members) { member in Text(member.displayName).tag(member.myaowId) }
                    }.pickerStyle(.navigationLink)
                }
                Section("Entrega") {
                    Toggle("Fecha y hora exactas", isOn: $hasDate)
                    if hasDate { DatePicker("Vencimiento", selection: $date, displayedComponents: [.date, .hourAndMinute]) }
                    Text("Zona horaria: \(TimeZone.current.identifier). Cambiar la zona del teléfono no cambia el instante de entrega.").font(.caption)
                }
                Section("Dentro del proyecto") {
                    Toggle("Tarea clave", isOn: $isKey)
                    Picker("Ritmo", selection: $cadence) { Text("Puntual").tag("once"); Text("Diario").tag("daily"); Text("Semanal").tag("weekly") }.pickerStyle(.navigationLink)
                    Text("El ritmo organiza la rutina. Las entregas no se duplican automáticamente.").font(.caption)
                }
                if let error { Text(error).foregroundStyle(MyaowColor.statusRed) }
                Button(busy ? "Guardando…" : "Guardar cambios") {
                    busy = true
                    Task {
                        defer { busy = false }
                        if DesignPreviewData.isEnabled {
                            var updated = task
                            updated.dueAt = hasDate ? date : nil; updated.dueTimezone = TimeZone.current.identifier
                            updated.isKey = isKey; updated.cadence = cadence
                            updated.assigneeMyaowId = assignee.isEmpty ? nil : assignee
                            updated.assigneeDisplayName = members.first { $0.myaowId == assignee }?.displayName
                            saved(updated); dismiss(); return
                        }
                        do {
                            guard let updated = try await GroupTasksService.shared.updatePlan(taskId: task.id.uuidString, dueAt: hasDate ? date : nil, timezone: TimeZone.current.identifier, isKey: isKey, cadence: cadence, assignee: assignee.isEmpty ? nil : assignee) else { throw URLError(.cannotParseResponse) }
                            saved(updated); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }.disabled(busy)
            }.disabled(busy).scrollContentBackground(.hidden).background(MyaowColor.charcoal).tint(MyaowColor.orange)
                .navigationTitle("Planificar tarea").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
        }.preferredColorScheme(.dark).interactiveDismissDisabled(busy)
    }
}
