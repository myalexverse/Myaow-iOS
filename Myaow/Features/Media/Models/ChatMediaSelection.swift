import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO

public struct ChatMediaSelection: Identifiable, Sendable {
    public let id = UUID()
    public let data: Data
    public let isVideo: Bool
}

enum ChatMediaSelectionError: LocalizedError {
    case tooLarge, unreadable
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "Selecciona hasta 10 archivos y 50 MB en total. Cada video debe pesar hasta 10 MB; cada foto original, hasta 40 MB."
        case .unreadable: return "No pudimos preparar este archivo. Selecciona otra foto o video."
        }
    }
}

/// Import from a file so a large video is rejected before being loaded into memory.
struct ImportedChatMedia: Transferable, Sendable {
    let data: Data
    let isVideo: Bool
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try read(received.file, video: false)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try read(received.file, video: true)
        }
    }
    private static func read(_ url: URL, video: Bool) throws -> Self {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let maximum = (video ? 10 : 40) * 1024 * 1024
        guard size > 0, size <= maximum else { throw ChatMediaSelectionError.tooLarge }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty, data.count <= maximum else { throw ChatMediaSelectionError.tooLarge }
        return Self(data: data, isVideo: video)
    }
}

enum ChatPhotoEncoding {
    /// Decode only the target resolution, apply orientation and omit the source metadata.
    nonisolated static func jpeg(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1280
              ] as CFDictionary) else { throw ChatMediaSelectionError.unreadable }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw ChatMediaSelectionError.unreadable }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ChatMediaSelectionError.unreadable }
        return output as Data
    }
}
