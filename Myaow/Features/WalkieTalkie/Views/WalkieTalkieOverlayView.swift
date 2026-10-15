import SwiftUI

/// Chat and legacy radar entry points use the same local Radio experience.
public struct WalkieTalkieOverlayView: View {
    @Environment(\.dismiss) private var dismiss
    public var targetContactName: String? = nil
    public var isTargetVerified: Bool = true
    public var targetContactID: String? = nil

    public var body: some View {
        NavigationStack {
            RadioView(contactHint: targetContactName, contactIDHint: targetContactID)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button("Cerrar") { dismiss() } }
                }
        }
    }
}
