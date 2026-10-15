import SwiftUI

struct GroupPanel<Content: View>: View {
    var accented = false
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [accented ? Color(hex: "282018") : MyaowColor.surface, MyaowColor.surface.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(accented ? MyaowColor.orange.opacity(0.2) : MyaowColor.borderSubtle, lineWidth: 1))
    }
}
struct GroupEyebrow: View {
    let title: String
    var body: some View { Text(title.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.8).foregroundStyle(MyaowColor.textSecondary) }
}
struct GroupBadge: View {
    let title: String
    let symbol: String
    var accent = false
    var body: some View {
        Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
            .foregroundStyle(accent ? MyaowColor.orange : MyaowColor.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(accent ? MyaowColor.orange.opacity(0.1) : Color.white.opacity(0.045), in: Capsule())
    }
}
struct GroupPrimaryStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 16, weight: .semibold)).foregroundStyle(Color.black)
            .frame(maxWidth: .infinity).frame(minHeight: 52)
            .background(MyaowColor.orange, in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: configuration.isPressed)
    }
}
extension SpaceCategory {
    var symbol: String {
        switch self {
        case .party: "sparkles"
        case .trip: "mountain.2"
        case .workshop: "wrench.and.screwdriver"
        case .design: "pencil.and.outline"
        case .family: "house"
        case .general: "person.3"
        }
    }
}
