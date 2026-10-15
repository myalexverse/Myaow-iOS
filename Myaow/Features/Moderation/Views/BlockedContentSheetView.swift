//
//  BlockedContentSheetView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct BlockedContentSheetView: View {
    @Environment(\.dismiss) private var dismiss
    public var onRevealContent: (() -> Void)?
    
    @State private var selectedCategory: ModerationCategory = .violence
    
    public init(onRevealContent: (() -> Void)? = nil) {
        self.onRevealContent = onRevealContent
    }
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Indicador superior de arrastre
                Capsule()
                    .fill(MyaowColor.surfaceSecondary)
                    .frame(width: 36, height: 4)
                    .padding(.top, 10)
                
                Spacer()
                
                // Icono de Escudo Seguro Naranja
                ZStack {
                    Circle()
                        .fill(MyaowColor.orange.opacity(0.12))
                        .frame(width: 84, height: 84)
                    
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 40))
                        .foregroundColor(MyaowColor.orange)
                }
                
                VStack(spacing: 8) {
                    Text("Contenido bloqueado")
                        .font(.myaowTitle)
                        .foregroundColor(MyaowColor.textPrimary)
                    
                    Text("Nuestra IA local ha bloqueado este contenido por tu seguridad.")
                        .font(.myaowBody)
                        .multilineTextAlignment(.center)
                        .foregroundColor(MyaowColor.textSecondary)
                        .padding(.horizontal, 24)
                }
                
                // Categorías con radio buttons según el mockup
                VStack(spacing: 12) {
                    categoryRow(.violence, title: "Violencia")
                    categoryRow(.nudity, title: "Desnudos")
                    categoryRow(.offensiveLanguage, title: "Lenguaje ofensivo")
                    categoryRow(.other, title: "Otro")
                }
                .padding(16)
                .background(MyaowColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Acciones
                VStack(spacing: 14) {
                    MyaowPillButton("Desbloquear bajo mi consentimiento", icon: "eye.fill", style: .secondary, isFullWidth: true) {
                        onRevealContent?()
                        dismiss()
                    }
                    
                    Button(action: {
                        dismiss()
                    }) {
                        Text("Más información sobre privacidad")
                            .font(.myaowCallout)
                            .foregroundColor(MyaowColor.orange)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    @ViewBuilder
    private func categoryRow(_ category: ModerationCategory, title: String) -> some View {
        HStack {
            Text(title)
                .font(.myaowBodyMedium)
                .foregroundColor(MyaowColor.textPrimary)
            
            Spacer()
            
            ZStack {
                Circle()
                    .stroke(selectedCategory == category ? MyaowColor.orange : MyaowColor.textTertiary, lineWidth: 2)
                    .frame(width: 20, height: 20)
                
                if selectedCategory == category {
                    Circle()
                        .fill(MyaowColor.orange)
                        .frame(width: 12, height: 12)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedCategory = category
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    BlockedContentSheetView()
}
