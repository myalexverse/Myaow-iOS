//
//  CalmMascotNetworkBanner.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

/// Banner Calm Tech de la Mascota y Red Mesh: "Tu red te mantiene conectado"
public struct CalmMascotNetworkBanner: View {
    public var nodeCount: Int = 8
    public var onTap: (() -> Void)? = nil
    
    @State private var nodePulse: CGFloat = 1.0
    @State private var catBreathing: CGFloat = 1.0
    
    public init(nodeCount: Int = 8, onTap: (() -> Void)? = nil) {
        self.nodeCount = nodeCount
        self.onTap = onTap
    }
    
    public var body: some View {
        Button(action: {
            onTap?()
        }) {
            HStack(spacing: 16) {
                // Ilustración Vectorial: Gato descansando con constelación de nodos orbitales
                ZStack {
                    // Órbitas punteadas de nodos
                    Canvas { context, size in
                        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.55)
                        var p1 = Path()
                        p1.addArc(center: center, radius: 28, startAngle: .degrees(160), endAngle: .degrees(380), clockwise: false)
                        context.stroke(p1, with: .color(MyaowColor.orange.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        
                        var p2 = Path()
                        p2.addArc(center: center, radius: 42, startAngle: .degrees(140), endAngle: .degrees(400), clockwise: false)
                        context.stroke(p2, with: .color(MyaowColor.orange.opacity(0.2)), style: StrokeStyle(lineWidth: 1.0, dash: [4, 4]))
                    }
                    .frame(width: 90, height: 70)
                    
                    // Gato durmiendo descansando en outline naranja
                    SleepingCatOutlineShape()
                        .stroke(MyaowColor.orange, lineWidth: 1.8)
                        .frame(width: 58, height: 38)
                        .scaleEffect(catBreathing)
                        .shadow(color: MyaowColor.orange.opacity(0.3), radius: 6)
                    
                    // Nodos luminosos orbitando
                    ForEach(0..<4) { i in
                        let angle = Double(i) * (.pi / 2) + 0.3
                        Circle()
                            .fill(MyaowColor.orange)
                            .frame(width: 5, height: 5)
                            .scaleEffect(nodePulse)
                            .offset(x: 34 * cos(angle), y: 22 * sin(angle))
                            .shadow(color: MyaowColor.orange, radius: 4)
                    }
                }
                .frame(width: 85, height: 70)
                
                // Texto de Calidez y Privacidad
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tu red te mantiene\nconectado")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineSpacing(2)
                    
                    Text("Cuando hay alguien cerca,\nmyaow lo encuentra.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#8E8E93"))
                        .lineSpacing(1.5)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(hex: "#18181A"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                catBreathing = 1.04
            }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                nodePulse = 1.3
            }
        }
    }
}

/// Forma vectorial de gato acurrucado descansando
public struct SleepingCatOutlineShape: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        
        // Cuerpo curvado acurrucado
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.85))
        
        // Lomo curvado
        path.addCurve(
            to: CGPoint(x: w * 0.70, y: h * 0.40),
            control1: CGPoint(x: w * 0.15, y: h * 0.30),
            control2: CGPoint(x: w * 0.45, y: h * 0.20)
        )
        
        // Cabeza con oreja derecha
        path.addCurve(
            to: CGPoint(x: w * 0.82, y: h * 0.15),
            control1: CGPoint(x: w * 0.75, y: h * 0.35),
            control2: CGPoint(x: w * 0.78, y: h * 0.20)
        )
        // Punta oreja a base interior
        path.addCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.35),
            control1: CGPoint(x: w * 0.85, y: h * 0.15),
            control2: CGPoint(x: w * 0.88, y: h * 0.25)
        )
        // Oreja izquierda
        path.addCurve(
            to: CGPoint(x: w * 0.96, y: h * 0.22),
            control1: CGPoint(x: w * 0.92, y: h * 0.32),
            control2: CGPoint(x: w * 0.95, y: h * 0.25)
        )
        // Punta oreja a hocico
        path.addCurve(
            to: CGPoint(x: w * 0.88, y: h * 0.70),
            control1: CGPoint(x: w * 0.98, y: h * 0.40),
            control2: CGPoint(x: w * 0.95, y: h * 0.65)
        )
        
        // Patita delantera y curva de descanso
        path.addCurve(
            to: CGPoint(x: w * 0.60, y: h * 0.85),
            control1: CGPoint(x: w * 0.80, y: h * 0.75),
            control2: CGPoint(x: w * 0.70, y: h * 0.85)
        )
        
        // Cola curvada envolviendo el cuerpo
        path.addCurve(
            to: CGPoint(x: w * 0.15, y: h * 0.85),
            control1: CGPoint(x: w * 0.40, y: h * 0.85),
            control2: CGPoint(x: w * 0.25, y: h * 0.85)
        )
        
        return path
    }
}
