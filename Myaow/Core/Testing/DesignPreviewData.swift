import SwiftUI
import SwiftData

/// Opt-in fictional content, restricted to a separate development bundle. Never seeds a user's app.
@MainActor
enum DesignPreviewData {
    static var isEnabled: Bool {
        #if DEBUG
        return Bundle.main.bundleIdentifier == "com.ScendLabs.Myaow.DesignReview" && ProcessInfo.processInfo.arguments.contains("--design-preview")
        #else
        return false
        #endif
    }
    private static var consumedLaunchRoutes = Set<String>()

    /// Launch shortcuts are one-shot. Returning or recreating a view must never
    /// push the preview again or overwrite a user's later navigation choice.
    static func consumeLaunchRoute(_ argument: String) -> Bool {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains(argument) else { return false }
        return consumedLaunchRoutes.insert(argument).inserted
    }

    static func prepare(context: ModelContext) {
        #if DEBUG
        guard isEnabled else { return }
        if ProcessInfo.processInfo.arguments.contains("--living-preview") { AppAtmosphereStore.shared.selection = .lava }
        defer {
            if ProcessInfo.processInfo.arguments.contains("--chat-scroll-check") { prepareTimelineCheck(context: context) }
        }
        UserDefaults.standard.set("localhost:18090", forKey: "myaow_relay_host")
        IdentityManager.shared.currentIdentity.displayName = "Alex"
        IdentityManager.shared.currentIdentity.customUsername = "alex_myaow"
        IdentityManager.shared.currentIdentity.bioStatus = "Haciendo espacio para lo que importa."
        IdentityManager.shared.hasCompletedOnboarding = true
        if ProcessInfo.processInfo.arguments.contains("--auth-review") {
            IdentityManager.shared.isDirectoryRegistrationPending = true
        }
        guard (try? context.fetchCount(FetchDescriptor<ConversationModel>())) == 0 else { return }
        let people: [(String, String, MyaowCatState, String, Int)] = [
            ("Eva Ríos", "MYAOW-DEMO01", .happy, "Nos vemos ahí. Llevo la cámara 📷", 2),
            ("Nico", "MYAOW-DEMO02", .cool, "Esta canción me recordó a ti", 0),
            ("Sofía", "MYAOW-DEMO03", .curious, "¿Un café y me cuentas?", 1),
            ("Dani", "MYAOW-DEMO04", .calm, "Ya llegué a casa. Gracias por hoy.", 0),
            ("Lucía", "MYAOW-DEMO05", .playful, "Te mando las fotos mañana ✨", 0),
            ("Mateo", "MYAOW-DEMO06", .thinking, "Me gusta. Vamos con esa idea.", 0)
        ]
        for (index, item) in people.enumerated() {
            let contact = ContactModel(myaowId: item.1, did: "did:myaow:preview", displayName: item.0, avatarCatState: item.2.rawValue, isMeshNearby: false, isVerified: false)
            context.insert(contact)
            let time = Date().addingTimeInterval(-Double(index * 1900 + 60))
            let conversation = ConversationModel(title: item.0, recipientMyaowId: item.1, unreadCount: item.4, lastMessageSnippet: item.3, lastMessageTimestamp: time, isMeshConnected: false)
            let dialogue: [(String, Bool)] = index == 0 ? [
                ("¿Y si salimos un rato? Encontré un lugar que te va a gustar.", true),
                ("Siempre dices eso y siempre tienes razón.", false),
                ("Tiene café, libros y una terraza enorme.", true),
                ("Perfecto. ¿A las cinco?", false),
                ("A las cinco. Te paso la ubicación en un momento.", true),
                (item.3, false)
            ] : [(item.3, false)]
            conversation.messages = dialogue.enumerated().map { offset, line in
                MessageModel(conversationId: conversation.id, senderId: line.1 ? IdentityManager.shared.currentIdentity.myaowId : item.1,
                    senderName: line.1 ? "Alex" : item.0, isOutgoing: line.1, text: line.0,
                    timestamp: time.addingTimeInterval(Double(offset - dialogue.count) * 90), deliveryStatusRaw: "read")
            }
            context.insert(conversation)
        }
        let group = ConversationModel(title: "Studio Norte", recipientMyaowId: "DEMO-GROUP", isGroup: true, unreadCount: 4, lastMessageSnippet: "Clara: Ya está la primera propuesta", lastMessageTimestamp: Date().addingTimeInterval(-2200), isMeshConnected: false, participantNames: ["Clara", "Nico", "Alex"])
        context.insert(group)
        try? context.save()
        #endif
    }
    #if DEBUG
    private static func prepareTimelineCheck(context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<ConversationModel>())) ?? []
        for (id, title, group) in [("layout-check-direct", "Prueba de historial", false),
                                  ("11111111-1111-1111-1111-111111111111", "Studio Norte", true)] {
            guard !existing.contains(where: { $0.id == id }) else { continue }
            let conversation = ConversationModel(id: id, title: title, recipientMyaowId: "MYAOW-LAYOUT", isGroup: group, isMeshConnected: false)
            context.insert(conversation)
            for index in 1...240 {
                let text = index == 240 ? "FIN DEL HISTORIAL · 240" : "Mensaje \(index). " + String(repeating: "Una conversación con alturas diferentes para revisar el desplazamiento. ", count: index % 5 + 1)
                let message = MessageModel(conversationId: id, senderId: "MYAOW-LAYOUT", senderName: "Eva", isOutgoing: index % 3 == 0,
                    text: index % 17 == 0 ? "[NUDGE:admiration] Fiu miau" : text,
                    timestamp: Date().addingTimeInterval(Double(index - 241) * 120), deliveryStatusRaw: "read",
                    messageTypeRaw: index % 17 == 0 ? "nudge" : "text")
                context.insert(message)
                conversation.messages.append(message)
            }
        }
        try? context.save()
    }

    static func appendTimelineCheckMessage(to conversation: ConversationModel, context: ModelContext) {
        guard isEnabled, ProcessInfo.processInfo.arguments.contains("--chat-scroll-check") else { return }
        let message = MessageModel(conversationId: conversation.id, senderId: "MYAOW-LAYOUT", senderName: "Eva", isOutgoing: false,
            text: "NUEVO MENSAJE DE PRUEBA · \(conversation.messages.count + 1)", deliveryStatusRaw: "read")
        context.insert(message)
        conversation.messages.append(message)
        try? context.save()
    }
    #endif

    static var spaces: [GroupSpaceModel] {
        guard isEnabled else { return [] }
        let owner = IdentityManager.shared.currentIdentity.myaowId
        let groupID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let team = [
            SpaceMemberModel(displayName: "Alex", myaowId: owner, role: "Admin", isOnline: false),
            SpaceMemberModel(displayName: "Clara", myaowId: "MYAOW-PREVIEW-CLARA", isOnline: false, catState: .curious),
            SpaceMemberModel(displayName: "Nico", myaowId: "MYAOW-PREVIEW-NICO", isOnline: false, catState: .cool),
            SpaceMemberModel(displayName: "Eva", myaowId: "MYAOW-PREVIEW-EVA", isOnline: false, catState: .happy),
            SpaceMemberModel(displayName: "Dani", myaowId: "MYAOW-PREVIEW-DANI", isOnline: false, catState: .calm)
        ]
        var tasks = [
            GroupMissionModel(groupId: groupID, title: "Preparar la dirección visual", assigneeMyaowId: owner, assigneeDisplayName: "Alex", dueLabel: "Hoy", priority: .high, creatorMyaowId: owner),
            GroupMissionModel(groupId: groupID, title: "Revisar la primera propuesta", assigneeMyaowId: "MYAOW-PREVIEW-CLARA", assigneeDisplayName: "Clara", dueLabel: "Mañana", creatorMyaowId: owner),
            GroupMissionModel(groupId: groupID, title: "Definir el concepto del proyecto", assigneeMyaowId: "MYAOW-PREVIEW-NICO", assigneeDisplayName: "Nico", dueLabel: "Hoy", isCompleted: true, completedByDisplayName: "Nico", creatorMyaowId: owner),
            GroupMissionModel(groupId: groupID, title: "Reunir las referencias", assigneeMyaowId: "MYAOW-PREVIEW-EVA", assigneeDisplayName: "Eva", dueLabel: "Hoy", isCompleted: true, completedByDisplayName: "Eva", creatorMyaowId: owner)
        ]
        tasks[0].isKey = true
        tasks[0].dueAt = Date().addingTimeInterval(ProcessInfo.processInfo.arguments.contains("--project-critical-preview") ? -3600 : 86400)
        tasks[0].dueTimezone = TimeZone.current.identifier
        tasks[0].cadence = "weekly"
        tasks[1].cadence = "daily"
        tasks[2].completedByMyaowId = "MYAOW-PREVIEW-NICO"
        tasks[2].completedAt = Date().addingTimeInterval(-7200)
        tasks[2].completedDueAt = Date().addingTimeInterval(-3600)
        return [
            GroupSpaceModel(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, title: "Studio Norte", description: "Ideas en movimiento", category: .design, memberCount: 5, connectedCount: 0, isMeshActive: false, lastMessage: "La próxima idea empieza aquí.", lastMessageTime: "", members: team, missions: tasks, streakDays: 0, ownerMyaowId: owner),
            GroupSpaceModel(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, title: "Escapada de octubre", category: .trip, memberCount: 4, connectedCount: 0, isMeshActive: false, lastMessage: "Una ruta. Muchas historias.", lastMessageTime: "", streakDays: 0),
            GroupSpaceModel(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, title: "Los de siempre", category: .family, memberCount: 6, connectedCount: 0, isMeshActive: false, lastMessage: "Nuestro punto de encuentro.", lastMessageTime: "", streakDays: 0)
        ]
    }
}
