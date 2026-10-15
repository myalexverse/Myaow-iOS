//
//  PrivacySecuritySettingsView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct PrivacySecuritySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var moderationService = LocalAIModerationService.shared
    
    @State private var showingSafetyNumberModal = false
    @State private var showingVaultModal = false
    @State private var showingDisappearingTimerModal = false
    @State private var showingModerationModal = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header Informativo
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacidad y Seguridad")
                            .font(.system(size: 24, weight: .bold, design: .default))
                            .foregroundColor(.white)
                        
                        Text("Configura el acceso a tu aplicación, los filtros de contenido y la duración de tus mensajes.")
                            .font(.system(size: 13, weight: .medium, design: .default))
                            .foregroundColor(MyaowColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Bloque Principal de Seguridad
                    MyaowCard(padding: 0) {
                        VStack(spacing: 0) {
                            settingsOptionRow(
                                icon: "lock.shield.fill",
                                iconColor: MyaowColor.orange,
                                title: "Código de seguridad",
                                subtitle: "Consulta el código de tu identidad",
                                value: nil,
                                valueColor: MyaowColor.statusGreen
                            ) {
                                showingSafetyNumberModal = true
                            }
                            
                            divider
                            
                            settingsOptionRow(
                                icon: "faceid",
                                iconColor: Color(hex: "#007AFF"),
                                title: "Bóveda de Acceso Seguro",
                                subtitle: "Bloqueo con Face ID o código",
                                value: nil
                            ) {
                                showingVaultModal = true
                            }
                            
                            divider
                            
                            settingsOptionRow(
                                icon: "timer",
                                iconColor: Color(hex: "#FF9500"),
                                title: "Mensajes Temporales",
                                subtitle: "Preferencia de duración de los mensajes",
                                value: DisappearingMessagesService.shared.defaultDuration.rawValue,
                                valueColor: MyaowColor.orange
                            ) {
                                showingDisappearingTimerModal = true
                            }
                            
                            divider
                            
                            settingsOptionRow(
                                icon: "eye.slash.fill",
                                iconColor: Color(hex: "#5856D6"),
                                title: "Protección de Contenido",
                                subtitle: "Filtro on-device de imágenes no deseadas",
                                value: moderationService.isEnabled ? "Activa" : "Inactiva",
                                valueColor: moderationService.isEnabled ? MyaowColor.orange : MyaowColor.textTertiary
                            ) {
                                showingModerationModal = true
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Nota de Confianza
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 14))
                            .foregroundColor(MyaowColor.statusGreen)
                        
                        Text("Tu identidad no necesita un número de teléfono.")
                            .font(.system(size: 12, weight: .semibold, design: .default))
                            .foregroundColor(MyaowColor.textSecondary)
                    }
                    .padding(.top, 8)
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Privacidad")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .tint(MyaowColor.textPrimary)
        .sheet(isPresented: $showingSafetyNumberModal) {
            SafetyNumberView()
        }
        .sheet(isPresented: $showingVaultModal) {
            SafeVaultView()
        }
        .sheet(isPresented: $showingModerationModal) {
            BlockedContentSheetView()
        }
        .sheet(isPresented: $showingDisappearingTimerModal) {
            disappearingTimerSheet
        }
    }
    
    private var divider: some View {
        Divider()
            .background(MyaowColor.borderSubtle.opacity(0.4))
            .padding(.leading, 56)
    }
    
    private func settingsOptionRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String?,
        value: String?,
        valueColor: Color = MyaowColor.textSecondary,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            action()
        }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 34, height: 34)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .default))
                        .foregroundColor(.white)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular, design: .default))
                            .foregroundColor(MyaowColor.textSecondary)
                    }
                }
                
                Spacer()
                
                if let value = value {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .default))
                        .foregroundColor(valueColor)
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyaowColor.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var disappearingTimerSheet: some View {
        NavigationStack {
            ZStack {
                MyaowColor.charcoal.ignoresSafeArea()
                
                VStack(spacing: 12) {
                    ForEach(DisappearingDuration.allCases) { duration in
                        let isSelected = DisappearingMessagesService.shared.defaultDuration == duration
                        
                        Button(action: {
                            DisappearingMessagesService.shared.defaultDuration = duration
                            showingDisappearingTimerModal = false
                        }) {
                            HStack {
                                Text(duration.rawValue)
                                    .font(.myaowHeadline)
                                    .foregroundColor(isSelected ? MyaowColor.orange : MyaowColor.textPrimary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(MyaowColor.orange)
                                        .font(.system(size: 14, weight: .bold))
                                }
                            }
                            .padding(16)
                            .background(MyaowColor.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Mensajes Temporales")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { showingDisappearingTimerModal = false }
                        .foregroundColor(MyaowColor.orange)
                }
            }
        }
        .presentationDetents([.fraction(0.55)])
    }
}
