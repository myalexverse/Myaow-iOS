//
//  ProtectedMediaBubbleView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct ProtectedMediaBubbleView: View {
    public let message: MessageModel
    public let onSelect: () -> Void
    
    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Caja difuminada de imagen
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(MyaowColor.surfaceElevated)
                        .frame(height: 170)
                    
                    // Fondo difuminado decorativo
                    LinearGradient(
                        colors: [MyaowColor.orange.opacity(0.12), MyaowColor.surfaceSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 26))
                            .foregroundColor(MyaowColor.orange)
                        
                        Text("Imagen difuminada\npor IA local")
                            .font(.myaowCaptionMedium)
                            .multilineTextAlignment(.center)
                            .foregroundColor(MyaowColor.textPrimary)
                    }
                    
                    // Hora en la esquina inferior derecha
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(timeString(message.timestamp))
                                .font(.myaowMicro)
                                .foregroundColor(MyaowColor.textSecondary)
                                .padding(10)
                        }
                    }
                }
                
                // Explicación de seguridad tranquila
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(MyaowColor.orange)
                        .padding(.top, 2)
                    
                    Text("Este mensaje contiene contenido que nuestra IA local ha bloqueado por tu seguridad.")
                        .font(.myaowCaption)
                        .foregroundColor(MyaowColor.textSecondary)
                    
                    Spacer()
                    
                    Text(timeString(message.timestamp))
                        .font(.myaowMicro)
                        .foregroundColor(MyaowColor.textTertiary)
                }
                .padding(.horizontal, 4)
            }
            .frame(maxWidth: 290)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
