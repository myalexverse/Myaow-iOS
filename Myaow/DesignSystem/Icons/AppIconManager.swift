//
//  AppIconManager.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import UIKit

public enum MyaowAppIconVariant: String, CaseIterable, Identifiable, Sendable {
    case classic = "classic"         // 🟠 Clásico Original
    case oledNoir = "oledNoir"       // 🕶️ Negro
    case cyberNeon = "cyberNeon"     // ⚡️ Neón
    case furryPeluche = "furry"      // 🧶 Peluche & Pelo
    case liquidGlass = "liquidGlass" // 🧊 Glaciar
    case pixelRetro = "pixel8bit"    // 👾 Arcade
    case holoSpace = "holoSpace"     // 🛸 Aurora
    case matchaPastel = "matcha"     // 🍵 Matcha
    case magmaCore = "magma"         // 🌋 Magma Ardiente
    case imperialGold = "gold"       // ✨ Oro
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .classic: return "Myaow Clásico"
        case .oledNoir: return "Negro"
        case .cyberNeon: return "Neón"
        case .furryPeluche: return "Terra"
        case .liquidGlass: return "Glaciar"
        case .pixelRetro: return "Arcade"
        case .holoSpace: return "Aurora"
        case .matchaPastel: return "Matcha"
        case .magmaCore: return "Cobre"
        case .imperialGold: return "Oro"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .classic: return "Naranja cálido sobre carbón mate"
        case .oledNoir: return "Grafito profundo y un acento ámbar"
        case .cyberNeon: return "Violeta nocturno y menta luminosa"
        case .furryPeluche: return "Arcilla cálida y acabado mate"
        case .liquidGlass: return "Azul mineral y reflejos de cristal"
        case .pixelRetro: return "La misma mascota, dibujada en píxeles"
        case .holoSpace: return "Reflejos suaves de jade y lavanda"
        case .matchaPastel: return "Verde salvia y crema natural"
        case .magmaCore: return "Metal cobrizo sobre carbón"
        case .imperialGold: return "Oro satinado y negro mineral"
        }
    }
    
    public var badgeEmoji: String {
        switch self {
        case .classic: return "🟠"
        case .oledNoir: return "🕶️"
        case .cyberNeon: return "⚡️"
        case .furryPeluche: return "🧶"
        case .liquidGlass: return "🧊"
        case .pixelRetro: return "👾"
        case .holoSpace: return "🛸"
        case .matchaPastel: return "🍵"
        case .magmaCore: return "🌋"
        case .imperialGold: return "✨"
        }
    }
}

@MainActor
@Observable
public final class AppIconManager {
    public static let shared = AppIconManager()
    public private(set) var currentIcon: MyaowAppIconVariant
    public private(set) var pendingIcon: MyaowAppIconVariant?
    public var errorMessage: String?

    private init() {
        currentIcon = Self.systemVariant()
    }
    private static func systemVariant() -> MyaowAppIconVariant {
        guard let name = UIApplication.shared.alternateIconName,
              name.hasPrefix("AppIcon_"),
              let variant = MyaowAppIconVariant(rawValue: String(name.dropFirst(8))) else { return .classic }
        return variant
    }
    public func refreshFromSystem() {
        guard pendingIcon == nil else { return }
        currentIcon = Self.systemVariant()
    }
    public func selectIcon(_ variant: MyaowAppIconVariant) {
        guard pendingIcon == nil else { return }
        refreshFromSystem()
        guard variant != currentIcon else { return }
        guard UIApplication.shared.supportsAlternateIcons else {
            errorMessage = "Este dispositivo no permite cambiar el icono de la app."; return
        }
        errorMessage = nil; pendingIcon = variant
        let name = variant == .classic ? nil : "AppIcon_\(variant.rawValue)"
        UIApplication.shared.setAlternateIconName(name) { [weak self] error in
            let message = error?.localizedDescription
            guard let self else { return }
            Task { @MainActor in
                self.pendingIcon = nil
                self.currentIcon = Self.systemVariant()
                if let message {
                    self.errorMessage = "No pudimos cambiar el icono. \(message)"
                } else if self.currentIcon == variant {
                    UserDefaults.standard.set(variant.rawValue, forKey: "myaow_selected_app_icon")
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } else {
                    self.errorMessage = "iOS no confirmó el cambio. Vuelve a intentarlo."
                }
            }
        }
    }
}
