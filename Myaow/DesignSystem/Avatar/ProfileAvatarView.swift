import SwiftUI

public struct ProfileAvatarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let avatarUrl: String?
    let avatarImageData: Data?
    let catState: MyaowCatState
    let size: CGFloat
    let showMiniCat: Bool
    let animateTransition: Bool
    
    @State private var showPhoto: Bool = false
    
    public init(
        avatarUrl: String? = nil,
        avatarImageData: Data? = nil,
        catState: MyaowCatState = .friendly,
        size: CGFloat = 44,
        showMiniCat: Bool = true,
        animateTransition: Bool = true
    ) {
        self.avatarUrl = avatarUrl
        self.avatarImageData = avatarImageData
        self.catState = catState
        self.size = size
        self.showMiniCat = showMiniCat
        self.animateTransition = animateTransition
    }
    
    private var hasPhoto: Bool {
        return !(avatarUrl ?? "").isEmpty || avatarImageData != nil
    }
    
    private var miniSize: CGFloat {
        return size * 0.3
    }
    
    public var body: some View {
        ZStack {
            // Cat avatar (visible when showPhoto is false OR when there's no photo)
            if !showPhoto || !hasPhoto {
                MyaowCatView(state: catState, style: .darkOnOrange, size: size, isInteractive: false)
                    .transition(.opacity)
            }
            
            // Photo (visible after animation)
            if hasPhoto && showPhoto {
                // Circular photo with border
                photoView
                    .transition(.opacity)
            }
            
            // Mini cat in bottom-right corner (always visible when photo is showing)
            if hasPhoto && showPhoto && showMiniCat {
                miniCatIndicator
            }
        }
        .task(id: hasPhoto) {
            guard hasPhoto else { showPhoto = false; return }
            guard !showPhoto else { return }
            guard animateTransition && !reduceMotion else { showPhoto = true; return }
            do {
                try await Task.sleep(for: .milliseconds(size >= 80 ? 600 : 180))
                try Task.checkCancellation()
                withAnimation(.easeInOut(duration: 0.28)) { showPhoto = true }
            } catch { /* Leaving the screen cancels the reveal. */ }
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced && hasPhoto { showPhoto = true }
        }
    }
    
    @ViewBuilder
    private var photoView: some View {
        Group {
            if let imageData = avatarImageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if let urlString = avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        MyaowCatView(state: catState, style: .darkOnOrange, size: size, isInteractive: false)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        MyaowCatView(state: catState, style: .darkOnOrange, size: size, isInteractive: false)
                    @unknown default:
                        MyaowCatView(state: catState, style: .darkOnOrange, size: size, isInteractive: false)
                    }
                }
            } else {
                MyaowCatView(state: catState, style: .darkOnOrange, size: size, isInteractive: false)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 1.5)
        )
    }
    
    private var miniCatIndicator: some View {
        MyaowCatView(state: catState, style: .darkOnOrange, size: miniSize, isInteractive: false)
            .background(
                Circle()
                    .fill(Color(hex: "#0A0A0C"))
                    .frame(width: miniSize + 4, height: miniSize + 4)
            )
            .offset(x: size / 2 - miniSize / 2, y: size / 2 - miniSize / 2)
    }
}
