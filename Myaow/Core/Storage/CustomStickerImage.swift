import Foundation
import Vision
import CoreImage
import ImageIO

/// Image messages retain backward compatibility; PNG alpha is preserved end to end.
enum CustomStickerImage {
    static let caption = "Sticker · Myaow"
    nonisolated static func prepare(_ data: Data, removeBackground: Bool) throws -> Data {
        guard data.count <= 20*1024*1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true, kCGImageSourceThumbnailMaxPixelSize:768] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        var result = cg
        if removeBackground {
            let handler = VNImageRequestHandler(cgImage: cg)
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { throw CocoaError(.featureUnsupported) }
            let pixels = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: true)
            let image = CIImage(cvPixelBuffer: pixels)
            guard let cut = CIContext().createCGImage(image, from: image.extent) else { throw CocoaError(.fileReadCorruptFile) }
            result = cut
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, result, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return output as Data
    }
}

