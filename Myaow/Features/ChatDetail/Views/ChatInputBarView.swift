import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct ChatInputBarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let conversationId: String
    let recipientMyaowId: String
    @Binding var replyingToMessage: MessageModel?
    let onSendMessage: (String) -> Bool
    let onSendVoice: (Double, [CGFloat], Data?) -> Void
    let onShowNudgeDeck: (() -> Void)?
    let onShowScheduleSheet: (String) -> Void
    let onPickedMedia: ([ChatMediaSelection]) -> Void
    let onSendSticker: (String) -> Bool
    let onSendCustomSticker: (Data) -> Bool
    let onPickedFile: ((Data, String) -> Void)?
    @State private var showingFiles = false
    @State private var inputText = ""
    @State private var voiceService = VoiceRecordingService.shared
    @State private var selectedPhotoPickerItems: [PhotosPickerItem] = []
    @State private var mediaLoadTask: Task<Void, Never>?
    @State private var showingStickers = false
    @State private var mediaProgress = ""
    @State private var showingPhotos = false
    @State private var loadingMedia = false
    @State private var mediaError: String?
    @FocusState.Binding private var isTextFieldFocused: Bool

    public init(conversationId: String, recipientMyaowId: String, replyingToMessage: Binding<MessageModel?>, focus: FocusState<Bool>.Binding,
        onSendMessage: @escaping (String) -> Bool, onSendVoice: @escaping (Double, [CGFloat], Data?) -> Void,
        onShowNudgeDeck: (() -> Void)?, onShowScheduleSheet: @escaping (String) -> Void,
        onPickedMedia: @escaping ([ChatMediaSelection]) -> Void, onSendSticker: @escaping (String) -> Bool, onSendCustomSticker: @escaping (Data) -> Bool, onPickedFile: ((Data, String) -> Void)? = nil) {
        self.conversationId = conversationId
        self.recipientMyaowId = recipientMyaowId
        self._replyingToMessage = replyingToMessage
        self._isTextFieldFocused = focus
        self.onSendMessage = onSendMessage
        self.onSendVoice = onSendVoice
        self.onShowNudgeDeck = onShowNudgeDeck
        self.onShowScheduleSheet = onShowScheduleSheet
        self.onPickedMedia = onPickedMedia
        self.onSendSticker = onSendSticker
        self.onSendCustomSticker = onSendCustomSticker
        self.onPickedFile = onPickedFile
    }
    private var trimmedText: String { inputText.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var body: some View {
        VStack(spacing: 10) {
            if let reply = replyingToMessage {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(MyaowColor.orange).frame(width: 3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(reply.senderName).font(.system(size: 13, weight: .semibold)).foregroundStyle(MyaowColor.orange)
                        Text(reply.text).font(.system(size: 13)).foregroundStyle(MyaowColor.textSecondary).lineLimit(1)
                    }
                    Spacer()
                    Button { replyingToMessage = nil } label: { Image(systemName: "xmark").frame(width: 36, height: 40) }.accessibilityLabel("Cancelar respuesta")
                }
                .frame(height: 44).padding(10).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 12))
            }
            if loadingMedia { ProgressView(mediaProgress).font(.system(size: 12)).tint(MyaowColor.orange) }
            if voiceService.isRecording {
                HStack(spacing: 14) {
                    Button { voiceService.cancelRecording() } label: { Image(systemName: "trash").frame(width: 40, height: 44) }.accessibilityLabel("Cancelar grabación")
                    Circle().fill(MyaowColor.statusRed).frame(width: 7, height: 7)
                    Text(voiceService.durationFormatted).font(.system(size: 15, weight: .medium, design: .monospaced))
                    HStack(spacing: 3) {
                        ForEach(voiceService.waveformBars) { bar in Capsule().fill(MyaowColor.orange).frame(width: 3, height: max(3, bar.value * 26)) }
                    }.frame(height: 30)
                    Spacer(minLength: 0)
                    Button {
                        let result = voiceService.stopAndExportRecording()
                        guard let audio = result.audioData, !audio.isEmpty else { mediaError = "No pudimos guardar el audio. Intenta grabarlo de nuevo."; return }
                        onSendVoice(result.duration, result.samples, audio)
                    } label: { sendSymbol }.accessibilityLabel("Enviar nota de voz")
                }
            } else {
                HStack(alignment: .bottom, spacing: 6) {
                    Menu {
                        if onPickedFile != nil { Button { showingFiles = true } label: { Label("Archivo", systemImage: "doc") } }
                        Button { showingPhotos = true } label: { Label("Fotos y videos", systemImage: "photo.on.rectangle") }
                        if let onShowNudgeDeck { Button(action: onShowNudgeDeck) { Label { Text("Maullidos y zumbidos") } icon: { MyaowMaullidosMark(size: 22) } } }
                        if !trimmedText.isEmpty {
                            Button { onShowScheduleSheet(trimmedText) } label: { Label("Programar mensaje", systemImage: "clock") }
                        }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 21, weight: .regular)).frame(width: 34, height: 46)
                    }.accessibilityLabel("Adjuntar y más opciones").disabled(loadingMedia)
                    HStack(alignment: .bottom, spacing: 0) {
                        TextField("Escribe un mensaje…", text: $inputText, axis: .vertical)
                            .font(.system(size: 16)).lineLimit(1...5)
                            .focused($isTextFieldFocused)
                            .padding(.leading, 15).padding(.vertical, 13)
                            .onChange(of: inputText) { old, new in
                                UserDefaults.standard.set(new, forKey: "myaow_draft_" + IdentityManager.shared.currentIdentity.myaowId + "_" + conversationId)
                                if !recipientMyaowId.isEmpty, old.isEmpty != new.isEmpty { OnlineMessagingService.shared.sendTypingIndicator(recipientMyaowId: recipientMyaowId, isTyping: !new.isEmpty) }
                            }
                        Button { isTextFieldFocused = false; showingStickers = true } label: {
                            Image(systemName: "face.smiling").font(.system(size: 19)).foregroundStyle(MyaowColor.textSecondary).frame(width: 44, height: 46)
                        }.accessibilityLabel("Abrir stickers")
                    }
                    .background(Color(hex: "1C1E22"), in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.08), lineWidth: 0.75))
                    if trimmedText.isEmpty, let onShowNudgeDeck {
                        Button { isTextFieldFocused = false; onShowNudgeDeck() } label: {
                            MyaowMaullidosButtonIconView(cooldownSeconds: MyaowNudgeService.shared.cooldownSeconds)
                        }.accessibilityLabel("Abrir maullidos")
                    }
                    ZStack {
                        if trimmedText.isEmpty {
                            Button { voiceService.startRecording() } label: {
                                Image(systemName: "mic").font(.system(size: 21)).frame(width: 44, height: 46)
                            }.accessibilityLabel("Grabar nota de voz")
                                .transition(.opacity)
                        } else {
                            Button {
                                if onSendMessage(trimmedText) { inputText = "" }
                            } label: { sendSymbol }.accessibilityLabel("Enviar mensaje")
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.86)))
                        }
                    }
                    .frame(width: 44, height: 46)
                    .buttonStyle(MyaowScaleButtonStyle())
                    .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.18), value: trimmedText.isEmpty)
                }
            }
        }
        .foregroundStyle(MyaowColor.textPrimary)
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
        .background(MyaowColor.charcoal)
        .overlay(alignment: .top) { Rectangle().fill(MyaowColor.borderSubtle).frame(height: 0.5) }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.item]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= SupabaseMediaClient.maximumPlaintextBytes else { mediaError = "Elige un archivo de hasta 10 MB."; return }
                let data = try Data(contentsOf: url)
                guard data.count <= SupabaseMediaClient.maximumPlaintextBytes else { mediaError = "Elige un archivo de hasta 10 MB."; return }
                onPickedFile?(data, url.lastPathComponent)
            } catch { if (error as NSError).code != NSUserCancelledError { mediaError = "No pudimos abrir ese archivo. Vuelve a intentarlo." } }
        }
        .photosPicker(isPresented: $showingPhotos, selection: $selectedPhotoPickerItems, maxSelectionCount: 10,
                      selectionBehavior: .ordered, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhotoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            mediaLoadTask?.cancel()
            loadingMedia = true
            mediaLoadTask = Task { @MainActor in
                defer { loadingMedia = false; selectedPhotoPickerItems = [] }
                do {
                    var selection: [ChatMediaSelection] = []
                    var totalBytes = 0
                    for (index, item) in items.enumerated() {
                        try Task.checkCancellation()
                        mediaProgress = "Preparando \(index + 1) de \(items.count)…"
                        guard let imported = try await item.loadTransferable(type: ImportedChatMedia.self) else { throw ChatMediaSelectionError.unreadable }
                        try Task.checkCancellation()
                        totalBytes += imported.data.count
                        guard totalBytes <= 50 * 1024 * 1024 else { throw ChatMediaSelectionError.tooLarge }
                        selection.append(ChatMediaSelection(data: imported.data, isVideo: imported.isVideo))
                    }
                    onPickedMedia(selection)
                } catch is CancellationError { }
                catch { mediaError = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showingStickers) { MyaowStickerPicker(onSend: onSendSticker, onSendImage: onSendCustomSticker) }
        .alert("No se pudo completar", isPresented: Binding(get: { mediaError != nil }, set: { if !$0 { mediaError = nil } })) {
            Button("Entendido", role: .cancel) { mediaError = nil }
        } message: { Text(mediaError ?? "") }
        .onAppear {
            if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--stickers-preview") { showingStickers = true }
            inputText = UserDefaults.standard.string(forKey: "myaow_draft_" + IdentityManager.shared.currentIdentity.myaowId + "_" + conversationId) ?? "" }
        .onChange(of: voiceService.lastError) { _, error in if let error { mediaError = error; voiceService.lastError = nil } }
        .onDisappear { mediaLoadTask?.cancel(); voiceService.cancelRecording(); if !recipientMyaowId.isEmpty { OnlineMessagingService.shared.sendTypingIndicator(recipientMyaowId: recipientMyaowId, isTyping: false) } }
    }
    private var sendSymbol: some View {
        Image(systemName: "arrow.up").font(.system(size: 19, weight: .semibold)).foregroundStyle(.black)
            .frame(width: 44, height: 44).background(MyaowColor.orange, in: Circle())
    }
}
