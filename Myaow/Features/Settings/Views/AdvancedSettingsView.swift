//
//  AdvancedSettingsView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public struct AdvancedSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var onlineService = OnlineMessagingService.shared
    @State private var identityManager = IdentityManager.shared
    
    @State private var showingMyQR = false
    @State private var showingAboutModal = false
    @State private var showingRelayHostAlert = false
    @State private var relayHostInput = ""
    @State private var showingResetAlert = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header Informativo
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Configuración Avanzada")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Herramientas técnicas de conexión, claves criptográficas y diagnósticos.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(MyaowColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    
                    // Bloque 1: Conexión & Redes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONECTIVIDAD Y RED")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(MyaowColor.textTertiary)
                            .padding(.horizontal, 24)
                        
                        MyaowCard(padding: 0) {
                            VStack(spacing: 0) {
                                advancedRow(
                                    icon: "network",
                                    iconColor: Color(hex: "#34C759"),
                                    title: "Servidor de mensajes",
                                    subtitle: onlineService.relayHost,
                                    value: onlineService.status == .online ? "Conectado" : "Reintentando",
                                    valueColor: onlineService.status == .online ? MyaowColor.statusGreen : MyaowColor.orange
                                ) {
                                    #if DEBUG
                                    relayHostInput = onlineService.relayHost
                                    showingRelayHostAlert = true
                                    #endif
                                }
                                
                                divider
                                
                                advancedRow(
                                    icon: "point.3.connected.trianglepath.dotted",
                                    iconColor: MyaowColor.orange,
                                    title: "Red Local Mesh P2P",
                                    subtitle: "Bluetooth LE + Wi-Fi Direct",
                                    value: "Activa",
                                    valueColor: MyaowColor.statusGreen
                                ) {
                                    // Diagnóstico mesh
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        if RelayEndpoint(onlineService.relayHost)?.supabaseAPIURL != nil {
                            Text("Conexión de prueba: los mensajes se actualizan mientras la app está abierta. Las llamadas por internet y las notificaciones aún no están activadas.")
                                .font(.footnote)
                                .foregroundStyle(MyaowColor.textSecondary)
                                .padding(.horizontal, 24)
                        }
                    }
                    
                    // Bloque 2: Claves e Identidad
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CLAVES Y CRIPTOGRAFÍA")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(MyaowColor.textTertiary)
                            .padding(.horizontal, 24)
                        
                        MyaowCard(padding: 0) {
                            VStack(spacing: 0) {
                                advancedRow(
                                    icon: "qrcode",
                                    iconColor: Color(hex: "#007AFF"),
                                    title: "Mi Tarjeta QR Criptográfica",
                                    subtitle: "Clave pública Curve25519 para handshakes",
                                    value: nil
                                ) {
                                    showingMyQR = true
                                }
                                
                                divider
                                
                                advancedRow(
                                    icon: "key.fill",
                                    iconColor: Color(hex: "#FF9500"),
                                    title: "ID de Huella Digital",
                                    subtitle: identityManager.currentIdentity.myaowId,
                                    value: nil
                                ) {
                                    UIPasteboard.general.string = identityManager.currentIdentity.myaowId
                                    let gen = UINotificationFeedbackGenerator()
                                    gen.notificationOccurred(.success)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Bloque 3: Mantenimiento
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SISTEMA")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(MyaowColor.textTertiary)
                            .padding(.horizontal, 24)
                        
                        MyaowCard(padding: 0) {
                            VStack(spacing: 0) {
                                advancedRow(
                                    icon: "info.circle.fill",
                                    iconColor: Color(hex: "#8E8E93"),
                                    title: "Acerca de Myaow",
                                    subtitle: "Versión 2.0 • Calm Tech",
                                    value: nil
                                ) {
                                    showingAboutModal = true
                                }
                                
                                divider
                                
                                advancedRow(
                                    icon: "trash.fill",
                                    iconColor: Color(hex: "#FF3B30"),
                                    title: "Restablecer Datos de Prueba",
                                    subtitle: "Limpia base de datos de simulación",
                                    value: nil
                                ) {
                                    showingResetAlert = true
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Avanzado")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMyQR) {
            MyQRCodeView()
        }
        .sheet(isPresented: $showingAboutModal) {
            aboutModalView
        }
        .alert("Servidor de mensajes", isPresented: $showingRelayHostAlert) {
            TextField("Dirección HTTPS del servidor", text: $relayHostInput)
                .autocapitalization(.none)
            Button("Guardar y Conectar") {
                let cleaned = relayHostInput.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    OnlineMessagingService.shared.relayHost = cleaned
                }
            }
            Button("Restablecer por Defecto") {
                OnlineMessagingService.shared.relayHost = OnlineMessagingService.defaultServerHost
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Permite enlazar el iPhone físico con la Mac o con un servidor Relay en la nube.")
        }
        .alert("Restablecer Datos", isPresented: $showingResetAlert) {
            Button("Restablecer", role: .destructive) {
                DataPreviewSample.purgeAllBetaData(context: modelContext)
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se eliminarán las conversaciones y contactos de prueba locales.")
        }
    }
    
    private var divider: some View {
        Divider()
            .background(MyaowColor.borderSubtle.opacity(0.4))
            .padding(.leading, 56)
    }
    
    private func advancedRow(
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
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(MyaowColor.textSecondary)
                    }
                }
                
                Spacer()
                
                if let value = value {
                    Text(value)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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
    
    private var aboutModalView: some View {
        NavigationStack {
            ZStack {
                MyaowColor.charcoal.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    MyaowCatView(state: .friendly, style: .darkOnOrange, size: 80, isInteractive: true)
                    
                    VStack(spacing: 6) {
                        Text("Myaow")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("Tecnología que se siente cercana")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(MyaowColor.orange)
                    }
                    
                    Text("Myaow reimagina la mensajería instantánea combinando cifrado de extremo a extremo sin números de teléfono, redes de malla locales P2P y una experiencia humana, cálida y tranquila.")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(MyaowColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                    
                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationTitle("Acerca de")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { showingAboutModal = false }
                        .foregroundColor(MyaowColor.orange)
                }
            }
        }
    }
}
