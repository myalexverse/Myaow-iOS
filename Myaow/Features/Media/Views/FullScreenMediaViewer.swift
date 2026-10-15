//
//  FullScreenMediaViewer.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import AVKit
import Photos

public struct FullScreenMediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    
    public let message: MessageModel
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var showingInfoSheet: Bool = false
    @State private var isSavedToCameraRoll: Bool = false
    @State private var player: AVPlayer?
    @State private var videoURL: URL?
    @State private var mediaError: String?
    @State private var saving = false
    
    public init(message: MessageModel) {
        self.message = message
    }
    
    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
                .opacity(max(0.4, 1.0 - Double(abs(dragOffset.height) / 400.0)))
            
            // Contenido Multimedia con Zoom & Drag
            mediaContent
                .scaleEffect(scale)
                .offset(dragOffset)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            scale = lastScale * value
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if scale < 1.0 {
                                    scale = 1.0
                                } else if scale > 4.0 {
                                    scale = 4.0
                                }
                                lastScale = scale
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if scale <= 1.05 {
                                dragOffset = value.translation
                            }
                        }
                        .onEnded { value in
                            if abs(value.translation.height) > 120 {
                                dismiss()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dragOffset = .zero
                                }
                            }
                        }
                )
            
            // Header y Controles Flotantes
            VStack {
                topViewerHeader
                Spacer()
                bottomViewerBar
            }
        }
        .task {
            guard message.messageTypeRaw == "video", let data = message.mediaData else { return }
            do {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyaowVideo-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("video.mov")
                videoURL = url
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                player = AVPlayer(url: url)
            } catch { mediaError = "No pudimos abrir el video." }
        }
        .onDisappear {
            player?.pause(); player = nil
            if let videoURL { try? FileManager.default.removeItem(at: videoURL.deletingLastPathComponent()) }
            videoURL = nil
        }
        .alert("Multimedia", isPresented: Binding(get: { mediaError != nil }, set: { if !$0 { mediaError = nil } })) {
            Button("Entendido", role: .cancel) { mediaError = nil }
        } message: { Text(mediaError ?? "") }
        .sheet(isPresented: $showingInfoSheet) {
            mediaInfoSheet
        }
    }
    
    // MARK: - Header
    private var topViewerHeader: some View {
        HStack {
            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(message.senderName)
                    .font(.myaowHeadline)
                    .foregroundColor(.white)
                
                Text(formatTimestamp(message.timestamp))
                    .font(.myaowMicro)
                    .foregroundColor(Color.white.opacity(0.7))
            }
            .padding(.leading, 8)
            
            Spacer()
            
            Button(action: {
                showingInfoSheet = true
            }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    
    // MARK: - Media Content
    private var mediaContent: some View {
        ZStack {
            if message.messageTypeRaw == "video" {
                if let player { VideoPlayer(player: player).padding(.vertical, 100) }
                else { ProgressView("Preparando video…").tint(MyaowColor.orange) }
            } else if let data = message.mediaData {
                #if canImport(UIKit)
                if let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    placeholderImageView
                }
                #else
                placeholderImageView
                #endif
            } else {
                placeholderImageView
            }
        }
    }
    
    private var placeholderImageView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(MyaowColor.surface)
                .frame(maxWidth: .infinity, maxHeight: 400)
            
            VStack(spacing: 12) {
                Image(systemName: message.messageTypeRaw == "video" ? "video.fill" : "photo.fill")
                    .font(.system(size: 50))
                    .foregroundColor(MyaowColor.orange)
                Text(message.text.isEmpty ? "Fotografía HD" : message.text)
                    .font(.myaowBodyMedium)
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Bottom Controls
    private var bottomViewerBar: some View {
        VStack(spacing: 12) {
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.myaowBody)
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            
            HStack(spacing: 24) {
                Button(action: {
                    saveToCameraRoll()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isSavedToCameraRoll ? "checkmark" : "square.and.arrow.down")
                        Text(isSavedToCameraRoll ? "Guardado" : "Guardar")
                    }
                    .font(.myaowBodyMedium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(isSavedToCameraRoll ? MyaowColor.statusGreen : Color.white.opacity(0.2))
                    .clipShape(Capsule())
                }.disabled(saving || isSavedToCameraRoll || (message.messageTypeRaw == "video" && videoURL == nil))
            }
            .padding(.bottom, 20)
        }
    }
    
    private var mediaInfoSheet: some View {
        ZStack {
            MyaowColor.charcoal.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Capsule().fill(MyaowColor.surfaceSecondary).frame(width: 36, height: 4).padding(.top, 12)
                
                Text("Detalles del Archivo Multimedia")
                    .font(.myaowTitle)
                    .foregroundColor(MyaowColor.textPrimary)
                
                MyaowCard(padding: 0) {
                    VStack(spacing: 12) {
                        infoRow(title: "Tipo", value: message.messageTypeRaw == "video" ? "Video" : "Fotografía")
                        Divider().background(MyaowColor.borderSubtle)
                        infoRow(title: "Tamaño", value: ByteCountFormatter.string(fromByteCount: Int64(message.mediaData?.count ?? 0), countStyle: .file))
                        Divider().background(MyaowColor.borderSubtle)
                        infoRow(title: "Enviado por", value: message.senderName)

                    }
                    .padding(16)
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
        }
        .presentationDetents([.fraction(0.45)])
    }
    
    private func infoRow(title: String, value: String, valueColor: Color = MyaowColor.textPrimary) -> some View {
        HStack {
            Text(title)
                .font(.myaowBody)
                .foregroundColor(MyaowColor.textSecondary)
            Spacer()
            Text(value)
                .font(.myaowBodyMedium)
                .foregroundColor(valueColor)
        }
    }
    
    private func saveToCameraRoll() {
        guard !saving else { return }
        saving = true
        Task { @MainActor in
            defer { saving = false }
            let permission = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard permission == .authorized || permission == .limited else {
                mediaError = "Permite guardar fotos y videos desde Ajustes > Myaow > Fotos."; return
            }
            do {
                let data = message.mediaData
                let url = videoURL
                let video = message.messageTypeRaw == "video"
                guard video ? url != nil : data.flatMap(UIImage.init(data:)) != nil else { throw URLError(.cannotDecodeContentData) }
                try await PHPhotoLibrary.shared().performChanges {
                    if video, let url { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                    else if let data, let image = UIImage(data: data) { PHAssetChangeRequest.creationRequestForAsset(from: image) }
                }
                isSavedToCameraRoll = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch { mediaError = "No se pudo guardar el archivo en Fotos. Inténtalo de nuevo." }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMMM yyyy, HH:mm"
        return formatter.string(from: date)
    }
}
