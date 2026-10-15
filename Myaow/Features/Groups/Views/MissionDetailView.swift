import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct MissionDetailView: View {
    @Binding var space: GroupSpaceModel
    let taskID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var messages: [MessageModel]
    @State private var editingPlan = false
    @State private var comment = ""
    @State private var error: String?
    @State private var updating = false
    @State private var importing = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var selection: [ChatMediaSelection] = []
    @State private var showingPreview = false
    @State private var showingFiles = false
    @State private var fileData: Data?
    @State private var fileName = ""
    @State private var selectedMedia: MessageModel?
    @State private var celebration = false
    @State private var proposedProgress = 100.0
    init(space: Binding<GroupSpaceModel>, taskID: UUID) {
        _space = space; self.taskID = taskID
        _messages = Query(ChatHistoryQuery.descriptor(conversationID: space.wrappedValue.id.uuidString))
    }
    private var task: GroupMissionModel? { space.missions.first { $0.id == taskID } }
    private var own: String { IdentityManager.shared.currentIdentity.myaowId }
    private var evidence: [MessageModel] { messages.filter { $0.replyToId == TaskEvidenceStore.reference(taskID) } }
    private var canEdit: Bool {
        guard let task else { return false }
        return space.canUpdateTask(task, actor: own)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let task {
                        header(task)
                        if canEdit {
                            Button { editingPlan = true } label: { Label("Responsable, fecha y planificación", systemImage: "calendar.badge.clock") }.tint(MyaowColor.orange).frame(minHeight: 44)
                        }
                        progress(task)
                            .sheet(isPresented: $editingPlan) {
                                MissionPlanEditor(task: task, members: space.members) { updated in
                                    if let index = space.missions.firstIndex(where: { $0.id == updated.id }) { space.missions[index] = updated }
                                }
                            }
                        HStack {
                            GroupEyebrow(title: "Bitácora y evidencia")
                            Spacer()
                            Text("\(evidence.count)").font(.caption.monospacedDigit()).foregroundStyle(MyaowColor.textSecondary)
                        }
                        if evidence.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: "photo.on.rectangle.angled").font(.title).foregroundStyle(MyaowColor.orange)
                                Text("Haz visible lo que avanzaste.").font(.headline)
                                Text("Comparte un boceto, una entrega o ese pequeño logro. Los comentarios y archivos quedan ligados a esta tarea y se comparten con el grupo.")
                                    .font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
                        } else {
                            ForEach(evidence) { item in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(item.isOutgoing ? "Tú" : item.senderName).font(.caption.weight(.semibold))
                                        Spacer()
                                        Text(item.timestamp.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(MyaowColor.textSecondary)
                                    }.padding(.horizontal, 16)
                                    MessageBubbleView(message: item, onMediaTapped: { selectedMedia = item })
                                    if item.isOutgoing && [.queued, .sending].contains(item.deliveryStatus) {
                                        Label("Guardado aquí · pendiente de envío", systemImage: "clock").font(.caption).foregroundStyle(MyaowColor.orange).padding(.horizontal, 16)
                                    }
                                }
                            }
                        }
                        composer
                    } else { ContentUnavailableView("Tarea no disponible", systemImage: "checklist") }
                    if let error { Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(MyaowColor.statusRed) }
                }.padding(20)
            }.background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
                .navigationTitle("Detalle de tarea").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() }.tint(MyaowColor.orange) } }
                .refreshable { await refresh() }
        }.preferredColorScheme(.dark)
            .onAppear { proposedProgress = Double(task?.progress ?? 0) }
            .sheet(isPresented: $showingPreview, onDismiss: { selection = []; photos = [] }) {
                MediaComposerSheetView(items: selection) { payloads in
                    enqueue(payloads.map { .init(text: $0.caption.isEmpty ? ($0.isVideo ? "Video de avance" : "Foto de avance") : $0.caption,
                        type: $0.isVideo ? "video" : "image", data: $0.data) })
                }
            }
            .fullScreenCover(item: $selectedMedia) { message in
                if message.messageTypeRaw == "rawFile" { DocumentAttachmentView(message: message) }
                else { FullScreenMediaViewer(message: message) }
            }
            .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.item]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size > 0 && size <= 10 * 1024 * 1024 else { throw ChatMediaSelectionError.tooLarge }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 10 * 1024 * 1024 else { throw ChatMediaSelectionError.tooLarge }
                    fileData = data; fileName = String(url.lastPathComponent.prefix(180)); error = nil
                } catch { self.error = error.localizedDescription }
            }
            .onChange(of: photos) { _, value in
                guard !value.isEmpty else { return }
                importing = true
                Task {
                    defer { importing = false }
                    do {
                        var items: [ChatMediaSelection] = []
                        for item in value {
                            guard let media = try await item.loadTransferable(type: ImportedChatMedia.self) else { throw ChatMediaSelectionError.unreadable }
                            items.append(.init(data: media.data, isVideo: media.isVideo))
                            guard items.reduce(0, { $0 + $1.data.count }) <= 50 * 1024 * 1024 else { throw ChatMediaSelectionError.tooLarge }
                        }
                        selection = items; showingPreview = true; error = nil
                    } catch { self.error = error.localizedDescription; photos = [] }
                }
            }
    }
    private func header(_ task: GroupMissionModel) -> some View {
        GroupPanel(accented: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 10) {
                        GroupEyebrow(title: task.isCompleted ? "Misión cumplida" : space.title)
                        Text(task.title).font(.system(size: 26, weight: .semibold)).tracking(-0.5)
                    }
                    Spacer(minLength: 4)
                    MyaowCatView(state: task.isCompleted || celebration ? .party : task.progress > 0 ? .thinking : .curious,
                        style: .darkOnOrange, size: 58, isInteractive: false)
                }
                Label(task.assigneeMyaowId == own ? "Tú llevas esta misión" : task.assigneeDisplayName ?? "Sin responsable", systemImage: "person.crop.circle")
                Label(task.dueText, systemImage: "calendar").fixedSize(horizontal: false, vertical: true)
                Text(task.priority.rawValue).foregroundStyle(MyaowColor.orange)
            }.font(.subheadline)
        }
    }
    private func progress(_ task: GroupMissionModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(task.isCompleted ? "¡Buen trabajo, equipo!" : "Cada paso cuenta.").font(.headline)
                Spacer()
                Text("\(task.progress)%").font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(MyaowColor.orange)
            }
            ProgressView(value: Double(task.progress), total: 100).tint(task.isCompleted ? MyaowColor.statusGreen : MyaowColor.orange)
            if canEdit {
                Slider(value: $proposedProgress, in: 0...100, step: 1).tint(MyaowColor.orange)
                    .accessibilityLabel("Porcentaje de avance").disabled(updating)
                Text("Avance a guardar: \(Int(proposedProgress))%").font(.subheadline.monospacedDigit())
                Text("Puedes añadir fotos, video, un archivo o una nota abajo antes de guardar.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                Button {
                    var items: [TaskEvidenceStore.Item] = []
                    let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { items.append(.init(text: text, type: "text")) }
                    if let fileData { items.append(.init(text: fileName, type: "rawFile", data: fileData)) }
                    if !items.isEmpty {
                        guard enqueue(items) else { return }
                        comment = ""; fileData = nil; fileName = ""
                    }
                    update(Int(proposedProgress))
                } label: { Label(proposedProgress == 100 ? "Completar tarea" : "Guardar avance", systemImage: "checkmark.circle") }
                    .buttonStyle(GroupPrimaryStyle()).disabled(updating || importing || comment.utf8.count > 8000)
                if proposedProgress != 100 {
                    Button("Ya terminé · 100%") { proposedProgress = 100 }.tint(MyaowColor.orange)
                }
            }
            if updating { ProgressView("Guardando avance…").font(.caption).tint(MyaowColor.orange) }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Deja tu avance").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(["Logré…", "Siguiente paso…", "Necesito ayuda con…"], id: \.self) { prompt in
                        Button(prompt) { if comment.isEmpty { comment = prompt + " " } }
                            .font(.caption).padding(.horizontal, 12).frame(minHeight: 44).background(MyaowColor.surfaceElevated, in: Capsule()).tint(MyaowColor.orange)
                    }
                }
            }
            TextField("Qué hiciste, qué falta o qué necesitas", text: $comment, axis: .vertical).lineLimit(3...6)
                .padding(14).background(MyaowColor.charcoal, in: RoundedRectangle(cornerRadius: 16))
            if fileData != nil {
                HStack {
                    Label(fileName, systemImage: "doc.fill").font(.caption).lineLimit(2)
                    Spacer()
                    Button { fileData = nil; fileName = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel("Quitar archivo")
                }
            }
            HStack(spacing: 18) {
                PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
                    Label("Fotos", systemImage: "photo.on.rectangle").frame(minHeight: 44)
                }.disabled(importing)
                Button { showingFiles = true } label: { Label("Archivo", systemImage: "paperclip").frame(minHeight: 44) }
                Spacer()
                if importing { ProgressView().tint(MyaowColor.orange) }
            }.font(.subheadline).tint(MyaowColor.orange)
            Button {
                var items: [TaskEvidenceStore.Item] = []
                let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { items.append(.init(text: text, type: "text")) }
                if let fileData { items.append(.init(text: fileName, type: "rawFile", data: fileData)) }
                if enqueue(items) { comment = ""; fileData = nil; fileName = "" }
            } label: { Label("Compartir avance", systemImage: "arrow.up") }.buttonStyle(GroupPrimaryStyle())
                .disabled(importing || (comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && fileData == nil) || comment.utf8.count > 8000)
            Text("Visible para el grupo. Puedes compartir evidencia sin marcar la tarea como terminada.")
                .font(.caption).foregroundStyle(MyaowColor.textSecondary)
        }.padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private func enqueue(_ items: [TaskEvidenceStore.Item]) -> Bool {
        guard !DesignPreviewData.isEnabled else { error = "Vista de diseño con datos ficticios."; return false }
        let group = space.id.uuidString
        do {
            guard task != nil else { throw SecureMessageError.invalidEnvelope }
            let chat = try context.fetch(FetchDescriptor<ConversationModel>()).first { $0.isGroup && $0.id.lowercased() == group.lowercased() }
                ?? ConversationModel(id: group, title: space.title, isGroup: true)
            let identity = IdentityManager.shared.currentIdentity
            try TaskEvidenceStore.enqueue(items, task: taskID, conversation: chat, actor: own, name: identity.displayName, context: context)
            MyaowBackendEngine.shared.retryPendingMessages(force: true)
            error = nil; UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func update(_ value: Int) {
        guard canEdit && !updating else { return }
        updating = true
        Task { @MainActor in
            defer { updating = false }
            guard !DesignPreviewData.isEnabled else { error = "Vista de diseño con datos ficticios."; return }
            do {
                if let changed = try await GroupTasksService.shared.updateProgress(taskId: taskID.uuidString, progress: value),
                   let index = space.missions.firstIndex(where: { $0.id == taskID }) {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.35)) { space.missions[index] = changed; celebration = value == 100 }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
    private func refresh() async {
        guard !DesignPreviewData.isEnabled else { return }
        do { space.missions = try await GroupTasksService.shared.fetchTasks(groupId: space.id.uuidString).compactMap(\.mission); if let policy = GroupTasksService.shared.policies[space.id.uuidString.lowercased()] { space.taskPolicy = policy }; error = nil }
        catch { self.error = error.localizedDescription }
    }
}
