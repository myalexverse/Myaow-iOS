//
//  MyaowNudgeThemesDeckView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum NudgeTheme: String, CaseIterable, Identifiable, Sendable {
    case electric = "Zarpazo Eléctrico"
    case clawSwipe = "Zarpazo Gatuno"
    case cosmicPurr = "Ronroneo Cósmico"
    case liquidSplash = "Miau Líquido"
    case ghostGaze = "Mirada de Medianoche"
    
    public var id: String { rawValue }
    
    public var subtitle: String {
        switch self {
        case .electric: return "Relámpago Myaow & Onda Eléctrica"
        case .clawSwipe: return "Zarpazo de Neón sobre el Cristal"
        case .cosmicPurr: return "Vibración Rítmica de Ronroneo"
        case .liquidSplash: return "Onda de Cristal Líquido y Salto"
        case .ghostGaze: return "Ojos Felinos en Modo Sigilo"
        }
    }
    
    public var description: String {
        switch self {
        case .electric: return "Sacudida física con ondas de choque y relámpago naranja ⚡️"
        case .clawSwipe: return "3 marcas de garra de neón rasgando el cristal 🐾"
        case .cosmicPurr: return "Resplandor cálido con vibración rítmica de ronroneo 💖"
        case .liquidSplash: return "Efecto de onda de cristal líquido sobre el chat 🌊"
        case .ghostGaze: return "Destello nocturno con mirada atenta de la mascota 👁️"
        }
    }
    
    public var badgeColor: Color {
        switch self {
        case .electric: return MyaowColor.orange
        case .clawSwipe: return Color(hex: "FF3B30")
        case .cosmicPurr: return Color(hex: "FF2D55")
        case .liquidSplash: return Color(hex: "007AFF")
        case .ghostGaze: return Color(hex: "AF52DE")
        }
    }
    
    public var gradientColors: [Color] {
        switch self {
        case .electric: return [Color(hex: "FF8533"), Color(hex: "E85100")]
        case .clawSwipe: return [Color(hex: "FF5247"), Color(hex: "D70015")]
        case .cosmicPurr: return [Color(hex: "FF4081"), Color(hex: "C2185B")]
        case .liquidSplash: return [Color(hex: "00B4D8"), Color(hex: "0077B6")]
        case .ghostGaze: return [Color(hex: "BF5AF2"), Color(hex: "5E5CE6")]
        }
    }
}

/// Arte Feline Original Vectorizado para Zumbidos Myaow (Adiós iconos genéricos)
public struct MyaowNudgeIconArtView: View {
    public let theme: NudgeTheme
    public var size: CGFloat = 44
    
    public var body: some View {
        ZStack {
            // Fondo con resplandor suave
            Circle()
                .fill(
                    LinearGradient(
                        colors: theme.gradientColors.map { $0.opacity(0.25) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(theme.badgeColor.opacity(0.5), lineWidth: 1.2)
                )
            
            // Arte de Ilustración Felina según temática
            switch theme {
            case .electric:
                // Silueta de orejas con rayo central estilizado
                ZStack {
                    MyaowHeadSilhouetteShape()
                        .fill(theme.badgeColor.opacity(0.35))
                        .frame(width: size * 0.65, height: size * 0.55)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.45, weight: .black))
                        .foregroundColor(theme.badgeColor)
                        .shadow(color: theme.badgeColor.opacity(0.8), radius: 4)
                }
                
            case .clawSwipe:
                // 3 Marcas de garras felinas diagonales
                HStack(spacing: size * 0.08) {
                    ForEach(0..<3) { idx in
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [theme.badgeColor, theme.badgeColor.opacity(0.4)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: size * 0.08, height: size * (idx == 1 ? 0.55 : 0.42))
                            .rotationEffect(.degrees(22))
                    }
                }
                .shadow(color: theme.badgeColor.opacity(0.7), radius: 3)
                
            case .cosmicPurr:
                // Cabeza de gato con ondas de ronroneo concéntricas
                ZStack {
                    Circle()
                        .stroke(theme.badgeColor.opacity(0.4), lineWidth: 1)
                        .frame(width: size * 0.72, height: size * 0.72)
                    
                    MyaowMaullidosMark(size: size * 0.48)
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundColor(theme.badgeColor)
                        .shadow(color: theme.badgeColor.opacity(0.8), radius: 5)
                }
                
            case .liquidSplash:
                // Gato nadador / Onda de agua cristalina
                ZStack {
                    Circle()
                        .stroke(theme.badgeColor.opacity(0.5), lineWidth: 1.5)
                        .frame(width: size * 0.7, height: size * 0.7)
                    
                    Image(systemName: "drop.fill")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundColor(theme.badgeColor)
                        .offset(y: -1)
                }
                
            case .ghostGaze:
                // Ojos felinos luminosos en la oscuridad
                HStack(spacing: size * 0.16) {
                    Ellipse()
                        .fill(theme.badgeColor)
                        .frame(width: size * 0.16, height: size * 0.28)
                        .rotationEffect(.degrees(-8))
                    
                    Ellipse()
                        .fill(theme.badgeColor)
                        .frame(width: size * 0.16, height: size * 0.28)
                        .rotationEffect(.degrees(8))
                }
                .shadow(color: theme.badgeColor.opacity(0.9), radius: 6)
            }
        }
    }
}

public struct MyaowNudgeThemesDeckView: View {
    @Environment(\.dismiss) private var dismiss
    public var onSelectTheme: (NudgeTheme) -> Void
    
    public init(onSelectTheme: @escaping (NudgeTheme) -> Void) {
        self.onSelectTheme = onSelectTheme
    }
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 18) {
                // Indicador de arrastre superior
                Capsule()
                    .fill(MyaowColor.surfaceSecondary)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                
                // Título con mascota
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        MyaowNudgeIconArtView(theme: .electric, size: 28)
                        Text("Zumbidos Myaow")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(MyaowColor.textPrimary)
                    }
                    
                    Text("Envía una sacudida física y visual en el cristal del chat.")
                        .font(.myaowMicro)
                        .foregroundColor(MyaowColor.textSecondary)
                }
                
                // Lista de Temáticas
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(NudgeTheme.allCases) { theme in
                            Button(action: {
                                dismiss()
                                onSelectTheme(theme)
                            }) {
                                HStack(spacing: 14) {
                                    MyaowNudgeIconArtView(theme: theme, size: 48)
                                    
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(theme.rawValue)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(MyaowColor.textPrimary)
                                        
                                        Text(theme.subtitle)
                                            .font(.system(size: 12, weight: .medium, design: .rounded))
                                            .foregroundColor(theme.badgeColor)
                                        
                                        Text(theme.description)
                                            .font(.system(size: 11, weight: .regular, design: .rounded))
                                            .foregroundColor(MyaowColor.textSecondary)
                                            .lineLimit(2)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(MyaowColor.textTertiary)
                                }
                                .padding(14)
                                .background(MyaowColor.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(MyaowColor.borderSubtle, lineWidth: 1)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .presentationDetents([.fraction(0.62), .medium])
    }
}
