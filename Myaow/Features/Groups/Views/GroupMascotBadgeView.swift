//
//  GroupMascotBadgeView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

/// Avatar oficial de grupo que viste al Myaow Cat con la personalidad del espacio
public struct GroupMascotBadgeView: View {
    public let category: SpaceCategory
    public var size: CGFloat = 56
    
    public init(category: SpaceCategory, size: CGFloat = 56) {
        self.category = category
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            // Fondo circular con gradiente cálido
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#2C2018"), Color(hex: "#161618")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle().stroke(MyaowColor.orange.opacity(0.3), lineWidth: 1.2)
                )
            
            // Mascota Myaow Base
            MyaowCatView(
                state: .friendly,
                style: .darkOnOrange,
                size: size * 0.72,
                isInteractive: false
            )
            
            // Accesorio Minimalista Vectorial según la Categoría
            accessoryOverlay
        }
        .frame(width: size, height: size)
    }
    
    @ViewBuilder
    private var accessoryOverlay: some View {
        switch category {
        case .party:
            // Gorro de fiesta / celebración
            VStack {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundColor(MyaowColor.orange)
                    .offset(x: size * 0.24, y: -size * 0.22)
                Spacer()
            }
        case .trip:
            // Tienda de campamento
            VStack {
                Image(systemName: "tent.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundColor(MyaowColor.statusGreen)
                    .offset(x: size * 0.24, y: -size * 0.22)
                Spacer()
            }
        case .workshop:
            // Escudo de taller
            VStack {
                Image(systemName: "shield.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundColor(Color(hex: "#FFCC00"))
                    .offset(x: size * 0.24, y: -size * 0.22)
                Spacer()
            }
        case .design:
            // Paleta de diseño
            VStack {
                Image(systemName: "paintpalette.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundColor(MyaowColor.orange)
                    .offset(x: size * 0.24, y: -size * 0.22)
                Spacer()
            }
        case .family:
            // Corazón familiar
            VStack {
                Image(systemName: "heart.fill")
                    .font(.system(size: size * 0.22, weight: .bold))
                    .foregroundColor(Color(hex: "#FF2D55"))
                    .offset(x: size * 0.24, y: -size * 0.22)
                Spacer()
            }
        case .general:
            EmptyView()
        }
    }
}
