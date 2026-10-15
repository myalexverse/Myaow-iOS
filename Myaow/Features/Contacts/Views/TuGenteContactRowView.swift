import SwiftUI

public struct TuGenteContactRowView: View {
    public let contact: ContactModel
    public init(contact: ContactModel) { self.contact = contact }
    private var nearby: Bool { MeshNetworkService.shared.connectedPeers.contains { $0.myaowId == contact.myaowId } }
    public var body: some View {
        HStack(spacing: 16) {
            ProfileAvatarView(avatarUrl: contact.avatarUrl, catState: MyaowCatState(rawValue: contact.avatarCatState) ?? .friendly, size: 54, showMiniCat: false, animateTransition: false)
            VStack(alignment: .leading, spacing: 6) {
                Text(contact.displayName).font(.system(size: 17, weight: .semibold)).foregroundStyle(MyaowColor.textPrimary)
                Text(nearby ? "Cerca de ti" : contact.myaowId)
                    .font(.system(size: 13)).foregroundStyle(nearby ? MyaowColor.statusGreen : MyaowColor.textSecondary)
            }
            Spacer()
            Image(systemName: "bubble.left").font(.system(size: 19, weight: .light)).foregroundStyle(MyaowColor.textSecondary)
        }
        .padding(.vertical, 17)
        .contentShape(Rectangle())
    }
}
