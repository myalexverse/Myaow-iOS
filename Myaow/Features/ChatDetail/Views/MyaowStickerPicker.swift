import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MyaowStickerArtwork: View {
    let sticker: MyaowSticker
    var size: CGFloat = 98
    var body: some View {
        VStack(spacing: 3) {
            MyaowCatView(state: MyaowCatState(rawValue: sticker.emotion) ?? .friendly,
                         style: .orangeOnTransparent, size: size, isInteractive: false)
                .shadow(color: MyaowColor.orange.opacity(0.15), radius: 12, y: 4)
            Text(sticker.title).font(.system(size: size < 100 ? 13 : 17, weight: .bold, design: .rounded))
                .foregroundStyle(MyaowColor.textPrimary).lineLimit(1).minimumScaleFactor(0.75)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(MyaowColor.surfaceElevated, in: Capsule())
        }.accessibilityElement(children: .ignore).accessibilityLabel("Sticker: " + sticker.title)
    }
}

struct MyaowStickerPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSend: (String) -> Bool
    let onSendImage: (Data) -> Bool
    @State private var photo: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFiles = false
    @State private var imported: StickerImport?
    @State private var saved: [URL] = []
    @State private var importError: String?
    @State private var importing = false
    private struct StickerImport: Identifiable { let id = UUID(); let data: Data }

    @State private var search = ""
    @State private var selected: MyaowSticker?
    @State private var failed = false
    private var filtered: [MyaowSticker] {
        MyaowSticker.all.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.emotion.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Mucho que decir. Muy Myaow.").font(.title2.weight(.semibold)).tracking(-0.5)
                    Text("Tus gatos, con otra forma de expresarse.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                    HStack(spacing: 12) {
                        Button { showPhotoPicker = true } label: { Label("Crear con foto", systemImage: "wand.and.stars").frame(maxWidth: .infinity, minHeight: 48) }
                        Button { showFiles = true } label: { Label("Importar", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 48) }
                    }.font(.subheadline.weight(.semibold)).tint(MyaowColor.orange)
                        .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 18)).disabled(importing)
                    if importing { ProgressView("Preparando imagen…") }
                    if !saved.isEmpty {
                        Text("Mis stickers").font(.headline)
                        LazyVGrid(columns: [.init(.adaptive(minimum: 90), spacing: 12)], spacing: 12) {
                            ForEach(saved, id: \.self) { url in
                                Button {
                                    guard let data = try? Data(contentsOf: url) else { importError = "No pudimos abrir el sticker."; return }
                                    if onSendImage(data) { dismiss() } else { failed = true }
                                } label: {
                                    if let image = UIImage(contentsOfFile: url.path) {
                                        Image(uiImage: image).resizable().scaledToFit().frame(height: 100)
                                    }
                                }.buttonStyle(.plain).accessibilityLabel("Enviar sticker guardado")
                                    .contextMenu { Button("Eliminar de mi colección", role: .destructive) {
                                        do { try CustomStickerLibrary.remove(url); saved = CustomStickerLibrary.items() }
                                        catch { importError = "No se pudo eliminar el sticker." }
                                    } }
                            }
                        }
                    }
                    Text("Los gatos de Myaow").font(.headline)
                    if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                    LazyVGrid(columns: [.init(.adaptive(minimum: 100), spacing: 12)], spacing: 14) {
                        ForEach(filtered) { sticker in
                            Button { selected = sticker } label: {
                                MyaowStickerArtwork(sticker: sticker).frame(maxWidth: .infinity).padding(.vertical, 14)
                                    .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 22))
                                    .overlay { RoundedRectangle(cornerRadius: 22).stroke(selected?.id == sticker.id ? MyaowColor.orange : MyaowColor.borderSubtle, lineWidth: 1) }
                            }.buttonStyle(MyaowScaleButtonStyle()).accessibilityAddTraits(selected?.id == sticker.id ? .isSelected : [])
                        }
                    }
                }.padding(20)
            }.background(MyaowColor.charcoal).foregroundStyle(MyaowColor.textPrimary)
                .searchable(text: $search, prompt: "Buscar una expresión")
                .navigationTitle("Stickers Myaow").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() }.tint(MyaowColor.textSecondary) } }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        guard let selected else { return }
                        if onSend(selected.wireText) { dismiss() } else { failed = true }
                    } label: {
                        Label(selected.map { "Enviar: " + $0.title } ?? "Elige un sticker", systemImage: "arrow.up")
                            .font(.headline).frame(maxWidth: .infinity).padding(17)
                            .foregroundStyle(selected == nil ? MyaowColor.textSecondary : .black)
                            .background(selected == nil ? MyaowColor.surface : MyaowColor.orange, in: Capsule())
                    }.disabled(selected == nil).padding(20).background(MyaowColor.charcoal)
                }
        }.preferredColorScheme(.dark).presentationDragIndicator(.visible)
            .onAppear { saved = CustomStickerLibrary.items() }
            .task {
                #if DEBUG
                if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--sticker-editor-preview"),
                   let data = UIImage(named: "WallpaperEmber")?.pngData() {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    imported = StickerImport(data: data)
                }
                #endif
            }
            .photosPicker(isPresented: $showPhotoPicker, selection: $photo, matching: .images)
            .task(id: photo) {
                guard let photo else { return }
                importing = true
                defer { importing = false }
                do {
                    guard let item = try await photo.loadTransferable(type: ImportedChatMedia.self), !item.isVideo, item.data.count <= 20*1024*1024 else { throw CocoaError(.fileReadTooLarge) }
                    try Task.checkCancellation(); imported = StickerImport(data: item.data)
                } catch { if !Task.isCancelled { importError = "Elige una imagen de hasta 20 MB." } }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.png, .jpeg, .webP, .heic]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 20*1024*1024 else { throw CocoaError(.fileReadTooLarge) }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 20*1024*1024 else { throw CocoaError(.fileReadTooLarge) }
                    imported = StickerImport(data: data)
                } catch { if (error as NSError).code != NSUserCancelledError { importError = "No pudimos importar esa imagen. Usa PNG, JPG, HEIC o WebP de hasta 20 MB." } }
            }
            .sheet(item: $imported, onDismiss: { photo = nil }) { item in
                CustomStickerEditor(source: item.data, onSaved: { saved = CustomStickerLibrary.items() }, onSend: onSendImage)
            }
            .alert("No se pudo importar", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("Entendido", role: .cancel) {}
            } message: { Text(importError ?? "") }
            .alert("No se pudo guardar", isPresented: $failed) { Button("Entendido", role: .cancel) {} }
            message: { Text("El sticker sigue seleccionado. Intenta enviarlo otra vez.") }
    }
}
