import SwiftUI
import PhotosUI
import AVFoundation

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = UIImagePickerController.isCameraDeviceAvailable(.front) ? .front : .rear
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(picker: self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let picker: CameraPickerView
        init(picker: CameraPickerView) { self.picker = picker }
        func imagePickerController(_ controller: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.selectedImage = info[.originalImage] as? UIImage
            picker.dismiss()
        }
        func imagePickerControllerDidCancel(_ controller: UIImagePickerController) { picker.dismiss() }
    }
}

public struct ProfilePhotoPickerSheet: View {
    let currentAvatarUrl: String?
    let currentAvatarData: Data?
    let catState: MyaowCatState
    var onPhotoSelected: (Data) -> Void
    var onRemovePhoto: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var draftImage: UIImage?
    @State private var useCat = false
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragOrigin: CGSize?
    @State private var loading = false
    @State private var cameraPending = false
    @State private var errorMessage: String?
    @State private var cameraDenied = false

    public init(currentAvatarUrl: String? = nil, currentAvatarData: Data? = nil, catState: MyaowCatState,
                onPhotoSelected: @escaping (Data) -> Void, onRemovePhoto: @escaping () -> Void) {
        self.currentAvatarUrl = currentAvatarUrl
        self.currentAvatarData = currentAvatarData
        self.catState = catState
        self.onPhotoSelected = onPhotoSelected
        self.onRemovePhoto = onRemovePhoto
    }
    private var hasPhoto: Bool { !(currentAvatarUrl ?? "").isEmpty || currentAvatarData != nil }
    private var hasChanges: Bool { draftImage != nil || (useCat && hasPhoto) }
    private var transitionAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.22) }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    introduction
                    if let draftImage { cropEditor(draftImage).transition(.opacity) }
                    else { currentPreview.transition(.opacity) }
                    sourceActions
                    catOption
                }
                .padding(24)
            }
            .background(MyaowColor.charcoal)
            .navigationTitle("Foto de perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }
                        .accessibilityLabel("Cerrar sin guardar")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 10) {
                    if hasChanges {
                        Button(action: save) {
                            Text(useCat ? "Usar mi gato" : "Guardar foto")
                                .font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 52)
                                .foregroundStyle(.black).background(MyaowColor.orange, in: Capsule())
                        }
                        .disabled(loading)
                    }
                    Text(hasChanges ? "Los cambios se aplican al guardar." : "Tu foto puede cambiar. Tu gato sigue contigo.")
                        .font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 18)
                .frame(maxWidth: .infinity).background(MyaowColor.charcoal)
            }
        }
        .tint(MyaowColor.orange)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .sheet(isPresented: $showCamera, onDismiss: acceptCameraImage) {
            CameraPickerView(selectedImage: $cameraImage).ignoresSafeArea()
        }
        .task(id: selectedItem) {
            guard let item = selectedItem else { return }
            loading = true
            defer { loading = false }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let prepared = try await Task.detached(priority: .userInitiated) { try ProfilePhotoCrop.prepare(data) }.value
                try Task.checkCancellation()
                guard let image = UIImage(data: prepared) else { throw CocoaError(.fileReadCorruptFile) }
                stage(image)
            } catch is CancellationError { }
            catch { if !Task.isCancelled { errorMessage = "No pudimos abrir esa imagen. Prueba con otra foto." } }
        }
        .alert("No pudimos abrir la foto", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Entendido", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .alert("Acceso a la cámara", isPresented: $cameraDenied) {
            Button("Abrir Ajustes") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
            Button("Ahora no", role: .cancel) {}
        } message: { Text("Permite el acceso a la cámara en Ajustes para tomar tu foto. También puedes elegir una de tu galería.") }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(draftImage != nil ? "Encuentra tu encuadre." : "Tu imagen.\nTu esencia.")
                .font(.system(size: 30, weight: .semibold)).tracking(-1)
                .foregroundStyle(MyaowColor.textPrimary)
            Text(draftImage != nil ? "Arrastra la foto y ajusta el zoom." : "Elige cómo te ven en Myaow.")
                .font(.system(size: 15)).foregroundStyle(MyaowColor.textSecondary)
        }
    }

    private var currentPreview: some View {
        VStack(spacing: 16) {
            ProfileAvatarView(avatarUrl: useCat ? nil : currentAvatarUrl,
                              avatarImageData: useCat ? nil : currentAvatarData,
                              catState: catState, size: 116, showMiniCat: false, animateTransition: false)
                .padding(10)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .padding(.top, 4)
                .accessibilityLabel(useCat || !hasPhoto ? "Tu gato actual" : "Tu foto actual")
            Text(useCat || !hasPhoto ? "TU GATO MYAOW" : "TU FOTO ACTUAL")
                .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(2)
                .foregroundStyle(MyaowColor.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(
                LinearGradient(colors: [Color(hex: "#22201F"), MyaowColor.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.05)))
    }

    private func cropEditor(_ image: UIImage) -> some View {
        VStack(spacing: 18) {
            GeometryReader { geometry in
                let side = geometry.size.width
                let rect = ProfilePhotoCrop.drawingRect(source: image.size, zoom: zoom, offset: offset, side: side)
                ZStack {
                    Color.black
                    Image(uiImage: image).resizable()
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
                .frame(width: side, height: side).clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.65), lineWidth: 1))
                .contentShape(Circle())
                .gesture(DragGesture().onChanged { value in
                    if dragOrigin == nil { dragOrigin = offset }
                    let origin = dragOrigin ?? .zero
                    offset = ProfilePhotoCrop.clampedOffset(
                        CGSize(width: origin.width + value.translation.width / side, height: origin.height + value.translation.height / side),
                        source: image.size, zoom: zoom)
                }.onEnded { _ in dragOrigin = nil })
                .accessibilityLabel("Vista previa circular de tu foto")
                .accessibilityHint("Usa las acciones para mover el encuadre y el control de zoom para acercar.")
                .accessibilityAction(named: "Mover a la izquierda") { moveCrop(x: -0.1, y: 0, source: image.size) }
                .accessibilityAction(named: "Mover a la derecha") { moveCrop(x: 0.1, y: 0, source: image.size) }
                .accessibilityAction(named: "Mover arriba") { moveCrop(x: 0, y: -0.1, source: image.size) }
                .accessibilityAction(named: "Mover abajo") { moveCrop(x: 0, y: 0.1, source: image.size) }
            }
            .aspectRatio(1, contentMode: .fit)
            HStack(spacing: 12) {
                Image(systemName: "minus.magnifyingglass").accessibilityHidden(true)
                Slider(value: $zoom, in: 1...4).accessibilityLabel("Zoom de la foto")
                    .accessibilityValue(String(format: "%.1f", zoom))
                Image(systemName: "plus.magnifyingglass").accessibilityHidden(true)
            }.font(.system(size: 16)).foregroundStyle(MyaowColor.textSecondary)
            Button("Restablecer encuadre") { withAnimation(transitionAnimation) { zoom = 1; offset = .zero } }
                .font(.system(size: 13, weight: .medium))
        }
        .padding(20).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 26))
        .onChange(of: zoom) { _, value in offset = ProfilePhotoCrop.clampedOffset(offset, source: image.size, zoom: value) }
    }

    private var sourceActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(draftImage == nil ? "ELIGE UNA FOTO" : "CAMBIAR FOTO")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.8)
                Spacer()
                if loading { ProgressView().controlSize(.small).accessibilityLabel("Preparando foto") }
            }.foregroundStyle(MyaowColor.textSecondary)
            HStack(spacing: 12) {
                Button(action: openCamera) { sourceTile("Cámara", subtitle: "Una foto nueva", symbol: "camera") }
                PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                    sourceTile("Galería", subtitle: "De tu colección", symbol: "photo.on.rectangle")
                }
            }
            .buttonStyle(.plain).disabled(loading || cameraPending)
        }
    }

    private func sourceTile(_ title: String, subtitle: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).font(.system(size: 23, weight: .light)).foregroundStyle(MyaowColor.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(MyaowColor.textPrimary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(MyaowColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(18)
        .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.06)))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }

    private var catOption: some View {
        Button {
            withAnimation(transitionAnimation) { draftImage = nil; useCat = true }
        } label: {
            HStack(spacing: 14) {
                MyaowCatView(state: catState, style: .orangeOnTransparent, size: 42, isInteractive: false).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mi gato Myaow").font(.system(size: 15, weight: .semibold)).foregroundStyle(MyaowColor.textPrimary)
                    Text("Conserva tu personalidad.").font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: (useCat || (!hasPhoto && draftImage == nil)) ? "checkmark.circle.fill" : "arrow.up.right")
                    .foregroundStyle(MyaowColor.orange).font(.system(size: 18))
            }.padding(16).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).disabled(loading)
    }

    private func moveCrop(x: CGFloat, y: CGFloat, source: CGSize) {
        offset = ProfilePhotoCrop.clampedOffset(CGSize(width: offset.width + x, height: offset.height + y), source: source, zoom: zoom)
    }
    private func stage(_ image: UIImage) {
        withAnimation(transitionAnimation) { draftImage = image; useCat = false; zoom = 1; offset = .zero; dragOrigin = nil }
    }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = "La cámara no está disponible en este dispositivo. Puedes elegir una imagen de tu galería."
            return
        }
        cameraPending = true
        Task { @MainActor in
            defer { cameraPending = false }
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard !Task.isCancelled else { return }
            if allowed { cameraImage = nil; showCamera = true } else { cameraDenied = true }
        }
    }
    private func acceptCameraImage() {
        guard let image = cameraImage else { return }
        stage(image)
        cameraImage = nil
    }
    private func save() {
        if useCat { onRemovePhoto(); dismiss(); return }
        guard let image = draftImage else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true
        let output = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: format).image { context in
            UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            image.draw(in: ProfilePhotoCrop.drawingRect(source: image.size, zoom: zoom, offset: offset, side: 512))
        }
        guard let data = output.jpegData(compressionQuality: 0.85) else {
            errorMessage = "No pudimos preparar tu foto. Inténtalo de nuevo."; return
        }
        onPhotoSelected(data)
        dismiss()
    }
}
