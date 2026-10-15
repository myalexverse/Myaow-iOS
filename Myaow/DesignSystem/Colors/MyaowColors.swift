//
//  MyaowColors.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum MyaowColor {
    /// Charcoal fondo principal (#101010)
    public static let charcoal = Color(hex: "0D0E10")
    
    /// Surface base para cards y contenedores (#1E1E1E)
    public static let surface = Color(hex: "191B1E")
    
    /// Surface elevada para elementos flotantes y burbujas (#242424)
    public static let surfaceElevated = Color(hex: "23262A")
    
    /// Surface secundaria (#2C2C2C / #3A3A3A)
    public static let surfaceSecondary = Color(hex: "2B2E32")
    public static let surfaceTertiary = Color(hex: "3A3A3A")
    
    /// Myaow Orange (#FF6A00) - Identidad, CTAs activos, mascota
    public static let orange = Color(hex: "FF6A00")
    public static let orangeLight = Color(hex: "FF8533")
    public static let orangeDark = Color(hex: "E05D00")
    public static let orangeSubtle = Color(hex: "FF6A00").opacity(0.15)
    
    /// Blancos y neutros de texto
    public static let white = Color.white
    public static let textPrimary = Color(hex: "F3F0E9")
    public static let textSecondary = Color(hex: "A8ADB5")
    public static let textTertiary = Color(hex: "7D848E")
    
    /// Indicadores de estado
    public static let statusGreen = Color(hex: "30D158")
    public static let statusOrange = Color(hex: "FF9500")
    public static let statusRed = Color(hex: "FF453A")
    public static let statusBlue = Color(hex: "0A84FF")
    
    /// Bordes sutiles
    public static let borderSubtle = Color.white.opacity(0.08)
    public static let borderFocus = Color(hex: "FF6A00").opacity(0.4)
    
    /// Unification colors
    public static let background = charcoal
    public static let cardBackground = surface
    public static let secondaryText = textSecondary
    public static let purple = Color(hex: "#AF52DE")
    public static let indigo = Color(hex: "#5E5CE6")
}

public extension Color {
    static let myaowCharcoal = MyaowColor.charcoal
    static let myaowSurface = MyaowColor.surface
    static let myaowSurfaceElevated = MyaowColor.surfaceElevated
    static let myaowSurfaceSecondary = MyaowColor.surfaceSecondary
    static let myaowOrange = MyaowColor.orange
    static let myaowOrangeLight = MyaowColor.orangeLight
    static let myaowTextPrimary = MyaowColor.textPrimary
    static let myaowTextSecondary = MyaowColor.textSecondary
    static let myaowTextTertiary = MyaowColor.textTertiary
    static let myaowStatusGreen = MyaowColor.statusGreen
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
