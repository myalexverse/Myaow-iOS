import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main struct ProfilePhotoChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) {
            precondition(condition(), description); checks += 1
        }
        // These are the same coordinates the preview and 512 px export consume.
        for source in [CGSize(width: 4000, height: 2000), CGSize(width: 1000, height: 3000), CGSize(width: 512, height: 512)] {
            for zoom: CGFloat in [1, 1.7, 4] {
                for offset in [CGSize.zero, CGSize(width: -9, height: 9), CGSize(width: 9, height: -9)] {
                    let r = ProfilePhotoCrop.drawingRect(source: source, zoom: zoom, offset: offset, side: 512)
                    check(abs(r.width / r.height - source.width / source.height) < 0.0001, "Photo aspect ratio must be preserved")
                    check(r.minX <= 0.001 && r.minY <= 0.001 && r.maxX >= 511.999 && r.maxY >= 511.999, "Crop must always cover the output, including at extreme drags")
                    let preview = ProfilePhotoCrop.drawingRect(source: source, zoom: zoom, offset: offset, side: 300)
                    check(abs(preview.minX / 300 - r.minX / 512) < 0.0001 && abs(preview.width / 300 - r.width / 512) < 0.0001, "Preview and export must show identical framing")
                }
            }
        }
        let context = CGContext(data: nil, width: 3000, height: 1500, bitsPerComponent: 8, bytesPerRow: 12000,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1500))
        let data = NSMutableData()
        let writer = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, context.makeImage()!, [kCGImagePropertyOrientation: 6,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 19.4, kCGImagePropertyGPSLatitudeRef: "N"]] as CFDictionary)
        check(CGImageDestinationFinalize(writer), "Fixture should encode")
        let result = try ProfilePhotoCrop.prepare(data as Data)
        let source = CGImageSourceCreateWithData(result as CFData, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        check(image.height == 2048 && image.width == 1024, "EXIF rotation normalized and huge image bounded")
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        check(properties[kCGImagePropertyGPSDictionary] == nil, "Prepared photo must not preserve GPS metadata")
        do { _ = try ProfilePhotoCrop.prepare(Data("invalid image".utf8)); fatalError("Corrupt file was accepted") }
        catch { checks += 1 }
        print("PASS: \(checks) profile checks: aspect ratio, coverage, matching preview, EXIF rotation, image limits, GPS removal and corrupt-file handling.")
    }
}
