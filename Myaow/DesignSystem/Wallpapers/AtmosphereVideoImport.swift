import Foundation
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers
import ImageIO

enum AtmosphereVideoError: LocalizedError {
    case tooLarge, unreadable, exportFailed
    var errorDescription: String? {
        switch self {
        case .tooLarge: "Elige un video de hasta 200 MB. Usaremos sus primeros 12 segundos."
        case .unreadable: "No pudimos abrir este video. Prueba otro de al menos un segundo."
        case .exportFailed: "No pudimos preparar el fondo. Tu fondo anterior sigue guardado."
        }
    }
}

struct ImportedAtmosphereVideo: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let size = try received.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 200 * 1024 * 1024 else { throw AtmosphereVideoError.tooLarge }
            let destination = FileManager.default.temporaryDirectory.appendingPathComponent("myaow-atmosphere-\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: destination)
            return Self(url: destination)
        }
    }
}

struct PreparedAtmosphereVideo: Sendable {
    let id: String
    let video: URL
    let poster: URL
    nonisolated func discard() {
        try? FileManager.default.removeItem(at: video)
        try? FileManager.default.removeItem(at: poster)
    }
}

enum AtmosphereVideoImport {
    /// Only a short, silent video track is retained. No source metadata or audio.
    @concurrent nonisolated static func prepare(source: URL, directory: URL) async throws -> PreparedAtmosphereVideo {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds >= 1,
              let track = try await asset.loadTracks(withMediaType: .video).first else { throw AtmosphereVideoError.unreadable }
        let composition = AVMutableComposition()
        guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw AtmosphereVideoError.exportFailed }
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: min(12, duration.seconds), preferredTimescale: 600))
        try video.insertTimeRange(range, of: track, at: .zero)
        video.preferredTransform = try await track.load(.preferredTransform)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset1280x720) else { throw AtmosphereVideoError.exportFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var localDirectory = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try localDirectory.setResourceValues(values)
        let id = UUID().uuidString
        let prepared = PreparedAtmosphereVideo(id: id, video: directory.appendingPathComponent(id + ".mp4"), poster: directory.appendingPathComponent(id + ".jpg"))
        do {
            // An explicit composition bounds high-frame-rate and high-resolution imports.
            let sourceSize = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let bounds = CGRect(origin: .zero, size: sourceSize).applying(transform)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { throw AtmosphereVideoError.unreadable }
            let scale = min(1, 1280 / max(1, max(bounds.width, bounds.height)))
            let outputSize = CGSize(width: max(2, floor(bounds.width * scale / 2) * 2),
                                    height: max(2, floor(bounds.height * scale / 2) * 2))
            let fitted = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
                .concatenating(CGAffineTransform(scaleX: outputSize.width / bounds.width, y: outputSize.height / bounds.height))
            var layer = AVVideoCompositionLayerInstruction.Configuration(assetTrack: video)
            layer.setTransform(fitted, at: .zero)
            let instruction = AVVideoCompositionInstruction(configuration: .init(layerInstructions: [AVVideoCompositionLayerInstruction(configuration: layer)], timeRange: range))
            exporter.videoComposition = AVVideoComposition(configuration: .init(frameDuration: CMTime(value: 1, timescale: 24), instructions: [instruction], renderSize: outputSize))
            exporter.metadata = []
            exporter.shouldOptimizeForNetworkUse = false
            try await exporter.export(to: prepared.video, as: .mp4)
            try Task.checkCancellation()
            let output = AVURLAsset(url: prepared.video)
            let outputDuration = try await output.load(.duration).seconds
            let audio = try await output.loadTracks(withMediaType: .audio)
            let size = try prepared.video.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard audio.isEmpty, outputDuration <= 12.1, size > 0, size < 25 * 1024 * 1024 else { throw AtmosphereVideoError.exportFailed }
            let generator = AVAssetImageGenerator(asset: output)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 1280)
            let image = try await generator.image(at: .zero).image
            guard let destination = CGImageDestinationCreateWithURL(prepared.poster as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw AtmosphereVideoError.exportFailed }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw AtmosphereVideoError.exportFailed }
            try Task.checkCancellation()
            return prepared
        } catch { prepared.discard(); throw error }
    }
}
