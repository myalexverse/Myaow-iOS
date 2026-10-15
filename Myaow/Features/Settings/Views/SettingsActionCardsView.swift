import SwiftUI

public struct SettingsActionCardsView: View {
    var activeSessions: [[String: Any]]
    
    public init(activeSessions: [[String: Any]]) {
        self.activeSessions = activeSessions
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            // Protection Card
            actionCard(
                icon: "shield.checkerboard",
                iconColor: MyaowColor.statusGreen,
                title: "Protección Activa",
                subtitle: "Tus datos están cifrados de extremo a extremo.",
                actionText: "Verificar"
            )
            
            // Customize Card
            NavigationLink(destination: AppearanceSettingsView()) {
                actionCard(
                    icon: "paintpalette.fill",
                    iconColor: MyaowColor.purple,
                    title: "Personalización",
                    subtitle: "Temas, colores y sonidos de Myaow.",
                    actionText: nil
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // Devices Card
            Button(action: {
                // Future: show devices sheet
            }) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(MyaowColor.indigo.opacity(0.12))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(MyaowColor.indigo)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mis dispositivos")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("\(max(1, activeSessions.count)) dispositivo\(activeSessions.count == 1 ? "" : "s") conectado\(activeSessions.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.35))
                    }
                    
                    Spacer()
                    
                    // Device icons with green connection dots
                    HStack(spacing: 8) {
                        deviceIcon(systemName: "iphone", isActive: true)
                        deviceIcon(systemName: "desktopcomputer", isActive: activeSessions.count > 1)
                        deviceIcon(systemName: "applewatch", isActive: activeSessions.count > 2)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(MyaowColor.indigo.opacity(0.6))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())
            
            // 🧡 Thanks banner
            SettingsThanksBannerView()
        }
        .padding(.horizontal, 20)
    }
    
    private func actionCard(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        actionText: String?
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.35))
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let actionText = actionText {
                Text(actionText)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(MyaowColor.orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(MyaowColor.orange.opacity(0.12))
                    .clipShape(Capsule())
            }
            
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.15))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    private func deviceIcon(systemName: String, isActive: Bool) -> some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 32, height: 32)
                
                Image(systemName: systemName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isActive ? .white : Color.white.opacity(0.2))
            }
            
            if isActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().stroke(MyaowColor.background, lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
        }
    }
}

public struct SettingsThanksBannerView: View {
    public init() {}
    public var body: some View {
        ZStack(alignment: .leading) {
            // Background card
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(MyaowColor.orange.opacity(0.15), lineWidth: 1)
                )
            
            HStack(spacing: 0) {
                // Cat on skateboard — larger, overflowing slightly
                Image("CatSkateboardBanner")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 90, height: 90)
                    .offset(x: -4, y: -6)
                
                VStack(alignment: .leading, spacing: 5) {
                    Text("Gracias por ser parte de Myaow ❤️")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Tu apoyo nos ayuda a seguir construyendo un lugar más privado y humano.")
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 4)
                
                Spacer(minLength: 8)
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(MyaowColor.orange.opacity(0.5))
                    .padding(.trailing, 6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(minHeight: 88)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
