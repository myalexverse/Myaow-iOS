import SwiftUI

public struct SettingsIdentityCardView: View {
    var identityManager: IdentityManager
    var currentCatState: MyaowCatState
    var statusText: String
    @Binding var showingPhotoPickerSheet: Bool
    @Binding var showingEditProfile: Bool
    @Binding var showingEmotionPickerSheet: Bool
    
    public init(
        identityManager: IdentityManager,
        currentCatState: MyaowCatState,
        statusText: String,
        showingPhotoPickerSheet: Binding<Bool>,
        showingEditProfile: Binding<Bool>,
        showingEmotionPickerSheet: Binding<Bool>
    ) {
        self.identityManager = identityManager
        self.currentCatState = currentCatState
        self.statusText = statusText
        self._showingPhotoPickerSheet = showingPhotoPickerSheet
        self._showingEditProfile = showingEditProfile
        self._showingEmotionPickerSheet = showingEmotionPickerSheet
    }
    
    public var body: some View {
        HStack(spacing: 16) {
            // Avatar (tappable)
            Button(action: { showingPhotoPickerSheet = true }) {
                ProfileAvatarView(
                    avatarUrl: identityManager.profilePhotoUrl,
                    avatarImageData: identityManager.profilePhotoData,
                    catState: currentCatState,
                    size: 72,
                    showMiniCat: true,
                    animateTransition: true
                )
                .shadow(color: MyaowColor.orange.opacity(0.3), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Identity info
            VStack(alignment: .leading, spacing: 4) {
                // Name + edit
                Button(action: { showingEditProfile = true }) {
                    HStack(spacing: 5) {
                        Text(identityManager.currentIdentity.displayName)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.25))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // Myaow ID (tappable to copy)
                Button(action: {
                    UIPasteboard.general.string = identityManager.currentIdentity.customUsername.map { "@\($0)" } ?? identityManager.currentIdentity.myaowId
                    let gen = UINotificationFeedbackGenerator()
                    gen.notificationOccurred(.success)
                }) {
                    HStack(spacing: 4) {
                        Text(identityManager.currentIdentity.customUsername.map { "@\($0)" } ?? identityManager.currentIdentity.myaowId)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(MyaowColor.orange)
                        
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(MyaowColor.orange.opacity(0.6))
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                // State pill + availability
                HStack(spacing: 8) {
                    Button(action: { showingEmotionPickerSheet = true }) {
                        HStack(spacing: 4) {
                            MyaowCatView(state: currentCatState, style: .darkOnOrange, size: 16, isInteractive: false)
                            Text(currentCatState.displayName)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(MyaowColor.orange)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(MyaowColor.orange.opacity(0.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(MyaowColor.orange.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(statusText)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.35))
                    }
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
    }
}
