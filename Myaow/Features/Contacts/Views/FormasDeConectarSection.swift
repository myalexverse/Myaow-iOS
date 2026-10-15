//
//  FormasDeConectarSection.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct FormasDeConectarSection: View {
    public var onFaceToFace: () -> Void
    public var onQRCode: () -> Void
    public var onMyaowId: () -> Void
    
    public init(
        onFaceToFace: @escaping () -> Void,
        onQRCode: @escaping () -> Void,
        onMyaowId: @escaping () -> Void
    ) {
        self.onFaceToFace = onFaceToFace
        self.onQRCode = onQRCode
        self.onMyaowId = onMyaowId
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FORMAS DE CONECTAR")
                .font(.myaowMicro)
                .foregroundColor(MyaowColor.textSecondary)
                .padding(.horizontal, 4)
            
            HStack(spacing: 12) {
                // 1. Cara a cara
                methodCard(
                    icon: "iphone.radiowaves.left.and.right",
                    title: "Cara a cara",
                    subtitle: "Acerca tu iPhone al de otra persona.",
                    action: onFaceToFace
                )
                
                // 2. Código QR
                methodCard(
                    icon: "qrcode.viewfinder",
                    title: "Código QR",
                    subtitle: "Escanea el código de otra persona.",
                    action: onQRCode
                )
                
                // 3. ID de Myaow
                methodCard(
                    icon: "at",
                    title: "ID de Myaow",
                    subtitle: "Ingresa el ID de Myaow de alguien.",
                    action: onMyaowId
                )
            }
        }
    }
    
    private func methodCard(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            action()
        }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(MyaowColor.orange.opacity(0.12))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(MyaowColor.orange)
                }
                .padding(.top, 4)
                
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundColor(Color(hex: "#8E8E93"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1.2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#18181A"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
