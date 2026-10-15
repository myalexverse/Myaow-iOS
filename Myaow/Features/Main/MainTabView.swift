//
//  MainTabView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public enum MyaowTab: Int, CaseIterable {
    case chats = 0
    case contacts = 1
    case groups = 2
    case radar = 3
    case profile = 4
    
    public var title: String {
        switch self {
        case .chats: return "Chats"
        case .contacts: return "Tu gente"
        case .groups: return "Grupos"
        case .radar: return "Radio"
        case .profile: return "Tú"
        }
    }
    
    public var iconName: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right"
        case .contacts: return "person.2"
        case .groups: return "square.stack.3d.up"
        case .radar: return "dot.radiowaves.left.and.right"
        case .profile: return "person.crop.circle"
        }
    }
}

public struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Query private var callContacts: [ContactModel]
    @State private var selectedTab: MyaowTab = .chats
    @State private var didSelectLaunchTab = false
    @State private var callService = CallSessionService.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
          Group {
            switch selectedTab {
            case .chats: ChatsListView()
            case .contacts: ContactsListView()
            case .groups: GroupsListView()
            case .radar: RadioView()
            case .profile: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !TabBarManager.shared.isHidden {
              VStack(spacing: 0) {
                customFloatingTabBar
                if DesignPreviewData.isEnabled {
                    Text("VISTA DE DISEÑO · DATOS FICTICIOS")
                        .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.3)
                        .foregroundStyle(MyaowColor.textSecondary).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
              }.background(AppAtmosphereStyle.bar)
            }
        }
        .background { AppAtmosphereBackdrop() }
        .overlay(alignment: .top) {
            if MyaowNudgeService.shared.showingNudgeEffect {
                MyaowNudgeOverlayView(senderName: MyaowNudgeService.shared.nudgeSenderName)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background {
            if callService.callState == .connected && callService.callType != .radio {
                CallPictureInPictureAnchor().frame(width: 100, height: 100)
            }
        }
        .overlay { if callService.isMinimized && callService.callState != .idle { MinimizedCallBubble() } }
        .task(id: "\(callService.callState.rawValue)|\(scenePhase)") {
            guard callService.callState == .connected, scenePhase == .active else { WebRTCPeerService.shared.clearVoiceLevel(); return }
            while !Task.isCancelled {
                WebRTCPeerService.shared.sampleRemoteVoice()
                do { try await Task.sleep(for: .milliseconds(80)) } catch { break }
            }
            WebRTCPeerService.shared.clearVoiceLevel()
        }
        .fullScreenCover(isPresented: Binding(
            get: { callService.callState != .idle && !callService.isMinimized },
            set: { if !$0 && !callService.isMinimized { callService.dismissCall() } }
        )) {
            CallOverlayView()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await APNsNotificationManager.shared.refreshRegistration()
            while !Task.isCancelled {
                if OnlineMessagingService.shared.status == .online {
                    CallSystemCoordinator.shared.updateContacts(callContacts)
                    APNsNotificationManager.shared.synchronizeDevice()
                    await ScheduledMessagesService.shared.refresh()
                }
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        .onChange(of: callContacts.map { $0.myaowId + $0.displayName + $0.publicKeyHex + $0.avatarCatState }.sorted()) { _, _ in
            CallSystemCoordinator.shared.updateContacts(callContacts)
            callService.refreshContactExpression()
        }
        .onAppear {
            if !didSelectLaunchTab {
                didSelectLaunchTab = true
                if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--groups-preview") { selectedTab = .groups }
                if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--appearance-preview") { selectedTab = .profile }
            }
            CallSystemCoordinator.shared.updateContacts(callContacts)
            callService.resolveContact = { id in
                let contacts = (try? modelContext.fetch(FetchDescriptor<ContactModel>())) ?? []
                return contacts.first { $0.myaowId == id }?.displayName
            }
            MyaowBackendEngine.shared.configureIncomingListener(context: modelContext)
            #if DEBUG
            if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--incoming-maullido-preview") {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    MyaowNudgeService.shared.receive(senderName: "Sofía", text: "[NUDGE:party] Fiesta", timestamp: Date())
                }
            }
            #endif
            #if DEBUG && targetEnvironment(simulator)
            if let contact = callContacts.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    callService.previewSystemIncomingCall(contactID: contact.myaowId, name: contact.displayName)
                }
            }
            #endif
        }
    }
    
    // MARK: - Tab Bar Flotante
    private var customFloatingTabBar: some View {
        HStack(spacing: 0) {
            ForEach(MyaowTab.allCases, id: \.self) { tab in
                Button {
                    guard selectedTab != tab else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    selectedTab = tab
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 21, weight: selectedTab == tab ? .semibold : .regular))
                            .frame(width: 50, height: 30)
                            .background(selectedTab == tab ? MyaowColor.orange.opacity(0.13) : .clear, in: Capsule())
                        Text(tab.title).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(selectedTab == tab ? MyaowColor.orange : MyaowColor.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .background(AppAtmosphereStyle.bar)
        .overlay(alignment: .top) { Rectangle().fill(MyaowColor.borderSubtle).frame(height: 0.5) }
    }

}

#Preview {
    MainTabView()
        .modelContainer(for: [ConversationModel.self, MessageModel.self, ContactModel.self, MeshNodeModel.self], inMemory: true)
}
