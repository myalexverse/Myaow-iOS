import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Coordinates are relative to the square viewport so rotation and layout changes
/// preserve the same crop. Aspect fill never stretches a portrait or landscape.
nonisolated enum ProfilePhotoCrop {
    static func imageSize(_ source: CGSize, zoom: CGFloat) -> CGSize {
        let scale = max(1 / source.width, 1 / source.height) * max(1, zoom)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }

    static func clampedOffset(_ offset: CGSize, source: CGSize, zoom: CGFloat) -> CGSize {
        let size = imageSize(source, zoom: zoom)
        let x = max(0, (size.width - 1) / 2)
        let y = max(0, (size.height - 1) / 2)
        return CGSize(width: min(x, max(-x, offset.width)), height: min(y, max(-y, offset.height)))
    }

    static func drawingRect(source: CGSize, zoom: CGFloat, offset: CGSize, side: CGFloat) -> CGRect {
        let size = imageSize(source, zoom: zoom)
        let bounded = clampedOffset(offset, source: source, zoom: zoom)
        return CGRect(x: ((1 - size.width) / 2 + bounded.width) * side,
                      y: ((1 - size.height) / 2 + bounded.height) * side,
                      width: size.width * side, height: size.height * side)
    }

    /// Decode only a bounded thumbnail, normalize EXIF orientation and discard
    /// location/camera metadata before the image is ever offered for upload.
    static func prepare(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
    }
}
