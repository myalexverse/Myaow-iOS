import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit

@main struct ExportAppIcons {
    static func write(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let assets = root.appendingPathComponent("Myaow/Assets.xcassets")
        let review = root.appendingPathComponent("Review/2026-09-23/Icons")
        let backup = review.appendingPathComponent("Previous")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        let titles = ["Negro", "Neón", "Terra", "Glaciar", "Arcade", "Aurora", "Matcha", "Cobre", "Oro"]
        var images: [CGImage] = []
        for variant in MyaowIconRenderer.variants {
            guard let image = MyaowIconRenderer.image(variant: variant) else { throw CocoaError(.fileWriteUnknown) }
            precondition(image.width == 1024 && image.height == 1024 && image.alphaInfo == .noneSkipLast)
            let name = "AppIcon_\(variant).png"
            let target = assets.appendingPathComponent("AppIcon_\(variant).appiconset/\(name)")
            let old = backup.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: old.path) { try FileManager.default.copyItem(at: target, to: old) }
            try write(image, to: target)
            try write(image, to: root.appendingPathComponent("Myaow/\(name)"))
            try write(image, to: root.appendingPathComponent("Myaow/AppIcon_\(variant)@2x.png"))
            let preview = assets.appendingPathComponent("IconPreview_\(variant).imageset")
            try FileManager.default.createDirectory(at: preview, withIntermediateDirectories: true)
            try write(image, to: preview.appendingPathComponent("icon.png"))
            let manifest: [String: Any] = ["images": [["filename": "icon.png", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]]
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: preview.appendingPathComponent("Contents.json"))
            images.append(image)
        }
        let classic = assets.appendingPathComponent("IconPreview_classic.imageset")
        try FileManager.default.createDirectory(at: classic, withIntermediateDirectories: true)
        let original = try Data(contentsOf: assets.appendingPathComponent("AppIcon.appiconset/AppIcon-Default.png"))
        try original.write(to: classic.appendingPathComponent("icon.png"))
        let classicManifest: [String: Any] = ["images": [["filename": "icon.png", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]]
        try JSONSerialization.data(withJSONObject: classicManifest, options: [.prettyPrinted, .sortedKeys]).write(to: classic.appendingPathComponent("Contents.json"))
        // A review sheet shows the actual exports at presentation and Home Screen sizes.
        let width = 1400, height = 1640
        let board = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        board.setFillColor(MyaowIconRenderer.color("0D0F12")); board.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: board, flipped: false)
        func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat, muted: Bool = false) {
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: muted ? NSColor(white: 0.55, alpha: 1) : NSColor(white: 0.93, alpha: 1)]
            (value as NSString).draw(at: CGPoint(x: x, y: CGFloat(height) - top - size * 1.3), withAttributes: attrs)
        }
        text("MYAOW  /  ICONOS", x: 68, top: 48, size: 22, muted: true)
        text("Una identidad. Nueve acabados.", x: 68, top: 96, size: 42)
        for (i, image) in images.enumerated() {
            let x = CGFloat(68 + (i % 3) * 434), top = CGFloat(205 + (i / 3) * 468)
            let rect = CGRect(x: x, y: CGFloat(height) - top - 300, width: 300, height: 300)
            board.saveGState(); board.addPath(CGPath(roundedRect: rect, cornerWidth: 65, cornerHeight: 65, transform: nil)); board.clip()
            board.interpolationQuality = .high; board.draw(image, in: rect); board.restoreGState()
            let small = CGRect(x: x + 320, y: rect.minY + 4, width: 60, height: 60)
            board.saveGState(); board.addPath(CGPath(roundedRect: small, cornerWidth: 13, cornerHeight: 13, transform: nil)); board.clip(); board.draw(image, in: small); board.restoreGState()
            text(titles[i], x: x, top: top + 324, size: 24)
            text("1024 px  /  Vista a 60 px", x: x, top: top + 364, size: 15, muted: true)
        }
        NSGraphicsContext.restoreGraphicsState()
        try write(board.makeImage()!, to: review.appendingPathComponent("coleccion-iconos.png"))
        print("Exported and validated 9 opaque 1024px alternate icons, 10 matching previews, preserved primary icon and archived originals.")
    }
}
