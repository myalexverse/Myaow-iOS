import SwiftUI
import PhotosUI

public struct ChatWallpaperPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var manager = ChatWallpaperManager.shared
    @State private var selection: ChatWallpaperType
    @State private var dimming: Double
    @State private var blur: CGFloat
    @State private var motion: Bool
    @State private var customData: Data?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var photoError: String?
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

    public init() {
        let saved = ChatWallpaperManager.shared
        _selection = State(initialValue: saved.currentWallpaper)
        _dimming = State(initialValue: saved.dimmingOpacity)
        _blur = State(initialValue: saved.blurRadius)
        _motion = State(initialValue: saved.motionEnabled)
        _customData = State(initialValue: saved.customImageData)
    }

    public var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dale otra atmósfera.").font(.system(size: 29, weight: .semibold)).tracking(-1)
                        Text("El mismo chat. Otra forma de sentirlo.")
                            .font(.system(size: 14)).foregroundStyle(MyaowColor.textSecondary)
                    }.padding(.horizontal, 24)
                    preview.padding(.horizontal, 24)
                    videoCollection
                    stillCollection
                    controls.padding(.horizontal, 24)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: 14) {
                            Image(systemName: "photo.on.rectangle").font(.system(size: 22, weight: .light)).foregroundStyle(MyaowColor.orange)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tu propia foto").font(.system(size: 15, weight: .semibold))
                                Text(loadingPhoto ? "Preparando imagen…" : "Un lugar, un recuerdo, algo tuyo.")
                                    .font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                            }
                            Spacer()
                            if loadingPhoto { ProgressView() }
                            else { Image(systemName: "plus").foregroundStyle(MyaowColor.orange) }
                        }.padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain).disabled(loadingPhoto).padding(.horizontal, 24)
                }.padding(.top, 18).padding(.bottom, 28)
            }
                Button(action: apply) {
                    HStack {
                        Text("Aplicar fondo").font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold))
                    }.padding(.horizontal, 22).frame(height: 52)
                        .foregroundStyle(.black).background(MyaowColor.orange, in: Capsule())
                }.disabled(loadingPhoto).padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 14)
                    .background(MyaowColor.charcoal)
          }
          .background(MyaowColor.charcoal)
          .navigationTitle("Fondos de chat").navigationBarTitleDisplayMode(.inline)
          .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                  Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)) }
                      .accessibilityLabel("Cerrar sin aplicar el fondo")
              }
          }
        }
        .tint(MyaowColor.orange)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            loadingPhoto = true
            defer { loadingPhoto = false }
            do {
                guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadCorruptFile) }
                let prepared = try await Task.detached(priority: .userInitiated) { try ProfilePhotoCrop.prepare(data) }.value
                try Task.checkCancellation()
                customData = prepared; selection = .customPhoto
            } catch { if !Task.isCancelled { photoError = "No pudimos abrir esa imagen. Prueba con otra foto." } }
        }
        .alert("No pudimos abrir la foto", isPresented: Binding(get: { photoError != nil }, set: { if !$0 { photoError = nil } })) {
            Button("Entendido", role: .cancel) { photoError = nil }
        } message: { Text(photoError ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    private var preview: some View {
        ZStack(alignment: .topLeading) {
            ChatWallpaperView(type: selection, dimming: dimming, blur: blur, customImageData: customData, motionEnabled: motion)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(MyaowColor.orange).frame(width: 6, height: 6)
                    Text("VISTA PREVIA").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.6)
                    Spacer()
                    if selection.videoResource != nil {
                        Image(systemName: motion && !reduceMotion && !lowPower ? "play.fill" : "pause.fill")
                            .font(.system(size: 10)).accessibilityLabel(motion && !reduceMotion && !lowPower ? "Fondo en movimiento" : "Fondo quieto")
                    }
                }.foregroundStyle(.white.opacity(0.8))
                Spacer()
                bubble("¿Nos vemos al rato?", outgoing: false)
                bubble("Sí. Tengo algo que contarte.", outgoing: true).padding(.top, 12)
                Spacer()
                VStack(alignment: .leading, spacing: 7) {
                    Text(selection.rawValue).font(.system(size: 27, weight: .semibold)).tracking(-0.7)
                    Text(selection.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                }
            }.padding(22)
        }
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.white.opacity(0.09)))
    }

    private func bubble(_ text: String, outgoing: Bool) -> some View {
        HStack {
            if outgoing { Spacer(minLength: 25) }
            Text(text).font(.system(size: 13, weight: .medium))
                .foregroundStyle(outgoing ? Color.black : Color.white)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(outgoing ? MyaowColor.orange : Color(hex: "#28292D"), in: RoundedRectangle(cornerRadius: 16))
            if !outgoing { Spacer(minLength: 25) }
        }
    }

    private var videoCollection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("EN MOVIMIENTO", detail: "3 videos · sin sonido").padding(.horizontal, 24)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ChatWallpaperType.videos) { type in
                        Button { choose(type) } label: { card(type, width: 136, height: 196) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(type.rawValue), fondo de video. \(type.subtitle)")
                            .accessibilityAddTraits(selection == type ? .isSelected : [])
                    }
                }.padding(.horizontal, 24)
            }
            Text("Loops de luz y textura, creados para Myaow.")
                .font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary).padding(.horizontal, 24)
        }
    }

    private var stillCollection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("EN CALMA", detail: "Tus fondos de siempre")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ChatWallpaperType.stills) { type in
                    Button { choose(type) } label: { card(type, width: nil, height: 104) }
                        .buttonStyle(.plain).accessibilityLabel(type.rawValue)
                        .accessibilityAddTraits(selection == type ? .isSelected : [])
                }
            }
        }.padding(.horizontal, 24)
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.8)
            Text(detail).font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
        }
    }

    private func card(_ type: ChatWallpaperType, width: CGFloat?, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                ChatWallpaperView(type: type, allowsMotion: false, dimming: type.videoResource == nil ? 0.15 : 0.05)
                    .frame(height: height).clipped()
                if type.videoResource != nil {
                    Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(.white)
                        .frame(width: 26, height: 26).background(.black.opacity(0.45), in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(10)
                }
                if selection == type {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 19))
                        .foregroundStyle(MyaowColor.orange).background(.black, in: Circle()).padding(9)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selection == type ? MyaowColor.orange : Color.white.opacity(0.08), lineWidth: selection == type ? 2 : 1))
            Text(type.shortTitle).font(.system(size: 12, weight: selection == type ? .semibold : .regular))
                .foregroundStyle(selection == type ? MyaowColor.textPrimary : MyaowColor.textSecondary)
                .lineLimit(2).frame(minHeight: 30, alignment: .topLeading)
        }.frame(width: width)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 20) {
            if selection.videoResource != nil {
                Toggle(isOn: $motion) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Movimiento").font(.system(size: 15, weight: .semibold))
                        Text(reduceMotion ? "Pausado por Reducir movimiento." : lowPower ? "Pausado por ahorro de batería." : motion ? "Suave, continuo y sin sonido." : "Vista quieta del mismo fondo.")
                            .font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                    }
                }
                Divider().overlay(MyaowColor.borderSubtle)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Oscurecer fondo").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(Int(dimming * 100)) %").font(.system(size: 12, design: .monospaced)).foregroundStyle(MyaowColor.textSecondary)
                }
                Slider(value: $dimming, in: 0.1...0.75, step: 0.05).accessibilityLabel("Oscurecer fondo")
            }
            if selection == .customPhoto {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Desenfoque").font(.system(size: 15, weight: .semibold))
                    Slider(value: $blur, in: 0...30, step: 2).accessibilityLabel("Desenfoque del fondo")
                }
            }
        }.padding(18).background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func choose(_ type: ChatWallpaperType) {
        if selection.videoResource == nil && type.videoResource != nil { dimming = min(dimming, 0.3) }
        selection = type
        UISelectionFeedbackGenerator().selectionChanged()
    }
    private func apply() {
        manager.customImageData = customData
        manager.blurRadius = blur
        manager.dimmingOpacity = dimming
        manager.motionEnabled = motion
        manager.currentWallpaper = selection
        dismiss()
    }
}
