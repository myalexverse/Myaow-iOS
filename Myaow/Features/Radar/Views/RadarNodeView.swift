//
//  RadarNodeView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct RadarNodeView: View {
    public let peer: MeshPeer
    public let onSelect: () -> Void
    
    @State private var isPulsing = false
    
    public var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            onSelect()
        }) {
            ZStack {
                // Anillo de pulso sutil
                Circle()
                    .stroke(MyaowColor.orange.opacity(0.3), lineWidth: 1)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                
                // Nodo
                Circle()
                    .fill(MyaowColor.surfaceElevated)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(MyaowColor.orange, lineWidth: 1.5)
                    )
                
                MyaowCatView(
                    state: .neutral,
                    style: .whiteOnTransparent,
                    size: 20
                )
            }
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: false).delay(Double.random(in: 0...1.5))) {
                isPulsing = true
            }
        }
    }
}
