import SwiftUI

enum AppAtmosphere: String, CaseIterable, Identifiable {
    case classic, lava, lavaViolet, lavaTeal, orbit, orbitBlue, silk, ember, water, waves, nebula, aurora, portal, grid, eclipse, titan, neonRain, binaryDunes, orbitalGarden, vertigo, silverScreen, deco, cosmicOpera, alienCrystal, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: "Clásico"
        case .lava: "Lava ámbar"
        case .orbit: "Órbita"
        case .silk: "Seda"
        case .lavaViolet: "Lava violeta"
        case .lavaTeal: "Lava turquesa"
        case .orbitBlue: "Órbita azul"
        case .ember: "Brasa"
        case .water: "Agua nocturna"
        case .waves: "Marea"
        case .nebula: "Nebulosa violeta"
        case .aurora: "Aurora ionizada"
        case .portal: "Portal ámbar"
        case .grid: "Retícula neón"
        case .eclipse: "Eclipse de cobre"
        case .titan: "Mar de Titán"
        case .neonRain: "Lluvia neón"
        case .binaryDunes: "Dunas binarias"
        case .orbitalGarden: "Jardín orbital"
        case .vertigo: "Vértigo"
        case .silverScreen: "Proyector nocturno"
        case .deco: "Palacio art déco"
        case .cosmicOpera: "Ópera cósmica"
        case .alienCrystal: "Cristal alienígena"
        case .custom: "Tu video"
        }
    }
    var resource: String? {
        switch self {
        case .lava: "WallpaperLava"
        case .orbit: "WallpaperOrbit"
        case .silk: "WallpaperSilk"
        case .lavaViolet: "WallpaperLavaViolet"
        case .lavaTeal: "WallpaperLavaTeal"
        case .orbitBlue: "WallpaperOrbitBlue"
        case .ember: "WallpaperEmber"
        case .water: "WallpaperWater"
        case .waves: "WallpaperWaves"
        case .nebula: "WallpaperNebula"
        case .aurora: "WallpaperAurora"
        case .portal: "WallpaperPortal"
        case .grid: "WallpaperGrid"
        case .eclipse: "WallpaperEclipse"
        case .titan: "WallpaperTitan"
        case .neonRain: "WallpaperNeonRain"
        case .binaryDunes: "WallpaperBinaryDunes"
        case .orbitalGarden: "WallpaperOrbitalGarden"
        case .vertigo: "WallpaperVertigo"
        case .silverScreen: "WallpaperSilverScreen"
        case .deco: "WallpaperDeco"
        case .cosmicOpera: "WallpaperCosmicOpera"
        case .alienCrystal: "WallpaperAlienCrystal"
        default: nil
        }
    }
}

@MainActor @Observable
final class AppAtmosphereStore {
    static let shared = AppAtmosphereStore()
    var selection: AppAtmosphere { didSet { UserDefaults.standard.set(selection.rawValue, forKey: "myaow_atmosphere") } }
    var motion: Bool { didSet { UserDefaults.standard.set(motion, forKey: "myaow_atmosphere_motion") } }
    var shade: Double { didSet { UserDefaults.standard.set(shade, forKey: "myaow_atmosphere_shade") } }
    private(set) var customID: String?
    var activeConversationID: String?
    var activeDecoration: ChatDecoration?
    var previewingDecoration = false
    var isEnabled: Bool { activeDecoration != nil || selection != .classic && (selection != .custom || customURL != nil) }
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("AppAtmosphere", isDirectory: true)
    }
    var customURL: URL? {
        guard let customID, UUID(uuidString: customID) != nil else { return nil }
        let url = Self.directory.appendingPathComponent(customID + ".mp4")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    var posterURL: URL? {
        guard customURL != nil, let customID else { return nil }
        return Self.directory.appendingPathComponent(customID + ".jpg")
    }
    var minimumShade: Double { selection == .custom && activeDecoration == nil ? 0.76 : 0.35 }
    var effectiveShade: Double { min(0.9, max(minimumShade, shade)) }
    // The root always owns the app atmosphere. A conversation owns its separate
    // layer inside the navigation destination; navigating never swaps this URL.
    var posterResource: String? { selection.resource }
    var videoURL: URL? {
        if selection == .custom { return customURL }
        return selection.resource.flatMap { Bundle.main.url(forResource: $0, withExtension: "mp4") }
    }
    var globalShade: Double { min(0.9, max(selection == .custom ? 0.76 : 0.35, shade)) }
    private init() {
        let defaults = UserDefaults.standard
        selection = AppAtmosphere(rawValue: defaults.string(forKey: "myaow_atmosphere") ?? "") ?? .classic
        motion = defaults.object(forKey: "myaow_atmosphere_motion") as? Bool ?? true
        shade = min(0.9, max(0.35, defaults.object(forKey: "myaow_atmosphere_shade") as? Double ?? 0.38))
        customID = defaults.string(forKey: "myaow_atmosphere_custom")
    }
    func install(_ prepared: PreparedAtmosphereVideo) {
        let oldID = customID
        customID = prepared.id
        UserDefaults.standard.set(prepared.id, forKey: "myaow_atmosphere_custom")
        selection = .custom
        if let oldID, oldID != prepared.id { removeFiles(id: oldID) }
    }
    func removeCustomVideo() {
        if selection == .custom { selection = .classic }
        if let customID { removeFiles(id: customID) }
        customID = nil
        UserDefaults.standard.removeObject(forKey: "myaow_atmosphere_custom")
    }
    private func removeFiles(id: String) {
        guard UUID(uuidString: id) != nil else { return }
        for ext in ["mp4", "jpg"] { try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(id + "." + ext)) }
    }
}

@MainActor enum AppAtmosphereStyle {
    static var page: Color { AppAtmosphereStore.shared.isEnabled ? .clear : MyaowColor.charcoal }
    static var card: Color { MyaowColor.surface.opacity(AppAtmosphereStore.shared.isEnabled ? 0.72 : 1) }
    static var bar: Color { MyaowColor.charcoal.opacity(AppAtmosphereStore.shared.isEnabled ? 0.82 : 1) }
}

/// A single layer behind the active section. Foreground controls remain native.
struct AppAtmosphereBackdrop: View {
    @State private var store = AppAtmosphereStore.shared
    var body: some View {
        ZStack {
            MyaowColor.charcoal
            if let url = store.videoURL {
                VideoWallpaperView(url: url, posterResource: store.posterResource, posterURL: store.selection == .custom ? store.posterURL : nil,
                    motionEnabled: store.motion && CallSessionService.shared.callState == .idle && !WalkieTalkieService.shared.transport.isActive,
                    playbackSuspended: store.activeDecoration != nil || store.previewingDecoration)
                Color.black.opacity(store.globalShade)
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
