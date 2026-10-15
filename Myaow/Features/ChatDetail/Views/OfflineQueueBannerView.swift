import SwiftUI

public struct OfflineQueueBannerView: View {
    public var onRetryTapped: (() -> Void)?
    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash").font(.system(size: 14)).foregroundStyle(MyaowColor.textSecondary)
            Text("Sin conexión. Revisa el estado de envío de tus mensajes.")
                .font(.system(size: 12)).foregroundStyle(MyaowColor.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(MyaowColor.surface, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }
}
