import SwiftUI

struct ConversationDecorationModifier: ViewModifier {
    let conversation: ConversationModel?
    private var selection: ChatDecoration? {
        guard let conversation else { return nil }
        return conversation.localDecorationRaw.flatMap(ChatDecoration.init(rawValue:))
            ?? ChatDecorationEvent.decode(conversation.sharedDecorationJSON)?.decoration
    }
    func body(content: Content) -> some View {
        content
            .background {
                if let selection {
                    ConversationAtmosphereBackdrop(decoration: selection)
                }
            }
            .onAppear { update() }
            .onChange(of: conversation?.id) { _, _ in update() }
            .onChange(of: selection) { _, _ in update() }
            .onDisappear {
                let store = AppAtmosphereStore.shared
                if store.activeConversationID == conversation?.id {
                    store.activeConversationID = nil; store.activeDecoration = nil
                }
            }
    }
    private func update() {
        AppAtmosphereStore.shared.activeConversationID = conversation?.id
        AppAtmosphereStore.shared.activeDecoration = selection
    }
}

/// This layer travels with the destination during push, pop and cancelled
/// interactive gestures. The root atmosphere stays underneath, unchanged.
private struct ConversationAtmosphereBackdrop: View {
    let decoration: ChatDecoration
    @State private var store = AppAtmosphereStore.shared
    var body: some View {
        ZStack {
            MyaowColor.charcoal
            if let resource = decoration.resource {
                VideoWallpaperView(resource: resource,
                    motionEnabled: store.motion && CallSessionService.shared.callState == .idle && !WalkieTalkieService.shared.transport.isActive,
                    playbackSuspended: store.previewingDecoration)
                Color.black.opacity(min(0.9, max(0.35, store.shade)))
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
