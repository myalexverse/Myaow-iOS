//
//  SpaceInviteModalView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct SpaceInviteModalView: View {
    @Environment(\.dismiss) private var dismiss
    public let spaceTitle: String
    
    @State private var selectedMethod: Int = 0 // 0: QR, 1: Cara a cara
    
    public init(spaceTitle: String) {
        self.spaceTitle = spaceTitle
    }
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "#8E8E93"))
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    VStack(spacing: 2) {
                        Text(spaceTitle)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Espacio temporal · 12 conectados")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundColor(MyaowColor.statusGreen)
                    }
                    
                    Spacer()
                    
                    Button(action: {}) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundColor(Color(hex: "#8E8E93"))
                    }.disabled(true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                
                // Selector de Método: Código QR | Cara a cara
                HStack(spacing: 10) {
                    inviteMethodPill(title: "Código QR", isSelected: selectedMethod == 0) {
                        selectedMethod = 0
                    }
                    inviteMethodPill(title: "Cara a cara", isSelected: selectedMethod == 1) {
                        selectedMethod = 1
                    }
                }
                .padding(.horizontal, 20)
                
                Spacer(minLength: 0)
                
                if selectedMethod == 0 {
                    // Código QR con Gato Myaow en el centro
                    VStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 220, height: 220)
                                .shadow(color: Color.black.opacity(0.3), radius: 12)
                            
                            Image(systemName: "qrcode")
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(width: 190, height: 190)
                                .foregroundColor(.black)
                            
                            // Gato Myaow en el centro del QR
                            Circle()
                                .fill(Color.white)
                                .frame(width: 44, height: 44)
                            
                            MyaowCatView(
                                state: .happy,
                                style: .darkOnOrange,
                                size: 36,
                                isInteractive: false
                            )
                        }
                        
                        Text("Escanea para unirte a este espacio privado.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        
                        Button(action: {}) {
                            HStack(spacing: 6) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Compartir enlace de invitación")
                            }
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(Color(hex: "#C7C7CC"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                        }.disabled(true)
                        
                        VStack(spacing: 4) {
                            Text("O comparte el código único")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundColor(Color(hex: "#8E8E93"))
                            
                            HStack(spacing: 8) {
                                Text("MYAOW-TSEG7")
                                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                                    .foregroundColor(MyaowColor.orange)
                                
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 13))
                                    .foregroundColor(Color(hex: "#8E8E93"))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hex: "#18181A"))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                } else {
                    // Cara a cara
                    VStack(spacing: 20) {
                        MyaowCatView(state: .friendly, style: .darkOnOrange, size: 70)
                        
                        Text("Acerca ambos dispositivos")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Mantén la parte superior de tu iPhone cerca del de la otra persona para invitarla directamente por Mesh.")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(Color(hex: "#8E8E93"))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .padding(.vertical, 30)
                }
                
                Spacer(minLength: 0)
                
                Text("El acceso requiere aprobación de los administradores del espacio.")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#636366"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
            }
        }
        .presentationDetents([.fraction(0.85)])
    }
    
    private func inviteMethodPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                .foregroundColor(isSelected ? .white : Color(hex: "#8E8E93"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isSelected ? Color(hex: "#261D16") : Color(hex: "#18181A"))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isSelected ? MyaowColor.orange.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
