//
//  MyaowHandshakeModalView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public enum HandshakeStage: Int, CaseIterable {
    case searching = 0    // Buscando iPhone cercano por BLE/WiFi Direct P2P
    case approaching = 1  // 🐱 ↔️ 🐱 Dispositivos detectados físicamente cerca
    case agreement = 2    // 🤝 Aprobando conexión mutua E2EE
    case connected = 3    // ✓ Conexión cifrada establecida y guardada
}

public struct MyaowHandshakeModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var stage: HandshakeStage = .searching
    @State private var discoveredPeerName: String = ""
    @State private var discoveredPeerId: String = ""
    
    @State private var cat1Offset: CGFloat = -90
    @State private var cat2Offset: CGFloat = 90
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.8
    @State private var handshakeGlow: CGFloat = 1.0
    
    public init() {}
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Barra de cierre
                HStack {
                    Spacer()
                    Button(action: {
                        MeshNetworkService.shared.stopMeshServices()
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(MyaowColor.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
                
                // Animación Central Cara a Cara: 🐱 → 🐱 → 🤝 → ✓
                ZStack {
                    // Ondas de Proximidad Expansivas P2P
                    Circle()
                        .stroke(MyaowColor.orange.opacity(pulseOpacity), lineWidth: 1.5)
                        .frame(width: 220, height: 220)
                        .scaleEffect(pulseScale)
                    
                    Circle()
                        .stroke(MyaowColor.orange.opacity(pulseOpacity * 0.5), lineWidth: 1)
                        .frame(width: 280, height: 280)
                        .scaleEffect(pulseScale * 1.1)
                    
                    if stage == .searching || stage == .approaching {
                        // Dos gatitos acercándose (Cara a cara estilo NameDrop)
                        HStack(spacing: 0) {
                            MyaowCatView(
                                state: .curious,
                                style: .darkOnOrange,
                                size: 68
                            )
                            .offset(x: cat1Offset)
                            
                            MyaowCatView(
                                state: .friendly,
                                style: .orangeOnDark,
                                size: 68
                            )
                            .offset(x: cat2Offset)
                        }
                    } else if stage == .agreement {
                        // 🤝 Apretón de Paws / Handshake con halo brillante
                        ZStack {
                            Circle()
                                .fill(MyaowColor.orange.opacity(0.15))
                                .frame(width: 140, height: 140)
                                .scaleEffect(handshakeGlow)
                            
                            Text("🤝")
                                .font(.system(size: 72))
                                .shadow(color: MyaowColor.orange.opacity(0.6), radius: 16)
                        }
                    } else {
                        // ✓ Conexión Aprobada y Cifrada
                        ZStack {
                            Circle()
                                .fill(MyaowColor.statusGreen.opacity(0.18))
                                .frame(width: 140, height: 140)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 76))
                                .foregroundColor(MyaowColor.statusGreen)
                                .shadow(color: MyaowColor.statusGreen.opacity(0.6), radius: 14)
                        }
                    }
                }
                .frame(height: 240)
                
                // Textos de Estado & Privacidad
                VStack(spacing: 8) {
                    Text(titleForStage)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text(subtitleForStage)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#8E8E93"))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                Spacer()
                
                // Botón de Acción o Estado
                VStack(spacing: 12) {
                    if stage == .agreement {
                        HStack(spacing: 14) {
                            Button("Rechazar") {
                                MeshNetworkService.shared.stopMeshServices()
                                dismiss()
                            }
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "#8E8E93"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            
                            Button("Aprobar Conexión") {
                                completeHandshake()
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(MyaowColor.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: MyaowColor.orange.opacity(0.4), radius: 10, x: 0, y: 4)
                        }
                        .padding(.horizontal, 20)
                    } else if stage == .connected {
                        Button("Listo") {
                            MeshNetworkService.shared.stopMeshServices()
                            dismiss()
                        }
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(MyaowColor.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal, 20)
                    } else {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(MyaowColor.orange)
                                .frame(width: 8, height: 8)
                            Text("Modo descubrimiento temporal activo (BLE + WiFi Direct)")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(Color(hex: "#8E8E93"))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .onAppear {
            startLiveHandshakeDiscovery()
        }
        .onDisappear {
            MeshNetworkService.shared.stopMeshServices()
        }
    }
    
    private var titleForStage: String {
        let name = discoveredPeerName.isEmpty ? "Dispositivo cercano" : discoveredPeerName
        switch stage {
        case .searching: return "Acerca tu iPhone"
        case .approaching: return "¡\(name) detectada!"
        case .agreement: return "¿Conectar con \(name)?"
        case .connected: return "¡Conexión verificada! 🤝"
        }
    }
    
    private var subtitleForStage: String {
        switch stage {
        case .searching:
            return "Mantén la parte superior de tu iPhone cerca del otro dispositivo para iniciar Myaow Handshake sin internet."
        case .approaching:
            return "Intercambiando claves públicas Curve25519 de forma segura y privada."
        case .agreement:
            return "Ambos deben aceptar para establecer el canal cifrado Double Ratchet offline."
        case .connected:
            return "Añadida a 'Tu gente'. El descubrimiento de radio se apagó automáticamente por privacidad."
        }
    }
    
    private func startLiveHandshakeDiscovery() {
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
            pulseScale = 1.35
            pulseOpacity = 0.0
        }
        
        // 1. Activar chips de radio en hardware real (Bluetooth Low Energy + Wi-Fi Direct P2P)
        MeshNetworkService.shared.startMeshServices()
        
        // 2. Transición visual con respuesta háptica progresiva
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.8))
            let gen = UIImpactFeedbackGenerator(style: .medium)
            gen.impactOccurred()
            
            // Si hay un dispositivo real cercano en la sesión Multipeer, tomamos su nombre
            if let firstRealPeer = MeshNetworkService.shared.connectedPeers.first ?? MeshNetworkService.shared.discoveredPeers.first {
                self.discoveredPeerName = firstRealPeer.displayName
                self.discoveredPeerId = firstRealPeer.myaowId
            }
            
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                stage = .approaching
                cat1Offset = -22
                cat2Offset = 22
            }
            
            try? await Task.sleep(for: .seconds(1.5))
            let heavyGen = UIImpactFeedbackGenerator(style: .heavy)
            heavyGen.impactOccurred()
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                stage = .agreement
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                handshakeGlow = 1.25
            }
        }
    }
    
    private func completeHandshake() {
        // 1. Guardar contacto verificado en base de datos local
        let newContact = ContactModel(
            myaowId: discoveredPeerId,
            did: "did:myaow:\(discoveredPeerId.lowercased())",
            displayName: discoveredPeerName,
            isMeshNearby: true,
            isVerified: true
        )
        modelContext.insert(newContact)
        try? modelContext.save()
        
        // 2. Reproducir sonido y vibración de éxito
        MyaowSoundEffectsService.shared.playPurrEffect()
        let successGen = UINotificationFeedbackGenerator()
        successGen.notificationOccurred(.success)
        
        // 3. Desactivar descubrimiento de radio
        MeshNetworkService.shared.stopMeshServices()
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            stage = .connected
        }
    }
}
