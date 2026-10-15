import SwiftUI
import SwiftData

struct ConversationDecorationPicker: View {
    let conversation: ConversationModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selection: ChatDecoration
    @State private var localOnly = false
    @State private var canShare = false
    @State private var checking = false
    @State private var saving = false
    @State private var error: String?
    init(conversation: ConversationModel) {
        self.conversation = conversation
        _selection = State(initialValue: conversation.localDecorationRaw.flatMap(ChatDecoration.init(rawValue:)) ?? ChatDecorationEvent.decode(conversation.sharedDecorationJSON)?.decoration ?? .lava)
        _localOnly = State(initialValue: conversation.localDecorationRaw != nil)
        _canShare = State(initialValue: !conversation.isGroup)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Un espacio de ustedes.").font(.system(size: 29, weight: .semibold)).tracking(-0.9)
                    Text("Elige una atmósfera para esta conversación. La decoración compartida llegará cuando la otra persona se conecte.")
                        .font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                    preview
                    Toggle("Solo en mi teléfono", isOn: $localOnly).tint(MyaowColor.orange)
                    if !canShare && conversation.isGroup {
                        Text(checking ? "Comprobando permisos del grupo…" : "Solo los administradores pueden cambiar el fondo para todo el grupo. Tú puedes elegir uno personal.")
                            .font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ChatDecoration.allCases) { item in
                            Button { selection = item } label: {
                                ZStack(alignment: .bottomLeading) {
                                    MyaowColor.charcoal
                                    if let resource = item.resource { Color.clear.overlay { Image(resource).resizable().scaledToFill() }.clipped() }
                                    LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                                    HStack {
                                        Text(item.title).font(.subheadline.weight(.medium))
                                        Spacer(minLength: 2)
                                        if item == selection { Image(systemName: "checkmark.circle.fill").foregroundStyle(MyaowColor.orange) }
                                    }.padding(12)
                                }.frame(height: 132).clipShape(RoundedRectangle(cornerRadius: 18))
                                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(item == selection ? MyaowColor.orange : .white.opacity(0.1)))
                            }.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityAddTraits(item == selection ? .isSelected : [])
                        }
                    }
                    if conversation.localDecorationRaw != nil {
                        Button("Volver a la decoración compartida") {
                            conversation.localDecorationRaw = nil
                            do { try context.save(); dismiss() } catch { context.rollback(); self.error = error.localizedDescription }
                        }.font(.subheadline).foregroundStyle(MyaowColor.orange)
                    }
                    Text("El movimiento y el ahorro de batería se respetan en cada teléfono. Ambos necesitan esta versión para ver el fondo compartido.")
                        .font(.caption).foregroundStyle(MyaowColor.textSecondary)
                }.padding(22)
            }
            .safeAreaInset(edge: .bottom) {
                Button { Task { await apply() } } label: {
                    HStack {
                        if saving { ProgressView().tint(.black) }
                        Text(localOnly ? "Aplicar solo para mí" : conversation.isGroup ? "Aplicar para el grupo" : "Aplicar para ambos").font(.headline)
                    }.frame(maxWidth: .infinity).frame(height: 52).foregroundStyle(.black).background(MyaowColor.orange, in: Capsule())
                }.disabled(saving || checking || (!localOnly && !canShare)).padding(16).background(MyaowColor.charcoal)
            }
            .background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
            .navigationTitle("Decorar chat").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.disabled(saving) } }
        }
        .tint(MyaowColor.orange)
        .interactiveDismissDisabled(saving)
        .onAppear { AppAtmosphereStore.shared.previewingDecoration = true }
        .onDisappear { AppAtmosphereStore.shared.previewingDecoration = false }
        .task {
            guard conversation.isGroup else { return }
            checking = true
            defer { checking = false }
            do {
                canShare = try await authorized()
                if !canShare { localOnly = true }
            } catch { self.error = "No pudimos comprobar tus permisos. Puedes elegir una decoración solo para ti."; localOnly = true }
        }
        .alert("Decoración sin guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Entendido", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }
    private var preview: some View {
        ZStack {
            MyaowColor.charcoal
            if let resource = selection.resource { VideoWallpaperView(resource: resource, motionEnabled: AppAtmosphereStore.shared.motion) }
            Color.black.opacity(0.4)
            VStack(alignment: .leading, spacing: 14) {
                Label(selection.title, systemImage: "paintpalette").font(.caption.weight(.semibold))
                Spacer()
                Text("Este rincón ya se siente nuestro.").font(.subheadline).padding(12).background(MyaowColor.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
                HStack { Spacer(); Text("Sí, aquí nos quedamos 🧡").font(.subheadline).padding(12).foregroundStyle(.black).background(MyaowColor.orange, in: RoundedRectangle(cornerRadius: 16)) }
            }.padding(20)
        }.frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 24))
    }
    private func authorized() async throws -> Bool {
        if DesignPreviewData.isEnabled { return true }
        let actor = IdentityManager.shared.currentIdentity.myaowId
        return try await GroupDeliveryService.members(conversation.id).contains { $0.myaow_id == actor && ["admin", "owner"].contains($0.role) }
    }
    private func apply() async {
        saving = true
        defer { saving = false }
        do {
            if localOnly {
                conversation.localDecorationRaw = selection.rawValue
                try context.save()
            } else {
                if conversation.isGroup { guard try await authorized() else { throw DecorationError.administratorRequired } }
                let own = IdentityManager.shared.currentIdentity
                try ChatDecorationStore.enqueue(selection, conversation: conversation, actor: own.myaowId, name: own.displayName, context: context)
                MyaowBackendEngine.shared.retryPendingMessages(force: true)
            }
            dismiss()
        } catch { context.rollback(); self.error = error.localizedDescription }
    }
}
