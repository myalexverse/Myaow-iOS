import SwiftUI
import Combine

struct GroupProjectPanel: View {
    @Binding var space: GroupSpaceModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true
    @State private var snapshot: GroupProjectSnapshot?
    @State private var error: String?
    @State private var actionError: String?
    @State private var accepting: GroupProjectProposal?
    @State private var openedTask: GroupMissionModel?
    @State private var workingIdea: UUID?
    @State private var showApproved = false
    @State private var feedback: String?
    @State private var busy = false
    @State private var editing = false
    @State private var proposing = false
    @State private var proposalTitle = ""
    @State private var proposalID = UUID()
    @State private var expandedCalendar = false
    @State private var expandedIdeas = false
    @State private var expandedAchievements = false
    @State private var now = Date()
    private var own: String { IdentityManager.shared.currentIdentity.myaowId }
    private var administrator: Bool { space.isAdministrator(own) }
    private var health: ProjectHealth { ProjectHealth.evaluate(plan: snapshot?.project, tasks: space.missions, now: now) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if DesignPreviewData.isEnabled {
                Label("Vista interactiva · datos de ejemplo", systemImage: "testtube.2").font(.caption).foregroundStyle(MyaowColor.textSecondary)
            }
            GroupPanel(accented: true) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            GroupEyebrow(title: "Pulso del proyecto")
                            Text(snapshot == nil ? "El plan del equipo" : health.rawValue).font(.title2.weight(.semibold)).tracking(-0.5)
                        }
                        Spacer(minLength: 0)
                        ProjectHealthCat(health: snapshot == nil ? .unplanned : health)
                    }
                    if let snapshot {
                        Text(health.reason(plan: snapshot.project, tasks: space.missions, now: now)).font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                        if let plan = snapshot.project {
                            HStack(spacing: 8) {
                                GroupBadge(title: plan.status == "paused" ? "En pausa" : plan.status == "completed" ? "Cerrado" : "Activo", symbol: plan.status == "paused" ? "pause.circle" : plan.status == "completed" ? "checkmark.seal" : "circle.dotted", accent: true)
                                if now < plan.startsAt { GroupBadge(title: "Inicio próximo", symbol: "calendar") }
                            }
                            Text(plan.objective).font(.headline).fixedSize(horizontal: false, vertical: true)
                            DisclosureGroup("Calendario y revisión", isExpanded: $expandedCalendar) {
                            VStack(alignment: .leading, spacing: 10) {
                                dateRow("Inicio", plan.startsAt, zone: plan.timezone, icon: "flag")
                                dateRow("Cierre", plan.endsAt, zone: plan.timezone, icon: "flag.checkered")
                                if let review = plan.reviewAt { dateRow("Revisión de salud", review, zone: plan.timezone, icon: "heart.text.clipboard") }
                            }
                            }.tint(MyaowColor.orange).font(.subheadline.weight(.medium))
                            let keys = space.missions.filter(\.isKey)
                            if !keys.isEmpty {
                                let percent = keys.reduce(0) { $0 + $1.progress } / keys.count
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack { Label("Tareas clave", systemImage: "scope"); Spacer(); Text("\(percent)%").monospacedDigit() }.font(.subheadline.weight(.medium))
                                    ProgressView(value: Double(percent), total: 100).tint(MyaowColor.orange)
                                    Text("\(keys.filter(\.isCompleted).count) de \(keys.count) terminadas · todas pesan igual").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                                }
                            }
                        }
                        if administrator {
                            Button { editing = true } label: { Label(snapshot.project == nil ? "Definir proyecto" : "Editar plan y revisión", systemImage: "slider.horizontal.3") }.tint(MyaowColor.orange).frame(minHeight: 44)
                        }
                    } else if busy { ProgressView("Cargando el plan…").tint(MyaowColor.orange) }
                    HStack {
                        Text("\(space.completedMissionsCount) de \(space.totalMissionsCount) tareas listas").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        Spacer()
                        Text("\(space.progressPercentageInt)%").font(.title2.weight(.semibold)).monospacedDigit()
                    }
                    ProgressView(value: space.progressPercentage).tint(MyaowColor.orange).animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: space.progressPercentage)
                    if let error {
                        Text(error).font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        Button("Volver a cargar") { Task { await load() } }.tint(MyaowColor.orange)
                    }
                }
            }
            if let snapshot {
                GroupPanel {
                    DisclosureGroup(isExpanded: $expandedIdeas) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Todos pueden sugerir y votar. Los administradores convierten las propuestas elegidas en tareas.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                            Picker("Estado de las propuestas", selection: $showApproved) {
                                Text("Por decidir · \(snapshot.proposals.filter { !$0.accepted }.count)").tag(false)
                                Text("En el plan · \(snapshot.proposals.filter(\.accepted).count)").tag(true)
                            }.pickerStyle(.segmented)
                            ForEach(snapshot.proposals.filter { $0.accepted == showApproved }) { idea in proposal(idea) }
                            if !snapshot.proposals.isEmpty && !snapshot.proposals.contains(where: { $0.accepted == showApproved }) {
                                Text(showApproved ? "Las ideas aprobadas aparecerán aquí, vinculadas a su tarea." : "Todo está decidido. Abran una nueva posibilidad.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                            }
                            if let feedback { Label(feedback, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(MyaowColor.statusGreen).accessibilityIdentifier("project-feedback") }
                            if snapshot.proposals.isEmpty { Text("La próxima buena idea puede ser tuya.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary) }
                            Button { proposalTitle = ""; proposalID = UUID(); proposing = true } label: { Label("Sugerir una tarea", systemImage: "plus.bubble") }.tint(MyaowColor.orange).frame(minHeight: 44)
                        }.padding(.top, 16)
                    } label: {
                        HStack { Image(systemName: "lightbulb.max").foregroundStyle(MyaowColor.orange); Text("Ideas del equipo").font(.headline); Spacer(); Text("\(snapshot.proposals.count)").font(.caption.monospacedDigit()) }
                    }.tint(MyaowColor.orange)
                }
                GroupPanel {
                    DisclosureGroup(isExpanded: $expandedAchievements) {
                        VStack(alignment: .leading, spacing: 12) {
                            let early = ProjectHealth.earlyDeliveries(space.missions)
                            Label("\(space.completedMissionsCount) entregas completadas", systemImage: "checkmark.seal")
                            Label("\(early.count) antes de su fecha límite", systemImage: "bolt.heart")
                            ForEach(space.members.filter { member in early.contains { $0.completedByMyaowId == member.myaowId } }) { member in
                                HStack { Text(member.displayName); Spacer(); Text("\(early.filter { $0.completedByMyaowId == member.myaowId }.count) a tiempo de sobra").foregroundStyle(MyaowColor.orange) }.font(.caption)
                            }
                            Text("Reconocemos entregas con fecha exacta. Completar una tarea no equivale a aprobar su evidencia.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        }.padding(.top, 16).font(.subheadline)
                    } label: { Label("Logros compartidos", systemImage: "sparkles").font(.headline) }.tint(MyaowColor.orange)
                }
            }
        }
        .onAppear { visible = true }.onDisappear { visible = false }
        .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
        .task(id: space.id) { await load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active && !editing && !proposing && openedTask == nil { Task { await load() } } }
        .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { date in now = date; if visible && scenePhase == .active && !editing && !proposing && openedTask == nil { Task { await load() } } }
        .alert("No se confirmó el cambio", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) { Button("Entendido") { actionError = nil } } message: { Text(actionError ?? "") }
        .confirmationDialog("¿Llevar esta idea al plan?", isPresented: Binding(get: { accepting != nil }, set: { if !$0 { accepting = nil } }), titleVisibility: .visible) {
            if let idea = accepting { Button("Aprobar y crear tarea") { perform("accept", body: ["id": idea.id.uuidString.lowercased()]) { accepting = nil; showApproved = true; GroupTasksService.shared.revision += 1 } } }
            Button("Cancelar", role: .cancel) { accepting = nil }
        } message: { Text("Se creará una tarea para \"\(accepting?.title ?? "")\". Después podrás asignar responsable y fecha.") }
        .sheet(item: $openedTask) { task in MissionDetailView(space: $space, taskID: task.id) }
        .sheet(isPresented: $editing) {
            GroupProjectEditor(plan: snapshot?.project ?? GroupProjectPlan(), hasPending: space.pendingMissionsCount > 0) { plan in
                if DesignPreviewData.isEnabled {
                    var updated = plan; updated.version += 1
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { snapshot?.project = updated }
                } else { snapshot = try await GroupProjectService.save(group: space.id, plan: plan) }
                error = nil
            }
        }
        .sheet(isPresented: $proposing) {
            NavigationStack {
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    GroupEyebrow(title: "Tu idea cuenta")
                    Text("¿Qué propones hacer?").font(.title2.weight(.semibold))
                    TextField("Una acción clara para el equipo", text: $proposalTitle, axis: .vertical).lineLimit(3...6).padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 18))
                    Text("\(proposalTitle.count)/240 · Aparecerá con tu nombre para que el grupo vote.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    if let error { Text(error).font(.caption).foregroundStyle(MyaowColor.statusRed) }
                    Button(busy ? "Compartiendo…" : "Compartir propuesta") {
                        perform("propose", body: ["id": proposalID.uuidString.lowercased(), "title": proposalTitle.trimmingCharacters(in: .whitespacesAndNewlines)]) { proposing = false; expandedIdeas = true }
                    }.buttonStyle(GroupPrimaryStyle()).disabled(busy || proposalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || proposalTitle.count > 240)
                }.padding(24)
                }.scrollDismissesKeyboard(.interactively).background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
                    .navigationTitle("Proponer").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { proposing = false }.disabled(busy) } }
            }.preferredColorScheme(.dark).interactiveDismissDisabled(busy)
        }
    }
    private func dateRow(_ label: String, _ date: Date, zone: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(MyaowColor.orange).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) { Text(label).font(.caption).foregroundStyle(MyaowColor.textSecondary); Text(ProjectDate.text(date, timezone: zone)).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private func proposal(_ idea: GroupProjectProposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(idea.title).font(.subheadline.weight(.medium))
            HStack {
                Text(idea.author_name)
                Spacer()
                if workingIdea == idea.id { ProgressView().controlSize(.small).tint(MyaowColor.orange) }
            }.font(.caption).foregroundStyle(MyaowColor.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack { proposalActions(idea) }
                VStack(alignment: .leading) { proposalActions(idea) }
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
    @ViewBuilder private func proposalActions(_ idea: GroupProjectProposal) -> some View {
        if idea.accepted {
            VStack(alignment: .leading, spacing: 8) {
                Label(idea.task_id == nil ? "Aprobada · tarea eliminada" : "Convertida en tarea", systemImage: "checkmark.circle").font(.caption).foregroundStyle(MyaowColor.statusGreen)
                Text("\(idea.votes) apoyos del grupo").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                if let id = idea.task_id {
                    Button("Ver tarea", systemImage: "arrow.up.right") { openTask(id) }.tint(MyaowColor.orange).frame(minHeight: 44).disabled(busy)
                }
            }
        }
        else {
            Button { perform("vote", body: ["id": idea.id.uuidString.lowercased(), "voted": !idea.voted]) } label: { Label("\(idea.votes) · \(idea.voted ? "Retirar voto" : "Apoyar")", systemImage: idea.voted ? "hand.thumbsup.fill" : "hand.thumbsup") }.buttonStyle(.bordered).tint(MyaowColor.orange).disabled(busy)
                .accessibilityLabel("\(idea.voted ? "Retirar tu voto de" : "Apoyar") \(idea.title). \(idea.votes) apoyos")
                .contentTransition(.numericText()).animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: idea.votes)
            if administrator { Button("Llevar al plan") { accepting = idea }.buttonStyle(.bordered).tint(MyaowColor.orange).disabled(busy) }
        }
    }
    private func openTask(_ id: UUID) {
        if let task = space.missions.first(where: { $0.id == id }) { openedTask = task; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                space.missions = try await GroupTasksService.shared.fetchTasks(groupId: space.id.uuidString).compactMap(\.mission)
                guard let task = space.missions.first(where: { $0.id == id }) else { throw RelayRequestError(message: "Esta tarea ya no está disponible. Actualiza las propuestas.") }
                openedTask = task
            } catch { actionError = error.localizedDescription }
        }
    }
    private func perform(_ operation: String, body: [String: Any], completion: @escaping () -> Void = {}) {
        guard !busy else { return }; busy = true; error = nil; feedback = nil
        workingIdea = (body["id"] as? String).flatMap(UUID.init(uuidString:))
        Task {
            defer { busy = false; workingIdea = nil }
            do {
                if DesignPreviewData.isEnabled {
                    applyPreview(operation, body: body)
                } else {
                    let updated = try await GroupProjectService.request(group: space.id, operation: operation, method: "POST", body: body)
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { snapshot = updated }
                }
                feedback = operation == "vote" ? ((body["voted"] as? Bool == true) ? "Tu apoyo quedó registrado." : "Retiraste tu voto.") : operation == "accept" ? "La idea ya forma parte del plan." : "Tu propuesta ya está en el tablero."
                if !DesignPreviewData.isEnabled { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                completion()
            } catch { if proposing { self.error = error.localizedDescription } else { actionError = error.localizedDescription } }
        }
    }
    // Ephemeral UI rehearsal, gated by the isolated DEBUG design bundle; never sends network requests.
    private func applyPreview(_ operation: String, body: [String: Any]) {
        guard DesignPreviewData.isEnabled, let id = (body["id"] as? String).flatMap(UUID.init(uuidString:)) else { return }
        if operation == "propose" {
            guard !(snapshot?.proposals.contains { $0.id == id } ?? false) else { return }
            snapshot?.proposals.insert(GroupProjectProposal(id: id, title: body["title"] as? String ?? "", author: own, author_name: "Tú", accepted: false, votes: 0, voted: false), at: 0)
        } else if let index = snapshot?.proposals.firstIndex(where: { $0.id == id }) {
            guard snapshot?.proposals[index].accepted == false else { return }
            if operation == "vote", let voted = body["voted"] as? Bool, snapshot?.proposals[index].voted != voted {
                snapshot?.proposals[index].votes += voted ? 1 : -1
                snapshot?.proposals[index].voted = voted
            } else if operation == "accept", administrator, let idea = snapshot?.proposals[index] {
                let task = GroupMissionModel(groupId: space.id, title: idea.title, dueLabel: "Pronto", creatorMyaowId: own)
                space.missions.append(task)
                snapshot?.proposals[index].accepted = true; snapshot?.proposals[index].task_id = task.id
            }
        }
    }
    private func load() async {
        guard !busy else { return }; now = Date()
        if DesignPreviewData.isEnabled {
            guard snapshot == nil else { return }
            snapshot = GroupProjectSnapshot(project: GroupProjectPlan(objective: "Preparar una experiencia Myaow que el equipo quiera usar todos los días.", startsAt: now.addingTimeInterval(-3 * 86400), endsAt: now.addingTimeInterval(11 * 86400), reviewAt: now.addingTimeInterval(86400)), proposals: [GroupProjectProposal(id: UUID(), title: "Probar la experiencia de bienvenida con tres personas", author: "preview", author_name: "Sofía", accepted: false, votes: 2, voted: false)])
            return
        }
        busy = true; defer { busy = false }
        do {
            let updated = try await GroupProjectService.request(group: space.id)
            if !DesignPreviewData.isEnabled {
                let tasks = try await GroupTasksService.shared.fetchTasks(groupId: space.id.uuidString)
                space.missions = tasks.compactMap(\.mission)
                if let policy = GroupTasksService.shared.policies[space.id.uuidString.lowercased()] { space.taskPolicy = policy }
            }
            snapshot = updated; error = nil
        }
        catch { if (error as? SupabaseHTTPError)?.status == 403 { snapshot = nil }; self.error = "No pudimos cargar el proyecto compartido. Actualiza para consultar los datos confirmados." }
    }
}

struct GroupProjectEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var plan: GroupProjectPlan
    var hasPending: Bool
    var save: (GroupProjectPlan) async throws -> Void
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Objetivo del equipo") { TextField("Qué quieren conseguir", text: $plan.objective, axis: .vertical).lineLimit(3...7); Text("\(plan.objective.count)/1200").font(.caption) }
                Section("Duración y revisión") {
                    DatePicker("Inicio", selection: $plan.startsAt, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("Cierre", selection: $plan.endsAt, displayedComponents: [.date, .hourAndMinute])
                    Toggle("Agendar revisión de salud", isOn: Binding(get: { plan.reviewAt != nil }, set: { plan.reviewAt = $0 ? min(max(Date(), plan.startsAt), plan.endsAt) : nil }))
                    if plan.reviewAt != nil { DatePicker("Revisión", selection: Binding(get: { plan.reviewAt ?? plan.startsAt }, set: { plan.reviewAt = $0 }), displayedComponents: [.date, .hourAndMinute]) }
                    Text("Zona del plan: \(plan.timezone). Las fechas se muestran en esta zona para todo el equipo.").font(.caption)
                    if !plan.isValid { Text("Escribe un objetivo. El cierre debe ir después del inicio y la revisión dentro de ese periodo.").font(.caption).foregroundStyle(MyaowColor.orange) }
                }.environment(\.timeZone, TimeZone(identifier: plan.timezone) ?? .current)
                Section("Estado del proyecto") {
                    Picker("Estado", selection: $plan.status) {
                        Text("En marcha").tag("active"); Text("En pausa").tag("paused")
                        if !hasPending { Text("Objetivo cumplido").tag("completed") }
                    }.pickerStyle(.navigationLink)
                    if hasPending { Text("Para cerrar el proyecto, primero termina las tareas pendientes.").font(.caption) }
                }
                if let error { Section { Text(error).foregroundStyle(MyaowColor.statusRed) } }
                Button(busy ? "Guardando…" : "Guardar para el equipo") {
                    busy = true
                    Task { defer { busy = false }; do { try await save(plan); dismiss() } catch { self.error = error.localizedDescription } }
                }.disabled(busy || !plan.isValid || (hasPending && plan.status == "completed"))
            }.disabled(busy).scrollContentBackground(.hidden).background(MyaowColor.charcoal).tint(MyaowColor.orange)
                .navigationTitle("Plan del proyecto").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(busy) } }
        }.preferredColorScheme(.dark).interactiveDismissDisabled(busy)
    }
}

struct ProjectHealthCat: View {
    let health: ProjectHealth
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private var critical: Bool { health == .critical }
    private var state: MyaowCatState {
        switch health { case .critical: .exhausted; case .attention: .skeptical; case .completed: .party; case .paused: .sleeping; case .unplanned: .thinking; case .active: .cool }
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !critical || reduceMotion || lowPower || !visible || scenePhase != .active)) { context in
            let phase = reduceMotion || lowPower ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                if critical {
                    ForEach(0..<5) { index in
                        Image(systemName: "flame.fill").font(.system(size: 45 - Double(index % 2) * 10))
                            .foregroundStyle(LinearGradient(colors: [MyaowColor.orange, .yellow.opacity(0.6), .clear], startPoint: .bottom, endPoint: .top))
                            .offset(x: CGFloat(index - 2) * 13, y: -8 - 5 * sin(phase * 3 + Double(index)))
                            .opacity(0.45)
                    }
                }
                MyaowCatView(state: state, style: .orangeOnTransparent, size: 76, isInteractive: false, showsCrossEyes: critical)
            }.frame(width: 90, height: 96)
        }.onAppear { visible = true }.onDisappear { visible = false }
            .onScrollVisibilityChange(threshold: 0.1) { visible = $0 }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
            .accessibilityElement(children: .ignore).accessibilityLabel("Estado del proyecto: \(health.rawValue)")
    }
}
