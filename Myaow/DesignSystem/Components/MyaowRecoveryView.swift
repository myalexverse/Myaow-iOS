import SwiftUI

struct MyaowRecoveryView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ZStack {
            MyaowColor.charcoal.ignoresSafeArea()
            VStack(spacing: 20) {
                MyaowCatView(state: .protected, size: 80, isInteractive: false)
                Text("Vamos a cuidar tus datos")
                    .font(.system(size: 25, weight: .semibold))
                Text(message).font(.system(size: 16)).foregroundStyle(MyaowColor.textSecondary)
                MyaowPillButton("Volver a intentar", action: retry)
                Text("No borres ni reinstales Myaow para resolver este error.")
                    .font(.system(size: 13)).foregroundStyle(MyaowColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(MyaowColor.textPrimary)
            .padding(30)
        }
        .preferredColorScheme(.dark)
    }
}
