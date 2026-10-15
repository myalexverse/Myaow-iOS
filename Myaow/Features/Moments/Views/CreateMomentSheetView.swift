//
//  CreateMomentSheetView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import PhotosUI
import SwiftData

public enum MomentContentType: String, CaseIterable, Identifiable {
    case emotion = "🐱 Mascota"
    case text = "💬 Nota"
    case photo = "📸 Foto"
    
    public var id: String { rawValue }
}

public struct CreateMomentSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var identityManager = IdentityManager.shared
    @State private var contentType: MomentContentType = .emotion
    @State private var captionText: String = ""
    @State private var selectedEmotion: MyaowCatState = .friendly
    @State private var selectedGradientIndex: Int = 0
    @State private var expiryHours: Int = 24
    
    // Photo selection
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var pickedImageData: Data? = nil
    
    public init() {}
    
    private let gradients: [[Color]] = [
        [Color(hex: "#FF6B00"), Color(hex: "#FF2D55")],
        [Color(hex: "#8A2387"), Color(hex: "#E94057"), Color(hex: "#F27121")],
        [Color(hex: "#1D2671"), Color(hex: "#C33764")],
        [Color(hex: "#0F2027"), Color(hex: "#203A43"), Color(hex: "#2C5364")],
        [Color(hex: "#11998E"), Color(hex: "#38EF7D")]
    ]
    
    public var body: some View {
        NavigationStack {
            ZStack {
                MyaowColor.charcoal
                    .ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // 1. Selector de Tipo de Momento
                    Picker("Tipo", selection: $contentType) {
                        ForEach(MomentContentType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    // 2. Lienzo de Previsualización del Momento
                    ZStack {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: gradients[selectedGradientIndex % gradients.count],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 24, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        
                        VStack(spacing: 16) {
                            switch contentType {
                            case .emotion:
                                MyaowCatView(
                                    state: selectedEmotion,
                                    style: .darkOnOrange,
                                    size: 88,
                                    isInteractive: true
                                )
                                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
                                
                                Text(selectedEmotion.displayName)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                                
                                if !captionText.isEmpty {
                                    Text("“\(captionText)”")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundColor(.white.opacity(0.9))
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 20)
                                }
                                
                            case .text:
                                VStack(spacing: 12) {
                                    Image(systemName: "quote.bubble.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Text(captionText.isEmpty ? "Escribe lo que sientes o piensas hoy..." : captionText)
                                        .font(.system(size: 20, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal, 24)
                                }
                                
                            case .photo:
                                if let data = pickedImageData, let uiImg = UIImage(data: data) {
                                    Image(uiImage: uiImg)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxHeight: 280)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                        .padding(8)
                                } else {
                                    PhotosPicker(selection: $photoItem, matching: .images) {
                                        VStack(spacing: 10) {
                                            Image(systemName: "photo.badge.plus")
                                                .font(.system(size: 44))
                                                .foregroundColor(.white)
                                            Text("Elegir foto de la galería")
                                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                    .frame(height: 280)
                    .padding(.horizontal, 20)
                    
                    // 3. Controles Específicos
                    if contentType == .emotion {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(MyaowCatState.allCases) { cat in
                                    let isSel = selectedEmotion == cat
                                    Button(action: {
                                        selectedEmotion = cat
                                    }) {
                                        VStack(spacing: 4) {
                                            MyaowCatView(state: cat, style: .darkOnOrange, size: 36, isInteractive: false)
                                            Text(cat.displayName)
                                                .font(.system(size: 9, weight: isSel ? .bold : .medium, design: .rounded))
                                                .foregroundColor(isSel ? MyaowColor.orange : MyaowColor.textSecondary)
                                        }
                                        .padding(6)
                                        .background(isSel ? MyaowColor.surfaceElevated : MyaowColor.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                    
                    // Selector de Fondo Gradiente
                    HStack(spacing: 10) {
                        ForEach(0..<gradients.count, id: \.self) { idx in
                            Circle()
                                .fill(LinearGradient(colors: gradients[idx], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedGradientIndex == idx ? 2.5 : 0)
                                )
                                .onTapGesture {
                                    selectedGradientIndex = idx
                                }
                        }
                    }
                    
                    // Campo de Texto de Comentario
                    TextField("Añadir un pensamiento o pie de foto...", text: $captionText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(MyaowColor.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 20)
                    
                    // Duración de la historia
                    HStack(spacing: 8) {
                        Text("Duración:")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(MyaowColor.textSecondary)
                        
                        ForEach([6, 12, 24], id: \.self) { hours in
                            Button("\(hours)h") {
                                expiryHours = hours
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(expiryHours == hours ? .white : MyaowColor.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(expiryHours == hours ? MyaowColor.orange : MyaowColor.surface)
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    // Botón Publicar Momento
                    Button(action: {
                        publishMoment()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Compartir Momento")
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MyaowColor.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: MyaowColor.orange.opacity(0.4), radius: 10, x: 0, y: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Nuevo Momento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        dismiss()
                    }
                    .foregroundColor(MyaowColor.orange)
                }
            }
            .onChange(of: photoItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            self.pickedImageData = data
                        }
                    }
                }
            }
            .onAppear {
                if let state = MyaowCatState(rawValue: identityManager.currentIdentity.avatarStateName) {
                    self.selectedEmotion = state
                }
            }
        }
    }
    
    private func publishMoment() {
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        
        let moment = MomentModel(
            authorMyaowId: identityManager.currentIdentity.myaowId,
            authorDisplayName: identityManager.currentIdentity.displayName,
            authorAvatarCatState: contentType == .emotion ? selectedEmotion.rawValue : identityManager.currentIdentity.avatarStateName,
            captionText: captionText,
            mediaData: contentType == .photo ? pickedImageData : nil,
            catEmotionRaw: selectedEmotion.rawValue,
            backgroundGradientIndex: selectedGradientIndex,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(Double(expiryHours) * 3600),
            isSeen: true,
            isMine: true
        )
        
        modelContext.insert(moment)
        try? modelContext.save()
        
        // Subir momento al servidor para distribución
        Task {
            var mediaUrl: String? = nil
            
            // Si tiene imagen, subirla primero
            if let imageData = moment.mediaData {
                if let result = await MediaUploadService.shared.uploadMedia(
                    data: imageData, filename: "moment_\(moment.id).jpg", contentType: "image/jpeg"
                ) {
                    mediaUrl = result.mediaUrl
                }
            }
            
            // Subir metadata del momento
            let host = OnlineMessagingService.shared.relayHost
                .replacingOccurrences(of: "ws://", with: "")
                .replacingOccurrences(of: "http://", with: "")
            guard let url = URL(string: "http://\(host)/api/v1/moments") else { return }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "id": moment.id,
                "authorId": moment.authorMyaowId,
                "authorName": moment.authorDisplayName,
                "authorAvatarState": moment.authorAvatarCatState,
                "caption": moment.captionText,
                "mediaUrl": mediaUrl ?? "",
                "catEmotion": moment.catEmotionRaw,
                "backgroundIndex": moment.backgroundGradientIndex,
                "expiresAt": ISO8601DateFormatter().string(from: moment.expiresAt)
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            let _ = try? await URLSession.shared.data(for: request)
            print("✅ [Moments] Momento subido al servidor")
        }
        
        dismiss()
    }
}
