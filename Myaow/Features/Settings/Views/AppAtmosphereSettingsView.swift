import SwiftUI
import PhotosUI

struct AppAtmosphereSettingsView: View {
    @State private var store = AppAtmosphereStore.shared
    @State private var pickedVideo: PhotosPickerItem?
    @State private var importTask: Task<Void, Never>?
    @State private var importing = false
    @State private var error: String?
    @State private var confirmRemoval = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack {
                    Label("AMBIENTE VIVO", systemImage: "sparkles").font(.system(size: 11, weight: .bold)).tracking(2)
                    Spacer()
                    Text("LAB").font(.caption2.weight(.bold)).padding(.horizontal, 9).padding(.vertical, 5).background(.white.opacity(0.1), in: Capsule())
                }.foregroundStyle(MyaowColor.orange)
                VStack(alignment: .leading, spacing: 12) {
                    Text("Tu mundo.\nEn movimiento.").font(.system(size: 38, weight: .semibold)).tracking(-1.5)
                    Text("Luz que fluye detrás de tus conversaciones. Tus gatos, tus colores, tu Myaow.")
                        .font(.system(size: 16)).foregroundStyle(MyaowColor.textSecondary)
                }
                HStack(spacing: 16) {
                    MyaowCatView(state: .cool, style: .orangeOnTransparent, size: 72, isInteractive: false)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Así se siente aquí.").font(.headline)
                        Text("El fondo cambia. Tú sigues al frente.").font(.subheadline).foregroundStyle(MyaowColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }.padding(18).background(AppAtmosphereStyle.card, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.12), lineWidth: 0.5))
                Text("Elige una atmósfera").font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(AppAtmosphere.allCases.filter { $0 != .custom }) { atmosphere in
                        Button { store.selection = atmosphere } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let resource = atmosphere.resource {
                                    Color.clear.overlay { Image(resource).resizable().scaledToFill() }.clipped()
                                }
                                else { MyaowColor.charcoal }
                                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                                HStack {
                                    Text(atmosphere.title).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if store.selection == atmosphere { Image(systemName: "checkmark.circle.fill").foregroundStyle(MyaowColor.orange) }
                                }.padding(14)
                            }.frame(height: 140).frame(maxWidth: .infinity).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                                .overlay(RoundedRectangle(cornerRadius: 20).stroke(store.selection == atmosphere ? MyaowColor.orange : .white.opacity(0.12), lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel(atmosphere.title).accessibilityAddTraits(store.selection == atmosphere ? .isSelected : [])
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    PhotosPicker(selection: $pickedVideo, matching: .videos) {
                        HStack {
                            Image(systemName: "video.badge.plus").font(.title2).foregroundStyle(MyaowColor.orange)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Trae tu propio video").font(.headline)
                                Text("12 segundos. Sin sonido. Solo para ti.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "plus")
                        }
                    }.disabled(importing)
                    if importing {
                        HStack { ProgressView(); Text("Preparando tu ambiente…").font(.subheadline); Spacer(); Button("Cancelar") { importTask?.cancel() } }
                    }
                    if store.customURL != nil {
                        HStack {
                            Button { store.selection = .custom } label: { Label("Usar mi video", systemImage: store.selection == .custom ? "checkmark.circle.fill" : "play.circle") }
                            Spacer()
                            Button("Eliminar", role: .destructive) { confirmRemoval = true }
                        }.font(.subheadline.weight(.medium))
                    }
                }.padding(18).background(AppAtmosphereStyle.card, in: RoundedRectangle(cornerRadius: 22))
                if store.isEnabled {
                    VStack(alignment: .leading, spacing: 18) {
                        Toggle("Movimiento", isOn: $store.motion).tint(MyaowColor.orange)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { Text("Oscurecer el fondo"); Spacer(); Text("\(Int(store.effectiveShade * 100)) %").monospacedDigit().foregroundStyle(MyaowColor.textSecondary) }
                            Slider(value: Binding(get: { store.effectiveShade }, set: { store.shade = $0 }), in: store.minimumShade...0.9).tint(MyaowColor.orange).accessibilityLabel("Oscurecer el fondo")
                        }.font(.subheadline)
                        if store.selection == .custom {
                            Text("Tu video mantiene una sombra suave para que los textos siempre destaquen.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        }
                        Text(reduceMotion ? "Reducir movimiento está activo: verás una imagen fija." : "Se pausa con ahorro de batería, al salir de la app y durante llamadas o Radio.")
                            .font(.caption).foregroundStyle(MyaowColor.textSecondary)
                    }.padding(18).background(AppAtmosphereStyle.card, in: RoundedRectangle(cornerRadius: 22))
                }
                Label("Solo cambia tu app. Tu video se guarda en este iPhone y no se comparte con tus contactos.", systemImage: "lock")
                    .font(.caption).foregroundStyle(MyaowColor.textSecondary)
                Text("Versión de prueba · Se aplica a las cinco secciones y sus conversaciones. Puedes volver a Clásico cuando quieras.")
                    .font(.caption).foregroundStyle(MyaowColor.textSecondary)
            }.padding(22).padding(.bottom, 24)
        }
        .background(AppAtmosphereStyle.page)
            .containerBackground(AppAtmosphereStyle.page, for: .navigation).foregroundStyle(MyaowColor.textPrimary)
        .navigationTitle("Ambiente vivo").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(AppAtmosphereStyle.bar, for: .navigationBar)
        .onAppear { TabBarManager.shared.hide() }
        .onDisappear { importTask?.cancel() }
        .onChange(of: pickedVideo) { _, item in
            guard let item else { return }
            importTask?.cancel()
            importing = true
            importTask = Task {
                defer { importing = false; pickedVideo = nil }
                do {
                    guard let imported = try await item.loadTransferable(type: ImportedAtmosphereVideo.self) else { throw AtmosphereVideoError.unreadable }
                    defer { try? FileManager.default.removeItem(at: imported.url) }
                    let prepared = try await AtmosphereVideoImport.prepare(source: imported.url, directory: AppAtmosphereStore.directory)
                    guard !Task.isCancelled else { prepared.discard(); return }
                    store.install(prepared)
                } catch is CancellationError { }
                catch { if !Task.isCancelled { self.error = error.localizedDescription } }
            }
        }
        .alert("No pudimos cambiar el fondo", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Entendido", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .confirmationDialog("¿Eliminar tu video de fondo?", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("Eliminar copia de Myaow", role: .destructive) { store.removeCustomVideo() }
        } message: { Text("El video original de Fotos se conserva.") }
    }
}
