import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Store packaging requires RGB icons; preserve artwork and let iOS mask corners.
let fix = CommandLine.arguments.contains("--fix")
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Myaow/Assets.xcassets")
let directories = try FileManager.default.contentsOfDirectory(at: assets, includingPropertiesForKeys: nil)
var invalid = 0
for directory in directories.filter({ $0.pathExtension == "appiconset" }) {
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))) as! [String: Any]
    let names = Set((json["images"] as! [[String: Any]]).compactMap { $0["filename"] as? String })
    for name in names {
        let url = directory.appendingPathComponent(name)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Unreadable icon: \(name)") }
        precondition(image.width == 1024 && image.height == 1024, "Invalid Store icon size: \(name)")
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard properties?[kCGImagePropertyHasAlpha] as? Bool == true else { continue }
        if !fix { print("FAIL: \(name) contains alpha"); invalid += 1; continue }
        let backup = root.appendingPathComponent("Builds/TestFlight/OriginalIcons/\(name)")
        try FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: url, to: backup) }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let sample = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: space,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        sample.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let pixel = sample.data!.assumingMemoryBound(to: UInt8.self).advanced(by: 512 * 4)
        precondition(pixel[3] == 255, "Icon edge must be opaque for background sampling")
        let rgb = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        rgb.setFillColor(CGColor(colorSpace: space, components: [CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255, 1])!)
        rgb.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        rgb.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, rgb.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        try (output as Data).write(to: url, options: .atomic)
        print("Prepared opaque RGB Store icon: \(name)")
    }
}
if invalid > 0 { exit(1) }
print("Store icon format checks passed")
