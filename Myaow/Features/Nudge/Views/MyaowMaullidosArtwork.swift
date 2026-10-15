//
//  MyaowMaullidosArtwork.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

/// Arte Vectorial Feline Indie para los Maullidos y Zumbidos
public struct MyaowMaullidoArtIconView: View {
    public let soundType: CatVocalSynthesizer.CatSoundType
    public var size: CGFloat = 46
    
    public var body: some View {
        ZStack {
            // Fondo Circular con borde sutil
            Circle()
                .fill(Color(hex: "#18181A"))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(badgeColor.opacity(0.4), lineWidth: 1.2)
                )
            
            // Ilustración Vectorial Indie según el Maullido
            switch soundType {
            case .classic:
                // Gato Amigable con ondas sonoras
                ZStack {
                    Circle()
                        .stroke(MyaowColor.orange.opacity(0.35), lineWidth: 1)
                        .frame(width: size * 0.88, height: size * 0.88)
                    
                    MyaowCatView(state: .friendly, style: .darkOnOrange, size: size * 0.62, isInteractive: false)
                }
                
            case .electric:
                // Gato Canchero con Gafas de Sol y Rayo
                ZStack {
                    MyaowCatView(state: .cool, style: .darkOnOrange, size: size * 0.64, isInteractive: false)
                    
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size * 0.32, weight: .black))
                        .foregroundColor(MyaowColor.orange)
                        .offset(x: size * 0.22, y: -size * 0.22)
                        .shadow(color: MyaowColor.orange.opacity(0.9), radius: 3)
                }
                
            case .purr:
                // Gato Enamorado / Ronroneo con Corazón
                ZStack {
                    MyaowCatView(state: .inLove, style: .darkOnOrange, size: size * 0.62, isInteractive: false)
                }
                
            case .melodic:
                // Gato Juguetón con Nota Musical
                ZStack {
                    MyaowCatView(state: .playful, style: .darkOnOrange, size: size * 0.62, isInteractive: false)
                    
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.28, weight: .bold))
                        .foregroundColor(MyaowColor.orange)
                        .offset(x: size * 0.24, y: -size * 0.20)
                }
                
            case .hiss:
                // Gato Ninja con Zarpazo
                ZStack {
                    MyaowCatView(state: .ninja, style: .darkOnOrange, size: size * 0.62, isInteractive: false)
                    
                    HStack(spacing: 2) {
                        ForEach(0..<3) { idx in
                            Capsule()
                                .fill(Color(hex: "FF3B30"))
                                .frame(width: 2, height: idx == 1 ? 12 : 9)
                                .rotationEffect(.degrees(25))
                        }
                    }
                    .offset(x: size * 0.22, y: size * 0.16)
                }
                
            case .kiss, .giggle, .party, .question, .sleepy, .echo, .mentada, .admiration:
                ZStack(alignment: .bottomTrailing) {
                    MyaowCatView(state: soundType.catState, style: .darkOnOrange, size: size * 0.68, isInteractive: false)
                    Image(systemName: soundType.effectSymbol).font(.system(size: size * 0.23, weight: .bold))
                        .foregroundStyle(MyaowColor.orange).offset(x: size * 0.05, y: size * 0.03)
                }
            case .lazy:
                // Gato Perezoso / Aburrido con Bostezo
                ZStack {
                    MyaowCatView(state: .bored, style: .darkOnOrange, size: size * 0.62, isInteractive: false)
                }
            }
        }
    }
    
    private var badgeColor: Color {
        switch soundType {
        case .classic: return MyaowColor.orange
        case .electric: return MyaowColor.orange
        case .purr: return Color(hex: "FF2D55")
        case .melodic: return Color(hex: "FF9500")
        case .hiss: return Color(hex: "FF3B30")
        case .lazy: return Color(hex: "8E8E93")
        case .kiss, .admiration: return Color(hex: "FF7799")
        case .giggle, .party, .question, .mentada: return MyaowColor.orange
        case .sleepy, .echo: return Color(hex: "A89BEA")
        }
    }
}
