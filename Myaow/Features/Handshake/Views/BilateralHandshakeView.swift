//
//  BilateralHandshakeView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct BilateralHandshakeView: View {
    @Environment(\.dismiss) private var dismiss
    public var peerName: String = ""
    public var onHandshakeCompleted: (() -> Void)?
    
    @State private var isApproved: Bool = false
    @State private var connectionProgress: CGFloat = 0.0
    @State private var catApproachOffset: CGFloat = 16
    @State private var pulseScale: CGFloat = 1.0
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                HStack {
                    Spacer()
                    Text("Conectando...")
                        .font(.myaowHeadline)
                        .foregroundColor(MyaowColor.textPrimary)
                    Spacer()
                }
                .padding(.top, 24)
                
                Spacer()
                
                // Escenario Central de Handshake Bilateral
                ZStack {
                    Circle()
                        .fill(MyaowColor.surface)
                        .frame(width: 280, height: 280)
                    
                    // Línea de conexión punteada
                    Path { path in
                        path.move(to: CGPoint(x: 80, y: 140))
                        path.addLine(to: CGPoint(x: 200, y: 140))
                    }
                    .stroke(MyaowColor.orange.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    
                    // Gato 1 (Dispositivo local)
                    MyaowCatView(
                        state: isApproved ? .happy : .friendly,
                        style: .darkOnOrange,
                        size: 74
                    )
                    .offset(x: -catApproachOffset - 40, y: 0)
                    
                    // Gato 2 (Dispositivo par)
                    MyaowCatView(
                        state: isApproved ? .happy : .friendly,
                        style: .orangeOnDark,
                        size: 74
                    )
                    .offset(x: catApproachOffset + 40, y: 0)
                    
                    // Badge central de verificación
                    ZStack {
                        Circle()
                            .fill(MyaowColor.surfaceElevated)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle().stroke(MyaowColor.orange, lineWidth: 1.5)
                            )
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(isApproved ? MyaowColor.statusGreen : MyaowColor.orange)
                    }
                    .scaleEffect(pulseScale)
                }
                
                // Explicación tranquila del Handshake
                VStack(spacing: 8) {
                    Text("Handshake bilateral")
                        .font(.myaowTitle)
                        .foregroundColor(MyaowColor.textPrimary)
                    
                    Text("Ambos dispositivos deben aprobar la conexión para poder chatear de forma segura.")
                        .font(.myaowBody)
                        .multilineTextAlignment(.center)
                        .foregroundColor(MyaowColor.textSecondary)
                        .padding(.horizontal, 32)
                }
                
                Spacer()
                
                // Botones de Aprobación / Cancelar
                VStack(spacing: 12) {
                    if !isApproved {
                        MyaowPillButton("Aprobar Conexión", icon: "lock.shield.fill", style: .primary, isFullWidth: true) {
                            approveHandshake()
                        }
                    }
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Text(isApproved ? "Listo" : "Cancelar")
                            .font(.myaowCallout)
                            .foregroundColor(isApproved ? MyaowColor.orange : MyaowColor.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseScale = 1.15
            }
        }
    }
    
    private func approveHandshake() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            catApproachOffset = 6
            isApproved = true
        }
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            await MainActor.run {
                onHandshakeCompleted?()
                dismiss()
            }
        }
    }
}

#Preview {
    BilateralHandshakeView()
}
