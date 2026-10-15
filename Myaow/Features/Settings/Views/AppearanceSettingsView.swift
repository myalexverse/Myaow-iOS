import SwiftUI

public struct AppearanceSettingsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var iconManager = AppIconManager.shared
    @State private var wallpaperManager = ChatWallpaperManager.shared
    @State private var showingWallpaperPicker = false
    @State private var showingLaunchAtmosphere = false
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    public init() {}
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                NavigationLink { AppAtmosphereSettingsView() } label: {
                    HStack(spacing: 16) {
                        Image("WallpaperLava").resizable().scaledToFill().frame(width: 66, height: 78).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AMBIENTE VIVO · LAB").font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(MyaowColor.orange)
                            Text("Dale vida a tu Myaow").font(.headline)
                            Text("Lava, luz o tu propio video.").font(.caption).foregroundStyle(MyaowColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption)
                    }.padding(16).background(AppAtmosphereStyle.card, in: RoundedRectangle(cornerRadius: 22))
                }.buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 8) {
                    Text("El mismo Myaow.\nA tu manera.").font(.system(size: 30, weight: .bold)).tracking(-0.7)
                    Text("Una colección de materiales y colores para tu pantalla de inicio. Nuestra mascota, siempre reconocible.")
                        .font(.system(size: 14)).foregroundStyle(MyaowColor.textSecondary)
                }
                activeIcon
                HStack {
                    Text("La colección").font(.system(size: 21, weight: .bold))
                    Spacer()
                    Text("9 acabados").font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(MyaowAppIconVariant.allCases.filter { $0 != .classic }) { variant in
                        iconCard(variant)
                    }
                }
                Button { iconManager.selectIcon(.classic) } label: {
                    HStack(spacing: 13) {
                        MyaowAppIconThumbnailView(variant: .classic, size: 46, cornerRadius: 11)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Myaow Clásico").font(.system(size: 14, weight: .semibold))
                            Text("El original, de siempre.").font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                        }
                        Spacer()
                        if iconManager.currentIcon == .classic {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(MyaowColor.orange)
                        } else {
                            Text("Restaurar").font(.system(size: 12, weight: .semibold)).foregroundStyle(MyaowColor.orange)
                        }
                    }.padding(14).background(MyaowColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).disabled(iconManager.pendingIcon != nil)
                Rectangle().fill(MyaowColor.borderSubtle).frame(height: 0.5)
                Button { showingWallpaperPicker = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.on.rectangle").font(.system(size: 21)).foregroundStyle(MyaowColor.orange)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Fondos de chat").font(.system(size: 16, weight: .semibold))
                            Text(wallpaperManager.currentWallpaper.rawValue).font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                    }.padding(.vertical, 5)
                }.buttonStyle(.plain)
            }.padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 36)
        }
        .background(AppAtmosphereStyle.page.ignoresSafeArea()).foregroundStyle(MyaowColor.textPrimary)
        .navigationTitle("Apariencia").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar).tint(MyaowColor.textPrimary)
        .toolbarBackground(AppAtmosphereStyle.bar, for: .navigationBar)
        .navigationDestination(isPresented: $showingLaunchAtmosphere) { AppAtmosphereSettingsView() }
         .onAppear {
            TabBarManager.shared.hide(); iconManager.refreshFromSystem()
            if DesignPreviewData.consumeLaunchRoute("--living-preview") { showingLaunchAtmosphere = true }
        }
        .onDisappear { TabBarManager.shared.show() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { iconManager.refreshFromSystem() } }
        .sheet(isPresented: $showingWallpaperPicker) { ChatWallpaperPickerView() }
        .alert("No se cambió el icono", isPresented: Binding(get: { iconManager.errorMessage != nil }, set: { if !$0 { iconManager.errorMessage = nil } })) {
            Button("Entendido", role: .cancel) { iconManager.errorMessage = nil }
        } message: { Text(iconManager.errorMessage ?? "Inténtalo de nuevo.") }
    }
    private var activeIcon: some View {
        HStack(spacing: 20) {
            MyaowAppIconThumbnailView(variant: iconManager.currentIcon, size: 88, cornerRadius: 21)
            VStack(alignment: .leading, spacing: 7) {
                Text(iconManager.pendingIcon == nil ? "ICONO EN USO" : "CAMBIANDO ICONO")
                    .font(.system(size: 9, weight: .bold)).tracking(1.4).foregroundStyle(MyaowColor.orange)
                Text(iconManager.currentIcon.title).font(.system(size: 22, weight: .semibold))
                Text(iconManager.currentIcon.subtitle).font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
                if iconManager.pendingIcon != nil { ProgressView().tint(MyaowColor.orange) }
            }
            Spacer(minLength: 0)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(MyaowColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 24))
    }
    private func iconCard(_ variant: MyaowAppIconVariant) -> some View {
        let selected = iconManager.currentIcon == variant
        return Button { iconManager.selectIcon(variant) } label: {
            VStack(spacing: 10) {
                MyaowAppIconThumbnailView(variant: variant, size: 76, cornerRadius: 18)
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 19)).foregroundStyle(MyaowColor.orange)
                                .background(MyaowColor.charcoal, in: Circle()).offset(x: 5, y: 5)
                        }
                    }
                Text(variant.title).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? MyaowColor.orange : MyaowColor.textPrimary)
            }.padding(.vertical, 15).frame(maxWidth: .infinity)
                .background(selected ? MyaowColor.orange.opacity(0.065) : MyaowColor.surfaceElevated.opacity(0.45), in: RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(selected ? MyaowColor.orange.opacity(0.5) : Color.white.opacity(0.04), lineWidth: 1))
        }.buttonStyle(.plain).disabled(iconManager.pendingIcon != nil)
            .accessibilityLabel("\(variant.title). \(variant.subtitle)")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
