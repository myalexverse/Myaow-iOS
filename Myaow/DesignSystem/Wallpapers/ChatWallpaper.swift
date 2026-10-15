//
//  ChatWallpaper.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import PhotosUI

public enum ChatWallpaperType: String, CaseIterable, Identifiable, Codable, Sendable {
    case myaowDoodles = "Patitas & Doodles"
    case amberGlow = "Atardecer Ámbar"
    case cosmicAurora = "Aurora Cósmica"
    case liquidCrystalTeal = "Océano Cristalino"
    case meshGrid = "Malla Cripto"
    case pureOledBlack = "Obsidiana OLED"
    case customPhoto = "Foto de Galería"
    case orbitVideo = "Órbita"
    case silkVideo = "Seda"
    case emberVideo = "Brasa"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .myaowDoodles: return "sparkles"
        case .amberGlow: return "sun.max.fill"
        case .cosmicAurora: return "moon.stars.fill"
        case .liquidCrystalTeal: return "waveform.path"
        case .meshGrid: return "grid"
        case .pureOledBlack: return "circle.fill"
        case .customPhoto: return "photo.fill"
        case .orbitVideo: return "circle.hexagongrid"
        case .silkVideo: return "water.waves"
        case .emberVideo: return "sparkles"
        }
    }
    public var videoResource: String? {
        switch self {
        case .orbitVideo: return "WallpaperOrbit"
        case .silkVideo: return "WallpaperSilk"
        case .emberVideo: return "WallpaperEmber"
        default: return nil
        }
    }
    public var shortTitle: String {
        switch self {
        case .myaowDoodles: return "Patitas"
        case .amberGlow: return "Ámbar"
        case .cosmicAurora: return "Aurora"
        case .liquidCrystalTeal: return "Océano"
        case .meshGrid: return "Malla"
        case .pureOledBlack: return "Obsidiana"
        default: return rawValue
        }
    }
    public var subtitle: String {
        switch self {
        case .orbitVideo: return "Luz en órbita. Negro profundo."
        case .silkVideo: return "Ondas de cobre, en calma."
        case .emberVideo: return "Pequeñas luces. Mucha atmósfera."
        default: return "Un fondo para hacerlo tuyo."
        }
    }
    public static var videos: [Self] { [.orbitVideo, .silkVideo, .emberVideo] }
    public static var stills: [Self] { allCases.filter { $0.videoResource == nil && $0 != .customPhoto } }

}

@MainActor
@Observable
public final class ChatWallpaperManager {
    public static let shared = ChatWallpaperManager()
    
    public var currentWallpaper: ChatWallpaperType {
        didSet {
            UserDefaults.standard.set(currentWallpaper.rawValue, forKey: "myaow_chat_wallpaper")
        }
    }
    
    public var motionEnabled: Bool {
        didSet { UserDefaults.standard.set(motionEnabled, forKey: "myaow_wallpaper_motion") }
    }

    public var blurRadius: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(blurRadius), forKey: "myaow_wallpaper_blur")
        }
    }
    
    public var dimmingOpacity: Double {
        didSet {
            UserDefaults.standard.set(dimmingOpacity, forKey: "myaow_wallpaper_dim")
        }
    }
    
    public var customImageData: Data? {
        didSet {
            if let data = customImageData {
                UserDefaults.standard.set(data, forKey: "myaow_wallpaper_custom_data")
            } else {
                UserDefaults.standard.removeObject(forKey: "myaow_wallpaper_custom_data")
            }
        }
    }
    
    private init() {
        self.motionEnabled = UserDefaults.standard.object(forKey: "myaow_wallpaper_motion") as? Bool ?? true
        if let raw = UserDefaults.standard.string(forKey: "myaow_chat_wallpaper"),
           let saved = ChatWallpaperType(rawValue: raw) {
            self.currentWallpaper = saved
        } else {
            self.currentWallpaper = .amberGlow
        }
        
        let savedBlur = UserDefaults.standard.double(forKey: "myaow_wallpaper_blur")
        self.blurRadius = UserDefaults.standard.object(forKey: "myaow_wallpaper_blur") != nil ? CGFloat(savedBlur) : 12.0
        
        let savedDim = UserDefaults.standard.double(forKey: "myaow_wallpaper_dim")
        self.dimmingOpacity = UserDefaults.standard.object(forKey: "myaow_wallpaper_dim") != nil ? savedDim : 0.50
        
        self.customImageData = UserDefaults.standard.data(forKey: "myaow_wallpaper_custom_data")
    }
}

/// Vista que renderiza el fondo de chat decorativo estilo Apple Liquid Glass con velo de protección de contraste
public struct ChatWallpaperView: View {
    public var explicitType: ChatWallpaperType?
    private var allowsMotion: Bool
    private var dimmingOverride: Double?
    private var blurOverride: CGFloat?
    private var customDataOverride: Data?
    private var motionOverride: Bool?
    @State private var manager = ChatWallpaperManager.shared
    
    public init(type: ChatWallpaperType? = nil, allowsMotion: Bool = true, dimming: Double? = nil,
                blur: CGFloat? = nil, customImageData: Data? = nil, motionEnabled: Bool? = nil) {
        self.explicitType = type
        self.allowsMotion = allowsMotion
        self.dimmingOverride = dimming
        self.blurOverride = blur
        self.customDataOverride = customImageData
        self.motionOverride = motionEnabled
    }
    private var dimming: Double { min(0.8, max(0, dimmingOverride ?? manager.dimmingOpacity)) }
    private var blur: CGFloat { min(30, max(0, blurOverride ?? manager.blurRadius)) }

    
    private var activeType: ChatWallpaperType {
        explicitType ?? manager.currentWallpaper
    }
    
    public var body: some View {
        if explicitType == nil && AppAtmosphereStore.shared.isEnabled {
            Color.clear
        } else {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            switch activeType {
            case .myaowDoodles:
                doodlesPatternView
                    .drawingGroup()
                
            case .amberGlow:
                amberGlowView
                
            case .cosmicAurora:
                cosmicAuroraView
                
            case .liquidCrystalTeal:
                liquidCrystalTealView
                
            case .meshGrid:
                meshGridPatternView
                    .drawingGroup()
                
            case .pureOledBlack:
                Color.black
                
            case .customPhoto:
                customPhotoView

            case .orbitVideo, .silkVideo, .emberVideo:
                if let resource = activeType.videoResource {
                    VideoWallpaperView(resource: resource, motionEnabled: allowsMotion && (motionOverride ?? manager.motionEnabled))
                        .id(resource)
                }
            }
            
            // Capa de atenuación y velo de contraste para legibilidad perfecta de la interfaz
            if activeType == .customPhoto || activeType.videoResource != nil {
                // Velo de gradiente obsidian: oscuro en barra superior y teclado, translúcido en centro
                LinearGradient(
                    colors: [
                        Color.black.opacity(min(0.95, max(0.55, dimming + 0.15))),
                        Color.black.opacity(dimming),
                        Color.black.opacity(min(0.95, max(0.60, dimming + 0.20)))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else if activeType != .pureOledBlack {
                Color.black.opacity(dimming)
                    .ignoresSafeArea()
            }
        }
        }
    }
    
    // MARK: - 1. Doodles Pattern
    private var doodlesPatternView: some View {
        Canvas { context, size in
            let stepX: CGFloat = 80
            let stepY: CGFloat = 80
            var rowIndex = 0
            
            for y in stride(from: 20, to: size.height + 40, by: stepY) {
                let offsetX = (rowIndex % 2 == 0) ? 0 : stepX / 2
                var colIndex = 0
                
                for x in stride(from: -20, to: size.width + 40, by: stepX) {
                    let point = CGPoint(x: x + offsetX, y: y)
                    let iconType = (rowIndex + colIndex) % 4
                    context.opacity = 0.06
                    
                    switch iconType {
                    case 0:
                        let rect = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
                        context.stroke(MyaowHeadSilhouetteShape().path(in: rect), with: .color(.white), lineWidth: 1.2)
                    case 1:
                        let rect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                        context.fill(Circle().path(in: rect), with: .color(MyaowColor.orange))
                    case 2:
                        let rect = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
                        context.stroke(RoundedRectangle(cornerRadius: 4).path(in: rect), with: .color(.white), lineWidth: 1.0)
                    default:
                        let r1 = CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)
                        let r2 = CGRect(x: point.x + 8, y: point.y + 4, width: 4, height: 4)
                        context.fill(Circle().path(in: r1), with: .color(.white))
                        context.fill(Circle().path(in: r2), with: .color(.white))
                    }
                    colIndex += 1
                }
                rowIndex += 1
            }
        }
    }
    
    // MARK: - 2. Amber Glow
    private var amberGlowView: some View {
        ZStack {
            RadialGradient(
                colors: [MyaowColor.orange.opacity(0.25), Color(hex: "#FF4500").opacity(0.12), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 500
            )
            
            RadialGradient(
                colors: [Color(hex: "#FF8A3D").opacity(0.18), Color.clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 450
            )
        }
    }
    
    // MARK: - 3. Cosmic Aurora
    private var cosmicAuroraView: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: "#7928CA").opacity(0.35), Color.clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 450
            )
            
            RadialGradient(
                colors: [MyaowColor.orange.opacity(0.22), Color.clear],
                center: .bottomTrailing,
                startRadius: 40,
                endRadius: 420
            )
        }
    }
    
    // MARK: - 4. Liquid Crystal Teal
    private var liquidCrystalTealView: some View {
        ZStack {
            RadialGradient(
                colors: [Color(hex: "#0070F3").opacity(0.28), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 480
            )
            RadialGradient(
                colors: [Color(hex: "#00DFD8").opacity(0.20), Color.clear],
                center: .bottomLeading,
                startRadius: 30,
                endRadius: 450
            )
        }
    }
    
    // MARK: - 5. Mesh Grid
    private var meshGridPatternView: some View {
        Canvas { context, size in
            let step: CGFloat = 32
            context.opacity = 0.045
            
            for x in stride(from: 0, to: size.width, by: step) {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(p, with: .color(.white), lineWidth: 0.5)
            }
            
            for y in stride(from: 0, to: size.height, by: step) {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(p, with: .color(.white), lineWidth: 0.5)
            }
        }
    }
    
    // MARK: - 6. Custom Photo View con Protección de Proporciones y Blur
    @ViewBuilder
    private var customPhotoView: some View {
        if let data = customDataOverride ?? manager.customImageData, let uiImage = UIImage(data: data) {
            GeometryReader { geo in
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .blur(radius: blur)
            }
            .ignoresSafeArea()
        } else {
            amberGlowView
        }
    }
}
