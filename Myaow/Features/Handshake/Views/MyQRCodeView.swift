//
//  MyQRCodeView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct MyQRCodeView: View {
    @Environment(\.dismiss) private var dismiss
    private let identity = IdentityManager.shared.currentIdentity
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                HStack {
                    Spacer()
                    Button("Cerrar") {
                        dismiss()
                    }
                    .font(.myaowCallout)
                    .foregroundColor(MyaowColor.orange)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
                
                // Tarjeta de Código QR
                VStack(spacing: 20) {
                    MyaowAvatarView(
                        source: .cat(state: .happy, style: .darkOnOrange),
                        size: 70
                    )
                    
                    VStack(spacing: 4) {
                        Text(identity.displayName)
                            .font(.myaowTitle)
                            .foregroundColor(MyaowColor.textPrimary)
                        
                        Text(identity.myaowId)
                            .font(.myaowMonoLarge)
                            .foregroundColor(MyaowColor.orange)
                    }
                    
                    // Renderizado del código QR
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 220, height: 220)
                        
                        if let qrImage = IdentityManager.shared.generateQRCodeImage(size: 200) {
                            qrImage
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 190, height: 190)
                        } else {
                            // Fallback estético
                            Image(systemName: "qrcode")
                                .font(.system(size: 150))
                                .foregroundColor(.black)
                        }
                    }
                    
                    Text("Cero números de teléfono. Totalmente privado.")
                        .font(.myaowCaption)
                        .foregroundColor(MyaowColor.textSecondary)
                }
                .padding(24)
                .background(MyaowColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(MyaowColor.borderSubtle, lineWidth: 1)
                )
                .padding(.horizontal, 24)
                
                Spacer()
                
                MyaowPillButton("Compartir Mi ID", icon: "square.and.arrow.up", style: .secondary, isFullWidth: true) {
                    // Compartir payload
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }
}

#Preview {
    MyQRCodeView()
}
