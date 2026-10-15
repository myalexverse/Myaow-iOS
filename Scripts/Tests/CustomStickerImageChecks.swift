import Foundation
import CoreGraphics
import ImageIO

@main struct CustomStickerImageChecks {
    static func main() throws {
        let context = CGContext(data: nil, width: 1200, height: 600, bitsPerComponent: 8, bytesPerRow: 4800,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0.3, blue: 0, alpha: 1))
        context.fill(CGRect(x: 300, y: 150, width: 600, height: 300))
        let input = NSMutableData()
        let destination = CGImageDestinationCreateWithData(input, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: "private source metadata"]] as CFDictionary)
        precondition(CGImageDestinationFinalize(destination))
        let output = try CustomStickerImage.prepare(input as Data, removeBackground: false)
        let source = CGImageSourceCreateWithData(output as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        precondition(image.width == 768 && image.height == 384, "Import must preserve proportions and bound resolution")
        precondition(image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast, "PNG alpha must survive import")
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        let png = properties[kCGImagePropertyPNGDictionary] as? NSDictionary
        precondition(png?[kCGImagePropertyPNGDescription] == nil, "Source metadata must not leak into the sticker")
        for invalid in [Data("not an image".utf8), Data(repeating: 0, count: 20*1024*1024 + 1)] {
            do {
                _ = try CustomStickerImage.prepare(invalid, removeBackground: false)
                preconditionFailure("Corrupt or oversized input must be rejected")
            } catch { }
        }
        print("Custom stickers: PNG transparency, aspect ratio, bounded resolution, metadata removal and invalid input passed.")
    }
}
