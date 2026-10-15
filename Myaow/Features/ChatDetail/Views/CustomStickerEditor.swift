import SwiftUI
import PhotosUI
import CryptoKit

@MainActor enum CustomStickerLibrary {
    private static func folder() throws -> URL {
        let owner = IdentityManager.shared.currentIdentity.myaowId
        let name = SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Stickers/" + name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return root
    }
    static func items() -> [URL] {
        guard let folder = try? folder() else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    static func save(_ data: Data) throws {
        guard data.count <= 2*1024*1024 else { throw CocoaError(.fileWriteOutOfSpace) }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard !items().contains(where: { $0.lastPathComponent.hasSuffix("-\(digest).png") }) else { return }
        guard items().count < 100 else { throw CocoaError(.fileWriteOutOfSpace) }
        let file = try folder().appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(digest).png")
        try data.write(to: file, options: [.atomic, .completeFileProtection])
    }
    static func remove(_ url: URL) throws {
        guard url.deletingLastPathComponent() == (try folder()) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

struct CustomStickerEditor: View {
    @Environment(\.dismiss) private var dismiss
    let source: Data
    let onSaved: () -> Void
    let onSend: (Data) -> Bool
    @State private var prepared: Data?
    @State private var cutout = false
    @State private var caption = ""
    @State private var decoration = ""
    @State private var busy = false
    @State private var error: String?
    @State private var cutoutUnavailable = false
    private var artwork: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                if let data = prepared, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFit().padding(12)
                }
                if !decoration.isEmpty { Text(decoration).font(.system(size: 58)).padding(14) }
            }.frame(width: 280, height: caption.isEmpty ? 280 : 225)
            if !caption.isEmpty {
                Text(caption).font(.system(size: 25, weight: .heavy, design: .rounded)).multilineTextAlignment(.center)
                    .foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.6)
                    .padding(.horizontal, 15).padding(.vertical, 8).background(.black.opacity(0.8), in: Capsule())
                    .padding(.horizontal, 10).padding(.bottom, 8)
            }
        }.frame(width: 300, height: 300)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Hazlo tuyo").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Una foto. Un gesto. Tu próximo sticker favorito.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary).multilineTextAlignment(.center)
                    artwork.background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 26))
                    Toggle("Recortar el fondo", isOn: $cutout).tint(MyaowColor.orange).disabled(busy || cutoutUnavailable)
                    if cutoutUnavailable {
                        Text("No encontramos un sujeto para recortar. Puedes crear el sticker con la imagen completa.")
                            .font(.footnote).foregroundStyle(MyaowColor.textSecondary)
                    }
                    TextField("Ponle una frase", text: $caption).textFieldStyle(.roundedBorder)
                        .onChange(of: caption) { _, value in caption = String(value.prefix(48)) }
                    HStack {
                        ForEach(["", "🧡", "✨", "😂", "🔥", "👀"], id: \.self) { emoji in
                            Button { decoration = emoji } label: {
                                Text(emoji.isEmpty ? "×" : emoji).font(.title2).frame(maxWidth: .infinity, minHeight: 44)
                                    .background(decoration == emoji ? MyaowColor.orange.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 12))
                            }.accessibilityLabel(emoji.isEmpty ? "Sin decoración" : emoji)
                        }
                    }
                    if busy { ProgressView("Preparando sticker…").tint(MyaowColor.orange) }
                    if let error { Text(error).font(.footnote).foregroundStyle(MyaowColor.orange) }
                    Text("El recorte se hace en tu iPhone. Se guarda en tu colección al enviar.").font(.footnote).foregroundStyle(MyaowColor.textSecondary)
                }.padding(20)
            }.background(MyaowColor.charcoal)
                .navigationTitle("Crear sticker").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    Button {
                        let renderer = ImageRenderer(content: artwork); renderer.scale = 512.0 / 300
                        renderer.isOpaque = false
                        guard let data = renderer.uiImage?.pngData(), data.count <= 2*1024*1024 else { error = "No pudimos preparar el sticker."; return }
                        do { try CustomStickerLibrary.save(data); onSaved() }
                        catch { self.error = "Tu colección está llena o no se pudo guardar. Elimina un sticker e inténtalo de nuevo."; return }
                        if onSend(data) { dismiss() } else { error = "Guardado en tu colección. No se pudo enviar; inténtalo desde Mis stickers." }
                    } label: {
                        Label("Guardar y enviar", systemImage: "paperplane.fill").font(.headline).frame(maxWidth: .infinity).padding(17)
                            .foregroundStyle(.black).background(MyaowColor.orange, in: Capsule())
                    }.disabled(busy || prepared == nil).padding(20).background(MyaowColor.charcoal)
                }
        }.preferredColorScheme(.dark)
            .task(id: cutout) {
                busy = true; error = nil
                defer { busy = false }
                let mode = cutout
                do {
                    let data = try await Task.detached(priority: .userInitiated) { try CustomStickerImage.prepare(source, removeBackground: mode) }.value
                    try Task.checkCancellation(); prepared = data
                } catch {
                    guard !Task.isCancelled else { return }
                    if mode {
                        cutoutUnavailable = true
                        cutout = false
                    } else {
                        self.error = "No pudimos abrir esta imagen. Prueba con otra foto."
                    }
                }
            }
    }
}
