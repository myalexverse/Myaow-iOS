//
//  TuGenteEduBannerView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

/// Banner Educativo Cara a Cara con ilustración de 2 gatos y botón de descartar
public struct TuGenteEduBannerView: View {
    public var onHowItWorks: () -> Void
    public var onDismiss: () -> Void
    
    @State private var catBreathing: CGFloat = 1.0
    @State private var handshakePulse: CGFloat = 1.0
    
    public init(onHowItWorks: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onHowItWorks = onHowItWorks
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 16) {
                // Ilustración Vectorial: Dos gatos mirándose con apretón de manos 🤝 en el centro
                ZStack {
                    // Órbitas punteadas de conexión
                    Canvas { context, size in
                        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
                        var p1 = Path()
                        p1.addArc(center: center, radius: 36, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
                        context.stroke(p1, with: .color(MyaowColor.orange.opacity(0.3)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    }
                    .frame(width: 90, height: 75)
                    
                    HStack(spacing: -10) {
                        // Gato izquierdo
                        MyaowHeadSilhouetteShape()
                            .stroke(MyaowColor.orange, lineWidth: 1.6)
                            .frame(width: 40, height: 40)
                            .rotationEffect(.degrees(8))
                            .scaleEffect(catBreathing)
                        
                        // Handshake en medio
                        Text("🤝")
                            .font(.system(size: 16))
                            .scaleEffect(handshakePulse)
                            .shadow(color: MyaowColor.orange.opacity(0.5), radius: 4)
                        
                        // Gato derecho (espejado)
                        MyaowHeadSilhouetteShape()
                            .stroke(MyaowColor.orange, lineWidth: 1.6)
                            .frame(width: 40, height: 40)
                            .scaleEffect(x: -1, y: 1)
                            .rotationEffect(.degrees(-8))
                            .scaleEffect(catBreathing)
                    }
                }
                .frame(width: 85, height: 75)
                
                // Texto & CTA
                VStack(alignment: .leading, spacing: 5) {
                    Text("Conecta cara a cara")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Acerca tu iPhone al de la otra persona para conectar de forma segura y privada.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#8E8E93"))
                        .lineSpacing(1.5)
                    
                    Button(action: onHowItWorks) {
                        Text("Cómo funciona")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(hex: "#18181A"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
            
            // Botón de cerrar/descartar banner (para liberar espacio de pantalla)
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
                withAnimation(.easeInOut(duration: 0.25)) {
                    onDismiss()
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "#8E8E93"))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Circle())
                    .padding(10)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                catBreathing = 1.04
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                handshakePulse = 1.25
            }
        }
    }
}
