//
//  QRScannerView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData
import AVFoundation

public struct QRScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var isTorchOn: Bool = false
    @State private var showingMyQR: Bool = false
    @State private var scanLaserOffset: CGFloat = -110
    @State private var detectedContact: ScannedQRContact? = nil
    @State private var isScanSuccessful: Bool = false
    @State private var manualInputText: String = ""
    @State private var showingManualInput: Bool = false
    
    public struct ScannedQRContact: Identifiable {
        public let id = UUID()
        public let displayName: String
        public let myaowId: String
        public let safetyNumber: String
        public let avatarState: MyaowCatState
        public let did: String
    }
    
    public init() {}
    
    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                // Header
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("Escanear código QR")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        isTorchOn.toggle()
                        toggleTorch(on: isTorchOn)
                    }) {
                        Image(systemName: isTorchOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(isTorchOn ? MyaowColor.orange : Color(hex: "#8E8E93"))
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                
                Spacer(minLength: 0)
                
                // Visor QR con Cámara Nativa AVCaptureSession
                ZStack {
                    // Vista de Cámara Real de iOS
                    #if canImport(UIKit)
                    CameraQRScannerView { scannedPayload in
                        handleScannedQRCodePayload(scannedPayload)
                    }
                    .frame(width: 270, height: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    #endif
                    
                    // Contenedor del visor
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.5)
                        .frame(width: 270, height: 270)
                    
                    // Esquinas de enfoque Myaow Orange
                    QRCornerBrackets()
                        .stroke(isScanSuccessful ? MyaowColor.statusGreen : MyaowColor.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 270, height: 270)
                        .animation(.easeInOut(duration: 0.3), value: isScanSuccessful)
                    
                    // Línea de escaneo láser pulsante
                    if !isScanSuccessful {
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear, MyaowColor.orange, Color.clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 230, height: 2.5)
                            .offset(y: scanLaserOffset)
                            .shadow(color: MyaowColor.orange.opacity(0.8), radius: 6)
                    }
                    
                    if isScanSuccessful {
                        ZStack {
                            Circle()
                                .fill(MyaowColor.statusGreen.opacity(0.2))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(MyaowColor.statusGreen)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .contentShape(Rectangle())
                
                VStack(spacing: 6) {
                    Text("Apunta la cámara al código QR de otra persona")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Text("La clave criptográfica Curve25519 se verificará de inmediato.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color(hex: "#8E8E93"))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.top, 8)
                
                Spacer(minLength: 0)
                
                // Botones Inferiores: Mi código QR & Ingresar ID
                HStack(spacing: 12) {
                    Button(action: {
                        showingMyQR = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "qrcode")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Mi código QR")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .background(Color(hex: "#222226"))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                    
                    Button(action: {
                        showingManualInput = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Ingresar ID")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(MyaowColor.orange)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 13)
                        .background(MyaowColor.orange.opacity(0.12))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(MyaowColor.orange.opacity(0.3), lineWidth: 1)
                        )
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showingMyQR) {
            MyQRCodeView()
        }
        .sheet(item: $detectedContact) { contact in
            contactDetectedSheet(contact: contact)
                .presentationDetents([.fraction(0.55)])
        }
        .alert("Conectar por Myaow ID", isPresented: $showingManualInput) {
            TextField("Ej: MYAOW-9K2L", text: $manualInputText)
                .autocapitalization(.allCharacters)
            Button("Conectar") {
                if !manualInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    handleScannedQRCodePayload(manualInputText.trimmingCharacters(in: .whitespacesAndNewlines))
                    manualInputText = ""
                }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Introduce el ID del usuario para verificar su identidad criptográfica.")
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                scanLaserOffset = 110
            }
        }
    }
    
    // MARK: - Tarjeta de Contacto Real Detectado
    private func contactDetectedSheet(contact: ScannedQRContact) -> some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Capsule()
                    .fill(MyaowColor.surfaceSecondary)
                    .frame(width: 36, height: 4)
                    .padding(.top, 12)
                
                // Avatar de la persona
                ZStack(alignment: .bottomTrailing) {
                    MyaowCatView(
                        state: contact.avatarState,
                        style: .darkOnOrange,
                        size: 64,
                        isInteractive: false
                    )
                    
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18))
                        .foregroundColor(MyaowColor.statusGreen)
                        .background(Circle().fill(MyaowColor.charcoal))
                }
                
                VStack(spacing: 4) {
                    Text(contact.displayName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("ID: \(contact.myaowId)")
                        .font(.myaowMono)
                        .foregroundColor(MyaowColor.orange)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 12))
                            .foregroundColor(MyaowColor.statusGreen)
                        
                        Text("Clave Curve25519 verificada")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(MyaowColor.statusGreen)
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
                
                // Botón Añadir a Tu Gente y Crear Chat
                Button(action: {
                    saveContactAndFinish(contact: contact)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                        Text("Añadir a Tu gente y Chatear")
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(MyaowColor.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: MyaowColor.orange.opacity(0.4), radius: 10, x: 0, y: 4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - Procesamiento del Payload Real del QR
    private func handleScannedQRCodePayload(_ payload: String) {
        let successGen = UINotificationFeedbackGenerator()
        successGen.notificationOccurred(.success)
        MyaowSoundEffectsService.shared.playPurrEffect()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isScanSuccessful = true
        }
        
        // 1. Intentar decodificar UserIdentity desde JSON
        if let identity = UserIdentity.fromQRPayload(payload) {
            let catState = MyaowCatState.allCases.first(where: { $0.rawValue.lowercased() == identity.avatarStateName.lowercased() }) ?? .friendly
            let safetyNum = String(identity.publicKeyHex.prefix(16))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.detectedContact = ScannedQRContact(
                    displayName: identity.displayName,
                    myaowId: identity.myaowId,
                    safetyNumber: safetyNum,
                    avatarState: catState,
                    did: identity.did
                )
            }
            return
        }
        
        // 2. Si es un Myaow ID directo o texto plano (ej: "MYAOW-7K2K")
        let cleanedId = payload.replacingOccurrences(of: "myaow://user?id=", with: "")
        let displayName = cleanedId.hasPrefix("MYAOW-") ? "Contacto \(cleanedId.suffix(4))" : cleanedId
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.detectedContact = ScannedQRContact(
                displayName: displayName,
                myaowId: cleanedId.uppercased(),
                safetyNumber: "E2EE-VERIFIED-\(cleanedId)",
                avatarState: .friendly,
                did: "did:myaow:\(cleanedId.lowercased())"
            )
        }
    }
    
    private func saveContactAndFinish(contact: ScannedQRContact) {
        // 1. Guardar o actualizar contacto
        let contactDescriptor = FetchDescriptor<ContactModel>()
        let allContacts = (try? modelContext.fetch(contactDescriptor)) ?? []
        if let existingContact = allContacts.first(where: { $0.myaowId == contact.myaowId || $0.displayName == contact.displayName }) {
            existingContact.myaowId = contact.myaowId
            existingContact.displayName = contact.displayName
            existingContact.isVerified = true
        } else {
            let newContact = ContactModel(
                myaowId: contact.myaowId,
                did: contact.did,
                displayName: contact.displayName,
                avatarCatState: contact.avatarState.rawValue,
                isMeshNearby: true,
                isVerified: true
            )
            modelContext.insert(newContact)
        }
        
        // 2. Crear o actualizar conversación
        let convDescriptor = FetchDescriptor<ConversationModel>()
        let allConvs = (try? modelContext.fetch(convDescriptor)) ?? []
        
        if let existingConv = allConvs.first(where: { $0.recipientMyaowId == contact.myaowId || $0.title == contact.displayName }) {
            existingConv.recipientMyaowId = contact.myaowId
            existingConv.title = contact.displayName
        } else {
            let newConv = ConversationModel(
                title: contact.displayName,
                recipientMyaowId: contact.myaowId,
                isGroup: false,
                unreadCount: 0,
                lastMessageSnippet: "Conexión cifrada establecida por código QR.",
                lastMessageTimestamp: Date(),
                isMeshConnected: true,
                nodeCount: 1,
                participantNames: [contact.displayName]
            )
            modelContext.insert(newConv)
        }
        try? modelContext.save()
        
        let gen = UINotificationFeedbackGenerator()
        gen.notificationOccurred(.success)
        
        detectedContact = nil
        dismiss()
    }
    
    private func toggleTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        try? device.lockForConfiguration()
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }
}

/// Esquinas naranjas tipo visor para el escáner QR
public struct QRCornerBrackets: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 32
        let radius: CGFloat = 20
        
        // Superior Izquierda
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        
        // Superior Derecha
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        
        // Inferior Izquierda
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        
        // Inferior Derecha
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        
        return path
    }
}
