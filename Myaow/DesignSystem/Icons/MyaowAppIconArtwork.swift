import SwiftUI

/// Previews display the exact exported artwork that iOS installs.
public struct MyaowAppIconThumbnailView: View {
    public let variant: MyaowAppIconVariant
    public var size: CGFloat = 64
    public var cornerRadius: CGFloat = 16
    public init(variant: MyaowAppIconVariant, size: CGFloat = 64, cornerRadius: CGFloat = 16) {
        self.variant = variant; self.size = size; self.cornerRadius = cornerRadius
    }
    public var body: some View {
        Image("IconPreview_\(variant.rawValue)")
            .resizable().interpolation(variant == .pixelRetro ? .none : .high).scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(.white.opacity(0.09), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
