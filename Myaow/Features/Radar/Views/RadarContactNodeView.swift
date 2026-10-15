//
//  RadarContactNodeView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct RadarContactNodeView: View {
    public let node: UniverseContactNode
    public var onTap: () -> Void
    
    @State private var pulseGlow: Bool = false
    
    public init(node: UniverseContactNode, onTap: @escaping () -> Void) {
        self.node = node
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            onTap()
        }) {
            VStack(spacing: 4) {
                // Avatar con Animación de Estado de Ánimo Viva
                ZStack(alignment: .bottomTrailing) {
                    // Resplandor pulsante si es Mesh local
                    if node.connectionType == .localMeshOffline {
                        Circle()
                            .stroke(MyaowColor.statusGreen.opacity(pulseGlow ? 0.4 : 0.05), lineWidth: 2)
                            .frame(width: 54, height: 54)
                            .scaleEffect(pulseGlow ? 1.25 : 0.95)
                    }
                    
                    // Mascota con su animación viva
                    MyaowCatView(
                        state: node.avatarState,
                        style: node.connectionType == .localMeshOffline ? .darkOnOrange : .orangeOnDark,
                        size: 46,
                        isInteractive: false
                    )
                    .shadow(color: node.connectionType.badgeColor.opacity(0.35), radius: 6)
                    
                    // Badge de tipo de conexión
                    Circle()
                        .fill(node.connectionType.badgeColor)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(MyaowColor.charcoal, lineWidth: 2))
                        .offset(x: 1, y: 1)
                }
                
                // Nombre del Contacto
                Text(node.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 80)
                
                // Estado de Ánimo escrito debajo del nombre
                Text(node.moodDescription)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundColor(MyaowColor.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.65).background(.ultraThinMaterial))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            if node.connectionType == .localMeshOffline {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulseGlow = true
                }
            }
        }
    }
}
