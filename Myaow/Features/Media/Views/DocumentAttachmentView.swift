import SwiftUI
import QuickLook

struct DocumentAttachmentView: View {
    let message: MessageModel
    @Environment(\.dismiss) private var dismiss
    @State private var file: URL?
    @State private var directory: URL?
    var body: some View {
        NavigationStack {
            Group {
                if let file { DocumentQuickLook(url: file) }
                else { ContentUnavailableView("No pudimos abrir el archivo", systemImage: "doc.badge.ellipsis") }
            }
            .navigationTitle("Archivo").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .task {
            guard let data = message.mediaData else { return }
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MyaowDocument-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                directory = folder
                let name = String(URL(fileURLWithPath: message.text).lastPathComponent.prefix(180))
                let url = folder.appendingPathComponent(name.isEmpty || name == "." || name == ".." ? "archivo" : name)
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                file = url
            } catch { file = nil }
        }
        .onDisappear { if let directory { try? FileManager.default.removeItem(at: directory) } }
    }
}
private struct DocumentQuickLook: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
