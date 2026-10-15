import SwiftUI

/// Only an intentional scroll changes whether the conversation follows new messages.
/// Lazy row measurements, keyboard insets and navigation layout must not detach it.
struct ChatTimelineBehavior: ViewModifier {
    @Binding var followsLatest: Bool
    @State private var isUserScrolling = false

    func body(content: Content) -> some View {
        content
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(.bottom, for: .alignment)
            .defaultScrollAnchor(followsLatest ? .bottom : nil, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                isNearBottom(geometry)
            } action: { _, nearBottom in
                if isUserScrolling { followsLatest = nearBottom }
            }
            .onScrollPhaseChange { _, phase, context in
                switch phase {
                case .interacting, .decelerating:
                    isUserScrolling = true
                    followsLatest = isNearBottom(context.geometry)
                case .idle:
                    if isUserScrolling { followsLatest = isNearBottom(context.geometry) }
                    isUserScrolling = false
                case .animating:
                    isUserScrolling = false
                default:
                    break
                }
            }
    }

    private func isNearBottom(_ geometry: ScrollGeometry) -> Bool {
        let bottom = geometry.contentSize.height + geometry.contentInsets.bottom
        let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
        return bottom - visibleBottom <= 80
    }
}
