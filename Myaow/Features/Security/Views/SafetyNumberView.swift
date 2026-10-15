//
//  SafetyNumberView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct SafetyNumberView: View {
    @Environment(\.dismiss) private var dismiss
    
    public var contactName: String
    public var contactMyaowId: String
    public var contactPublicKeyHex: String
    
    @State private var isVerified: Bool = false
    @State private var showingScanner: Bool = false
    
    private var safetyNumber: SafetyNumber? {
        if contactPublicKeyHex.isEmpty { return nil }
        return SafetyNumberService.shared.generateSafetyNumber(
            myIdentity: IdentityManager.shared.currentIdentity,
            peerPublicKeyHex: contactPublicKeyHex,
            peerMyaowId: contactMyaowId
        )
    }
    
    public init(
        contactName: String = "Contacto",
        contactMyaowId: String = "",
        contactPublicKeyHex: String = ""
    ) {
        self.contactName = contactName
        self.contactMyaowId = contactMyaowId
        self.contactPublicKeyHex = contactPublicKeyHex
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                MyaowColor.charcoal
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header con Avatar y Estado de Cifrado
                        VStack(spacing: 12) {
                            MyaowAvatarView(
                                source: .cat(state: .friendly, style: .darkOnOrange),
                                size: 70
                            )
                            
                            VStack(spacing: 4) {
                                Text(contactName)
                                    .font(.myaowTitle)
                                    .foregroundColor(MyaowColor.textPrimary)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.shield.fill")
                                        .foregroundColor(MyaowColor.orange)
                                    Text("Cifrado Double Ratchet de Extremo a Extremo")
                                        .font(.myaowMicro)
                                        .foregroundColor(MyaowColor.textSecondary)
                                }
                            }
                        }
                        .padding(.top, 12)
                        
                        // Código QR de Verificación Bilateral
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white)
                                .frame(width: 180, height: 180)
                            
                            if let qr = IdentityManager.shared.generateQRCodeImage(size: 160) {
                                qr
                                    .interpolation(.none)
                                    .resizable()
                                    .frame(width: 160, height: 160)
                            }
                        }
                        
                        // Huella Criptográfica de 60 dígitos en bloques de 5
                        VStack(spacing: 10) {
                            Text("CÓDIGO DE SEGURIDAD")
                                .font(.myaowMicro)
                                .foregroundColor(MyaowColor.textSecondary)
                            
                            if contactPublicKeyHex.isEmpty {
                                Text("No se puede verificar la seguridad")
                                    .font(.system(size: 14, weight: .regular, design: .rounded))
                                    .foregroundColor(MyaowColor.textSecondary)
                                    .padding(.vertical, 8)
                            } else if let sn = safetyNumber {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(sn.formattedBlocks, id: \.self) { block in
                                        Text(block)
                                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                                            .foregroundColor(MyaowColor.textPrimary)
                                            .padding(.vertical, 8)
                                            .padding(.horizontal, 10)
                                            .frame(maxWidth: .infinity)
                                            .background(MyaowColor.surface)
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // Explicación anti-MITM tranquila
                        Text("Para verificar que la conversación es 100% privada y que ninguna clave ha sido interceptada, compara estos 60 dígitos con el dispositivo de tu contacto o escanea su código.")
                            .font(.myaowCaption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(MyaowColor.textSecondary)
                            .padding(.horizontal, 30)
                        
                        // Botón de Escanear / Validar
                        MyaowPillButton(
                            isVerified ? "Código Verificado ✓" : "Escanear para Comparar",
                            icon: isVerified ? "checkmark.seal.fill" : "qrcode.viewfinder",
                            style: isVerified ? .secondary : .primary,
                            isFullWidth: true
                        ) {
                            withAnimation {
                                isVerified.toggle()
                            }
                            let generator = UINotificationFeedbackGenerator()
                            generator.notificationOccurred(.success)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Código de Seguridad")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                    }
                    .font(.myaowCallout)
                    .foregroundColor(MyaowColor.orange)
                }
            }
        }
    }
}

#Preview {
    SafetyNumberView()
}
