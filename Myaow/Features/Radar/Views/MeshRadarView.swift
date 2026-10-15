//
//  MeshRadarView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData
import Combine

public enum UniverseFilter: String, CaseIterable, Identifiable {
    case all = "Todos"
    case localOnly = "Cerca"
    case internetOnly = "Internet"
    
    public var id: String { rawValue }
}

public struct MeshRadarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var contacts: [ContactModel]
    
    @State private var selectedFilter: UniverseFilter = .all
    @State private var radarSweepAngle: Double = 0
    @State private var selectedContactNode: UniverseContactNode?
    @State private var activeConversationForNavigation: ConversationModel?
    @State private var showingWalkieTalkie: Bool = false
    @State private var centerPulseScale: CGFloat = 1.0
    @State private var centerPulseOpacity: Double = 0.6
    
    @State private var onlineContactIds: Set<String> = []
    
    private func fetchOnlinePresence() {
        Task {
            guard let base = RelayEndpoint(OnlineMessagingService.shared.relayHost)?.httpURL,
                  let url = URL(string: base.absoluteString + "/api/v1/presence/online") else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { onlineContactIds = []; return }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let ids = json["online"] as? [String] {
                    await MainActor.run {
                        onlineContactIds = Set(ids)
                    }
                }
            } catch { onlineContactIds = [] }
        }
    }
    
    private var allUniverseNodes: [UniverseContactNode] {
        UniverseContactNode.buildFrom(
            contacts: contacts,
            meshPeers: MeshNetworkService.shared.allRadarPeers,
            onlineIds: onlineContactIds
        )
    }
    
    private var filteredNodes: [UniverseContactNode] {
        switch selectedFilter {
        case .all:
            return allUniverseNodes
        case .localOnly:
            return allUniverseNodes.filter { $0.connectionType == .localMeshOffline }
        case .internetOnly:
            return allUniverseNodes.filter { $0.connectionType == .internetRelay }
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                MyaowColor.charcoal
                    .ignoresSafeArea()
                
                ScrollView {
                VStack(spacing: 20) {
                    // 1. Header con Título & Botón de Radio
                    headerView
                    
                    // 2. Filtro de Espacio (Todos / Solo Local / Por Internet)
                    filterPillBar
                        .padding(.horizontal, 20)
                    
                    Spacer(minLength: 0)
                    
                    // 3. Universo de Red Orbital (Tú en el centro + Órbitas Concéntricas)
                    universeCanvasView
                        .frame(maxWidth: .infinity)
                        .frame(height: 380)
                        .clipped()
                    
                    Spacer(minLength: 0)
                    
                    // 4. Tarjeta Informativa de Conectividad Real
                    universeInfoCard
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $activeConversationForNavigation) { conv in
                ChatDetailView(conversation: conv)
            }
            .sheet(item: $selectedContactNode) { node in
                RadarQuickInteractionSheet(node: node) { conv in
                    activeConversationForNavigation = conv
                }
            }
            .sheet(isPresented: $showingWalkieTalkie) {
                WalkieTalkieOverlayView()
            }
            .onAppear {
                withAnimation(.linear(duration: 10.0).repeatForever(autoreverses: false)) {
                    radarSweepAngle = 360
                }
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    centerPulseScale = 1.35
                    centerPulseOpacity = 0.0
                }
                MeshNetworkService.shared.startMeshServices()
                fetchOnlinePresence()
            }
            .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                fetchOnlinePresence()
            }
        }
    }
    
    // MARK: - Header
    private var headerView: some View {
        MyaowScreenHeader(title: "Cerca de ti", subtitle: "Un pequeño mundo por descubrir.") {
            Menu {
                Button { showingWalkieTalkie = true } label: { Label("Walkie-talkie", systemImage: "waveform") }
                Button { MeshNetworkService.shared.startMeshServices(); fetchOnlinePresence() } label: { Label("Actualizar", systemImage: "arrow.clockwise") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20)).foregroundStyle(MyaowColor.textPrimary).frame(width: 44, height: 48)
            }
            .accessibilityLabel("Opciones de red")
        }
    }

    // MARK: - Filtro de Espacio
    private var filterPillBar: some View {
        HStack(spacing: 8) {
            ForEach(UniverseFilter.allCases) { filter in
                let isSelected = selectedFilter == filter
                
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .light)
                    gen.impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedFilter = filter
                    }
                }) {
                    Text(filter.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isSelected ? MyaowColor.charcoal : MyaowColor.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(isSelected ? MyaowColor.textPrimary : MyaowColor.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(isSelected ? Color.clear : Color.white.opacity(0.06), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
        }
    }
    
    // MARK: - Universo de Red Orbital (Canvas)
    private var universeCanvasView: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            if w > 50 && h > 50 {
                let center = CGPoint(x: w / 2, y: h / 2)
                let maxRadius = min(w, h) * 0.44
                
                ZStack {
                    // 1. Haz de Barrido Radar Giratorio
                    AngularGradient(
                        gradient: Gradient(colors: [
                            MyaowColor.orange.opacity(0.18),
                            MyaowColor.orange.opacity(0.04),
                            Color.clear,
                            Color.clear
                        ]),
                        center: .center
                    )
                    .frame(width: maxRadius * 2, height: maxRadius * 2)
                    .clipShape(Circle())
                    .rotationEffect(Angle(degrees: radarSweepAngle))
                    .position(center)
                    
                    // 2. Órbitas Concéntricas (Local Mesh, Internet Relay, Fuera de línea)
                    ForEach([0.42, 0.72, 0.94], id: \.self) { fraction in
                        Circle()
                            .stroke(
                                fraction == 0.42 ? MyaowColor.statusGreen.opacity(0.25) : Color.white.opacity(0.08),
                                style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                            )
                            .frame(width: maxRadius * 2 * fraction, height: maxRadius * 2 * fraction)
                            .position(center)
                    }
                    
                    // 3. Líneas de Conexión y Nodos Reales
                    if filteredNodes.isEmpty {
                        VStack(spacing: 6) {
                            Text("Buscando dispositivos...")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(Color(hex: "#8E8E93"))
                            Text("Los contactos y pares reales aparecerán en las órbitas")
                                .font(.system(size: 14))
                                .foregroundColor(Color(hex: "#636366"))
                        }
                        .offset(y: 85)
                    } else {
                        ForEach(filteredNodes) { node in
                            let radians = node.angleDegrees * .pi / 180
                            let dist = maxRadius * node.connectionType.orbitRadiusFraction
                            let nodeX = center.x + CGFloat(cos(radians) * dist)
                            let nodeY = center.y + CGFloat(sin(radians) * dist)
                            
                            Path { p in
                                p.move(to: center)
                                p.addLine(to: CGPoint(x: nodeX, y: nodeY))
                            }
                            .stroke(node.connectionType.badgeColor.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                            
                            RadarContactNodeView(node: node) {
                                selectedContactNode = node
                            }
                            .position(x: nodeX, y: nodeY)
                        }
                    }
                    
                    // 4. Centro del Universo: TÚ
                    ZStack {
                        Circle()
                            .stroke(MyaowColor.orange.opacity(centerPulseOpacity), lineWidth: 1.5)
                            .frame(width: 70, height: 70)
                            .scaleEffect(centerPulseScale)
                        
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#1E1E22"))
                                .frame(width: 58, height: 58)
                                .overlay(
                                    Circle().stroke(MyaowColor.orange, lineWidth: 2)
                                )
                                .shadow(color: MyaowColor.orange.opacity(0.4), radius: 10)
                            
                            let currentMood = MyaowCatState(rawValue: IdentityManager.shared.currentIdentity.avatarStateName) ?? .friendly
                            MyaowCatView(
                                state: currentMood,
                                style: .darkOnOrange,
                                size: 42,
                                isInteractive: false
                            )
                        }
                    }
                    .position(center)
                }
            }
        }
    }
    
    // MARK: - Tarjeta Informativa de Nodos Reales
    private var universeInfoCard: some View {
        let count = allUniverseNodes.count
        let localCount = allUniverseNodes.filter { $0.connectionType == .localMeshOffline }.count
        
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(count > 0 ? MyaowColor.statusGreen.opacity(0.15) : MyaowColor.orange.opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Circle()
                    .fill(count > 0 ? MyaowColor.statusGreen : MyaowColor.orange)
                    .frame(width: 10, height: 10)
                    .shadow(color: count > 0 ? MyaowColor.statusGreen : MyaowColor.orange, radius: 4)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(count > 0 ? "\(count) contacto(s) en tu red (\(localCount) local)" : "Buscando conexiones")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(count > 0 ? "Toca cualquier contacto para mandar mensaje, zumbido o llamada." : "Las personas disponibles aparecerán aquí. Acércate a otro dispositivo con Myaow.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#8E8E93"))
            }
            
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "#18181A"))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
