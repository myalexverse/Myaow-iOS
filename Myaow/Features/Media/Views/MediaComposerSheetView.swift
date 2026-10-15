import SwiftUI

public struct MediaComposerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ChatMediaSelection]
    @State private var selectedID: UUID?
    @State private var caption = ""
    @State private var quality: MediaQualityMode = .hdOptimized
    @State private var sending = false
    @State private var error: String?
    public var onSend: ([MediaAttachmentPayload]) -> Bool

    public init(items: [ChatMediaSelection], onSend: @escaping ([MediaAttachmentPayload]) -> Bool) {
        self._items = State(initialValue: items)
        self._selectedID = State(initialValue: items.first?.id)
        self.onSend = onSend
    }
    private var selected: ChatMediaSelection? { items.first { $0.id == selectedID } ?? items.first }
    public var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack {
                    Label(items.count == 1 ? "1 archivo" : "\(items.count) archivos", systemImage: "photo.stack")
                    Spacer()
                    Menu {
                        ForEach(MediaQualityMode.allCases) { mode in Button(mode.rawValue) { quality = mode } }
                    } label: { Text(quality == .hdOptimized ? "HD" : "Original").font(.subheadline.weight(.semibold)).padding(10).background(MyaowColor.surface, in: Capsule()) }
                }.font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                if let selected {
                    GeometryReader { geometry in
                        ZStack {
                            MyaowAsyncThumbnailView(data: selected.data, maxDimension: 960, cornerRadius: 22, isVideo: selected.isVideo, contentMode: .fit)
                            if selected.isVideo { Image(systemName: "play.circle.fill").font(.system(size: 56)).foregroundStyle(.white).shadow(radius: 10) }
                        }.frame(width: geometry.size.width, height: geometry.size.height).clipped().id(selected.id)
                            .accessibilityLabel(selected.isVideo ? "Vista previa de video" : "Vista previa de foto")
                    }
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            Button { selectedID = item.id } label: {
                                MyaowAsyncThumbnailView(data: item.data, maxDimension: 160, cornerRadius: 12, isVideo: item.isVideo)
                                    .frame(width: 62, height: 68).clipped()
                                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected?.id == item.id ? MyaowColor.orange : .clear, lineWidth: 2) }
                                    .overlay(alignment: .bottomTrailing) { if item.isVideo { Image(systemName: "video.fill").font(.caption).padding(4).background(.black.opacity(0.6), in: Capsule()) } }
                            }.accessibilityLabel("Seleccionar archivo \((items.firstIndex { $0.id == item.id } ?? 0) + 1)")
                        }
                    }.padding(2)
                }.scrollIndicators(.hidden)
                HStack(alignment: .top) {
                    Text(quality == .hdOptimized ? "Fotos en JPEG HD. Videos en calidad original, hasta 10 MB." : "Hasta 10 MB por original. Puede incluir ubicación y otros metadatos.")
                        .font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    Spacer()
                    Button(role: .destructive) {
                        guard let selected else { return }
                        items.removeAll { $0.id == selected.id }; selectedID = items.first?.id
                        if items.isEmpty { dismiss() }
                    } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("Quitar archivo seleccionado")
                }
                TextField(items.count > 1 ? "Comentario para la primera foto o video" : "Añadir un comentario", text: $caption, axis: .vertical)
                    .lineLimit(1...3).padding(14).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 16))
                Button(action: send) {
                    HStack { if sending { ProgressView().tint(.black) }; Text(sending ? "Preparando…" : "Enviar \(items.count == 1 ? "archivo" : "\(items.count) archivos")"); Image(systemName: "arrow.up") }
                        .font(.headline).frame(maxWidth: .infinity).padding(16).foregroundStyle(.black).background(MyaowColor.orange, in: Capsule())
                }.disabled(items.isEmpty || sending)
            }.padding(20).background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
                .navigationTitle("Antes de enviar").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.tint(MyaowColor.textSecondary) } }
                .disabled(sending)
        }.preferredColorScheme(.dark).interactiveDismissDisabled(sending)
            .alert("No se pudo enviar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Entendido", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
    private func send() {
        guard !sending, !items.isEmpty else { return }
        sending = true
        let selection = items, mode = quality, text = caption
        Task {
            defer { sending = false }
            do {
                let payloads = try await Task.detached(priority: .userInitiated) {
                    try selection.enumerated().map { index, item in
                        let data = !item.isVideo && mode == .hdOptimized ? try ChatPhotoEncoding.jpeg(item.data) : item.data
                        guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else { throw ChatMediaSelectionError.tooLarge }
                        return MediaAttachmentPayload(data: data, isVideo: item.isVideo, quality: mode,
                            caption: index == 0 ? text : "", fileSizeFormatted: "", dimensionsFormatted: "")
                    }
                }.value
                if onSend(payloads) { dismiss() }
                else { error = "No pudimos guardar el envío. Tu selección sigue aquí; vuelve a intentarlo." }
            } catch { self.error = error.localizedDescription }
        }
    }
}
