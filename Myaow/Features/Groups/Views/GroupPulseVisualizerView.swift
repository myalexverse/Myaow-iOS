//
//  GroupPulseVisualizerView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct GroupPulseVisualizerView: View {
    public let space: GroupSpaceModel
    
    @State private var wavePhase: CGFloat = 0
    @State private var pulseGlow: CGFloat = 1.0
    
    public init(space: GroupSpaceModel) {
        self.space = space
    }
    
    public var body: some View {
        VStack(spacing: 10) {
            // Header del Pulso
            HStack {
                Text("Pulso del grupo")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: "#8E8E93"))
                
                Spacer()
                
                HStack(spacing: 5) {
                    Circle()
                        .fill(space.isMeshActive ? MyaowColor.statusGreen : MyaowColor.orange)
                        .frame(width: 7, height: 7)
                        .scaleEffect(pulseGlow)
                    
                    Text("\(space.connectedCount) conectados · \(space.isMeshActive ? "Mesh activa" : "Internet")")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(space.isMeshActive ? MyaowColor.statusGreen : Color(hex: "#8E8E93"))
                }
            }
            
            // Fila de Mini-Gatos con Estados Emocionales del Grupo
            HStack(spacing: 8) {
                if !space.members.isEmpty {
                    ForEach(space.members.prefix(5)) { member in
                        VStack(spacing: 3) {
                            MyaowCatView(
                                state: member.catState,
                                style: .darkOnOrange,
                                size: 36,
                                isInteractive: false
                            )
                            
                            Text(member.moodEmoji)
                                .font(.system(size: 12))
                        }
                    }
                } else {
                    // Fallback visual con 4 gatitos en diferentes estados
                    ForEach([MyaowCatState.happy, .purring, .calm, .party], id: \.self) { st in
                        MyaowCatView(
                            state: st,
                            style: .darkOnOrange,
                            size: 36,
                            isInteractive: false
                        )
                    }
                }
                
                Spacer(minLength: 0)
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(space.pulseStatusText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.trailing)
                    
                    Text("Sentimiento colectivo")
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#8E8E93"))
                }
            }
            
            // Onda Sinusoidal de Pulso Cálido
            Canvas { context, size in
                var path = Path()
                let midY = size.height * 0.5
                path.move(to: CGPoint(x: 0, y: midY))
                
                let step: CGFloat = 4
                for x in stride(from: 0, to: size.width, by: step) {
                    let relativeX = x / size.width
                    let sine = sin(relativeX * 4 * .pi + wavePhase)
                    let y = midY + sine * 4
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [MyaowColor.orange.opacity(0.1), MyaowColor.orange, MyaowColor.orange.opacity(0.1)]),
                        startPoint: CGPoint(x: 0, y: midY),
                        endPoint: CGPoint(x: size.width, y: midY)
                    ),
                    lineWidth: 1.8
                )
            }
            .frame(height: 14)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "#18181A"))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                wavePhase = .pi * 2
            }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulseGlow = 1.3
            }
        }
    }
}
