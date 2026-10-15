//
//  CreateSpaceModalView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//  Rediseño: Flujo de 3 pasos — Social, inmediato, cálido
//

import SwiftUI
import SwiftData

// MARK: - Propósito del Grupo
public enum GroupPurpose: String, CaseIterable, Identifiable, Sendable {
    case study = "Estudiar"
    case project = "Proyecto"
    case event = "Evento"
    case trip = "Viaje"
    case family = "Familia"
    case home = "Casa"
    case team = "Equipo"
    case create = "Crear algo"
    case friends = "Amigos"
    case other = "Otro"
    
    public var id: String { rawValue }
    
    public var emoji: String {
        switch self {
        case .study: return "📚"
        case .project: return "💼"
        case .event: return "🎉"
        case .trip: return "✈️"
        case .family: return "👨‍👩‍👧"
        case .home: return "🏠"
        case .team: return "⚽"
        case .create: return "🎨"
        case .friends: return "💬"
        case .other: return "＋"
        }
    }
    
    public var catState: MyaowCatState {
        switch self {
        case .study: return .thinking
        case .project: return .busy
        case .event: return .party
        case .trip: return .curious
        case .family: return .friendly
        case .home: return .calm
        case .team: return .playful
        case .create: return .curious
        case .friends: return .happy
        case .other: return .friendly
        }
    }
    
    public var spaceCategory: SpaceCategory {
        switch self {
        case .study: return .workshop
        case .project: return .design
        case .event: return .party
        case .trip: return .trip
        case .family: return .family
        case .home: return .family
        case .team: return .general
        case .create: return .design
        case .friends: return .general
        case .other: return .general
        }
    }
    
    /// Misiones sugeridas automáticamente por Myaow
    public var suggestedMissions: [String] {
        switch self {
        case .study:
            return ["Definir temas a estudiar", "Repartir capítulos", "Fijar fecha de repaso", "Compartir resúmenes"]
        case .project:
            return ["Definir entregables", "Asignar responsables", "Fijar fecha límite", "Revisar avances"]
        case .event:
            return ["Definir lugar y hora", "Crear lista de invitados", "Comprar lo necesario", "Confirmar asistencia"]
        case .trip:
            return ["Reservar hospedaje", "Comprar boletos", "Definir transporte", "Hacer itinerario"]
        case .family:
            return ["Organizar reunión", "Definir pendientes", "Compartir fotos"]
        case .home:
            return ["Lista de compras", "Repartir tareas", "Pagar servicios"]
        case .team:
            return ["Definir horario", "Organizar próximo partido", "Confirmar asistencia"]
        case .create:
            return ["Definir concepto", "Repartir tareas creativas", "Fijar fecha de entrega", "Compartir referencias"]
        case .friends:
            return []
        case .other:
            return []
        }
    }
}

// MARK: - Flujo de Creación de Grupo (3 pasos)
public struct CreateSpaceModalView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    public var onSpaceCreated: (GroupSpaceModel) -> Void
    
    // Estado del wizard
    @State private var currentStep: Int = 1
    @State private var selectedPurpose: GroupPurpose? = nil
    @State private var groupName: String = ""
    @State private var selectedCatState: MyaowCatState = .friendly
    @State private var isCreating: Bool = false
    
    // Contacts for invite step
    @Query private var contacts: [ContactModel]
    @State private var selectedContactIds: Set<String> = []
    
    public init(onSpaceCreated: @escaping (GroupSpaceModel) -> Void) {
        self.onSpaceCreated = onSpaceCreated
    }
    
    public var body: some View {
        ZStack {
            // Fondo
            Color(hex: "#0A0A0C")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Nav bar
                navBar
                
                // Progress dots
                progressDots
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                
                // Content
                TabView(selection: $currentStep) {
                    stepOnePurpose.tag(1)
                    stepTwoName.tag(2)
                    stepThreeInvite.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentStep)
            }
        }
        .disabled(true)
    }
    
    // MARK: - Nav Bar
    private var navBar: some View {
        HStack {
            Button(action: {
                if currentStep > 1 {
                    withAnimation { currentStep -= 1 }
                } else {
                    dismiss()
                }
            }) {
                Image(systemName: currentStep > 1 ? "chevron.left" : "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Text("Crear grupo")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Spacer()
            
            // Invisible spacer for centering
            Color.clear.frame(width: 34, height: 34)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }
    
    // MARK: - Progress Dots
    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(1...3, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? MyaowColor.orange : Color.white.opacity(0.1))
                    .frame(width: step == currentStep ? 24 : 8, height: 4)
                    .animation(.spring(response: 0.3), value: currentStep)
            }
        }
    }
    
    // MARK: - Paso 1: ¿Qué van a hacer juntos?
    private var stepOnePurpose: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Mascota animada
                MyaowCatView(
                    state: selectedPurpose?.catState ?? .friendly,
                    style: .darkOnOrange,
                    size: 72,
                    isInteractive: true
                )
                .shadow(color: MyaowColor.orange.opacity(0.3), radius: 16)
                .padding(.top, 12)
                
                // Pregunta principal
                VStack(spacing: 6) {
                    Text("¿Qué van a hacer")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("juntos?")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(MyaowColor.orange)
                }
                
                Text("Puedes cambiarlo después")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.3))
                
                // Grid de propósitos 3x4
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(GroupPurpose.allCases) { purpose in
                        purposeCard(purpose)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                
                Spacer(minLength: 80)
            }
        }
        .overlay(alignment: .bottom) {
            // Botón continuar
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(hex: "#0A0A0C").opacity(0), Color(hex: "#0A0A0C")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                
                Button(action: {
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    withAnimation { currentStep = 2 }
                }) {
                    Text("Continuar")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            selectedPurpose != nil
                                ? MyaowColor.orange
                                : Color.white.opacity(0.08)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(selectedPurpose == nil)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .background(Color(hex: "#0A0A0C"))
            }
        }
    }
    
    // MARK: - Purpose Card
    private func purposeCard(_ purpose: GroupPurpose) -> some View {
        let isSelected = selectedPurpose == purpose
        
        return Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            withAnimation(.spring(response: 0.25)) {
                selectedPurpose = purpose
                selectedCatState = purpose.catState
            }
        }) {
            VStack(spacing: 8) {
                Text(purpose.emoji)
                    .font(.system(size: 28))
                
                Text(purpose.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? .white : Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected
                          ? MyaowColor.orange.opacity(0.2)
                          : Color.white.opacity(0.04)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                isSelected
                                    ? MyaowColor.orange.opacity(0.6)
                                    : Color.white.opacity(0.06),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Paso 2: ¿Cómo se llama?
    private var stepTwoName: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Mascota que cambia según propósito
            MyaowCatView(
                state: selectedCatState,
                style: .darkOnOrange,
                size: 80,
                isInteractive: true
            )
            .shadow(color: MyaowColor.orange.opacity(0.3), radius: 16)
            
            // Pregunta
            Text("¿Cómo se llama?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            // Input del nombre
            TextField("Ej. Viaje a Oaxaca", text: $groupName)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    groupName.isEmpty
                                        ? Color.white.opacity(0.08)
                                        : MyaowColor.orange.opacity(0.4),
                                    lineWidth: 1
                                )
                        )
                )
                .padding(.horizontal, 32)
            
            Text("También puedes cambiarlo después")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color.white.opacity(0.3))
            
            // Selector de personalidad de la mascota
            VStack(spacing: 10) {
                Text("Personaliza tu mascota")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.4))
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(catStateOptions, id: \.self) { state in
                            let isSelected = selectedCatState == state
                            Button(action: {
                                let gen = UIImpactFeedbackGenerator(style: .light)
                                gen.impactOccurred()
                                withAnimation { selectedCatState = state }
                            }) {
                                VStack(spacing: 4) {
                                    MyaowCatView(
                                        state: state,
                                        style: .darkOnOrange,
                                        size: 36,
                                        isInteractive: false
                                    )
                                    .opacity(isSelected ? 1.0 : 0.4)
                                    
                                    Text(state.displayName)
                                        .font(.system(size: 9, weight: .medium, design: .rounded))
                                        .foregroundColor(isSelected ? MyaowColor.orange : Color.white.opacity(0.3))
                                }
                                .padding(6)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(isSelected ? MyaowColor.orange.opacity(0.1) : Color.clear)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
            
            Spacer()
            
            // Botón continuar
            Button(action: {
                let gen = UIImpactFeedbackGenerator(style: .medium)
                gen.impactOccurred()
                withAnimation { currentStep = 3 }
            }) {
                Text("Continuar")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        groupName.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.white.opacity(0.08)
                            : MyaowColor.orange
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }
    
    private var catStateOptions: [MyaowCatState] {
        [.happy, .friendly, .curious, .playful, .party, .calm, .busy, .thinking]
    }
    
    private var limitedContacts: [ContactModel] {
        let maxCount = min(contacts.count, 10)
        return maxCount > 0 ? Array(contacts[0..<maxCount]) : []
    }
    
    // MARK: - Paso 3: ¡Tu grupo está listo!
    private var stepThreeInvite: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Header de éxito
                VStack(spacing: 12) {
                    MyaowCatView(
                        state: selectedCatState,
                        style: .darkOnOrange,
                        size: 72,
                        isInteractive: true
                    )
                    .shadow(color: MyaowColor.orange.opacity(0.4), radius: 20)
                    
                    Text(groupName.isEmpty ? "Tu grupo" : groupName)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("¡Tu grupo está listo!")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(MyaowColor.orange)
                }
                .padding(.top, 16)
                
                // Invitar sección
                VStack(alignment: .leading, spacing: 12) {
                    Text("¿A quién quieres invitar?")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.6))
                        .padding(.horizontal, 24)
                    
                    // Contactos
                    ForEach(limitedContacts, id: \.myaowId) { (contact: ContactModel) in
                        let isSelected = selectedContactIds.contains(contact.myaowId)
                        Button(action: {
                            let gen = UIImpactFeedbackGenerator(style: .light)
                            gen.impactOccurred()
                            if isSelected {
                                selectedContactIds.remove(contact.myaowId)
                            } else {
                                selectedContactIds.insert(contact.myaowId)
                            }
                        }) {
                            HStack(spacing: 12) {
                                MyaowCatView(
                                    state: MyaowCatState(rawValue: contact.avatarCatState) ?? .friendly,
                                    style: .darkOnOrange,
                                    size: 36,
                                    isInteractive: false
                                )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.displayName)
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text(contact.myaowId)
                                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                                        .foregroundColor(Color.white.opacity(0.3))
                                }
                                
                                Spacer()
                                
                                ZStack {
                                    Circle()
                                        .stroke(isSelected ? MyaowColor.orange : Color.white.opacity(0.15), lineWidth: 2)
                                        .frame(width: 24, height: 24)
                                    
                                    if isSelected {
                                        Circle()
                                            .fill(MyaowColor.orange)
                                            .frame(width: 24, height: 24)
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(isSelected ? MyaowColor.orange.opacity(0.08) : Color.white.opacity(0.03))
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 20)
                    }
                }
                
                // Métodos alternativos de invitación
                VStack(spacing: 10) {
                    // Cerca (P2P/AirDrop style)
                    inviteMethodRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Cerca",
                        subtitle: "Acerca tu iPhone al de tus amigos",
                        isProminent: true
                    )
                    
                    inviteMethodRow(
                        icon: "qrcode",
                        title: "Escanear QR",
                        subtitle: "Comparte un código QR",
                        isProminent: false
                    )
                    
                    inviteMethodRow(
                        icon: "at",
                        title: "Compartir ID",
                        subtitle: "Envía el ID de tu grupo",
                        isProminent: false
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                
                Spacer(minLength: 80)
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 10) {
                LinearGradient(
                    colors: [Color(hex: "#0A0A0C").opacity(0), Color(hex: "#0A0A0C")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                
                VStack(spacing: 10) {
                    // Crear grupo
                    Button(action: createGroup) {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.8)
                            }
                            Text(selectedContactIds.isEmpty ? "Crear grupo" : "Crear e invitar")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(MyaowColor.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(isCreating)
                    
                    // Ahora no
                    Button(action: {
                        selectedContactIds.removeAll()
                        createGroup()
                    }) {
                        Text("Ahora no")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .background(Color(hex: "#0A0A0C"))
            }
        }
    }
    
    // MARK: - Invite Method Row
    private func inviteMethodRow(icon: String, title: String, subtitle: String, isProminent: Bool) -> some View {
        Button(action: {
            let gen = UIImpactFeedbackGenerator(style: .light)
            gen.impactOccurred()
            // TODO: Implement invite methods
        }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isProminent ? MyaowColor.orange : Color.white.opacity(0.5))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(isProminent ? MyaowColor.orange.opacity(0.15) : Color.white.opacity(0.05))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.35))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.2))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isProminent ? Color.white.opacity(0.05) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                isProminent ? MyaowColor.orange.opacity(0.2) : Color.white.opacity(0.05),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Create Group
    private func createGroup() {
        guard !groupName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isCreating = true
        
        let purpose = selectedPurpose ?? .friends
        
        Task {
            // Crear en el servidor
            let _ = await GroupsNetworkService.shared.createGroup(
                name: groupName,
                category: purpose.spaceCategory.rawValue
            )
            
            await MainActor.run {
                let gen = UINotificationFeedbackGenerator()
                gen.notificationOccurred(.success)
                
                let groupId = UUID()
                
                // Generar misiones automáticas según el propósito
                let autoMissions = purpose.suggestedMissions.map { title in
                    GroupMissionModel(
                        groupId: groupId,
                        title: title,
                        assigneeDisplayName: "Sin asignar",
                        dueLabel: "Esta semana"
                    )
                }
                
                let newGroup = GroupSpaceModel(
                    id: groupId,
                    title: groupName,
                    description: "",
                    category: purpose.spaceCategory,
                    isTemporary: false,
                    memberCount: 1 + selectedContactIds.count,
                    connectedCount: 1,
                    isMeshActive: true,
                    lastMessage: "¡Grupo creado! Listo para empezar.",
                    lastMessageTime: "Ahora",
                    pulseStatusText: "Grupo activo",
                    members: [
                        SpaceMemberModel(
                            displayName: IdentityManager.shared.currentIdentity.displayName,
                            myaowId: IdentityManager.shared.currentIdentity.myaowId,
                            role: "Creador",
                            isOnline: true,
                            moodEmoji: "😸",
                            moodLabel: "Listo",
                            catState: selectedCatState
                        )
                    ],
                    missions: autoMissions,
                    streakDays: 1
                )
                
                isCreating = false
                onSpaceCreated(newGroup)
                dismiss()
            }
        }
    }
}
