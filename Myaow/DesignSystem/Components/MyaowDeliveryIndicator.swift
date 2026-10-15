//
//  MyaowDeliveryIndicator.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct MyaowDeliveryStatusIndicator: View {
    public let status: MessageDeliveryStatus
    public let isSender: Bool
    
    @State private var isSpinning: Bool = false
    
    public init(status: MessageDeliveryStatus, isSender: Bool = true) {
        self.status = status
        self.isSender = isSender
    }
    
    public var body: some View {
        if isSender {
            HStack(spacing: 3) {
                switch status {
                case .queued:
                    // 1. En Cola: Micro Reloj de Órbita Naranja
                    HStack(spacing: 2) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.8))
                    }
                    
                case .sending:
                    // 2. Enviando: Anillo de Cifrado Giratorio
                    Circle()
                        .trim(from: 0.1, to: 0.85)
                        .stroke(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 8, height: 8)
                        .rotationEffect(.degrees(isSpinning ? 360 : 0))
                        .onAppear {
                            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                                isSpinning = true
                            }
                        }
                    
                case .sent:
                    // 3. Enviado: Un Chevron Geométrico de Alta Precisión
                    singleChevronMark(color: Color.white.opacity(0.85))
                    
                case .delivered:
                    // 4. Entregado: Doble Chevron Entrelazado (Blanco/Plateado)
                    doubleChevronMark(color: Color.white.opacity(0.95))
                    
                case .read:
                    // 5. Leído: Doble Marca Radiante con Huella Naranja Myaow
                    HStack(spacing: 2) {
                        doubleChevronMark(color: MyaowColor.orangeLight)
                        
                        // Micro Huella Naranja Myaow
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 7))
                            .foregroundColor(MyaowColor.orange)
                            .shadow(color: MyaowColor.orange.opacity(0.6), radius: 3, x: 0, y: 0)
                    }
                    
                case .meshRelayed:
                    // 6. Mesh Relayed: Entregado por Saltos P2P sin Internet
                    HStack(spacing: 2) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(MyaowColor.statusGreen)
                        doubleChevronMark(color: MyaowColor.statusGreen)
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: status)
        }
    }
    
    // MARK: - Chevrons de Precisión Myaow (Diseño Geométrico Propio)
    private func singleChevronMark(color: Color) -> some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundColor(color)
    }
    
    private func doubleChevronMark(color: Color) -> some View {
        HStack(spacing: -4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold, design: .rounded))
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .black, design: .rounded))
        }
        .foregroundColor(color)
    }
}
