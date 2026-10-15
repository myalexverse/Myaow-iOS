import Foundation
import AVFoundation
import CryptoKit

@main struct AtmosphereImportChecks {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("myaow-import-check-\(UUID())")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let source = root.appendingPathComponent("Myaow/Resources/Wallpapers/WallpaperLava.mp4")
        let before = SHA256.hash(data: try Data(contentsOf: source))
        let first = try await AtmosphereVideoImport.prepare(source: source, directory: temp.appendingPathComponent("out"))
        try await verify(first, duration: 10, landscape: false)
        let after = SHA256.hash(data: try Data(contentsOf: source))
        precondition(before == after, "Original changed")
        first.discard()
        precondition(!FileManager.default.fileExists(atPath: first.video.path))
        precondition(!FileManager.default.fileExists(atPath: first.poster.path))

        // A longer rotated video with an audio track tests trim, orientation and silence.
        let asset = AVURLAsset(url: source)
        let videoTrack = try await asset.loadTracks(withMediaType: .video)[0]
        let composition = AVMutableComposition()
        let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        for n in 0..<3 { try video.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 10, preferredTimescale: 600)), of: videoTrack, at: CMTime(seconds: Double(n) * 10, preferredTimescale: 600)) }
        video.preferredTransform = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 960, ty: 0)
        let sound = AVURLAsset(url: root.appendingPathComponent("Myaow/Resources/Sounds/myaow-classic.wav"))
        let audioTrack = try await sound.loadTracks(withMediaType: .audio)[0]
        let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: try await sound.load(.duration)), of: audioTrack, at: .zero)
        let fixture = temp.appendingPathComponent("rotated-with-audio.mov")
        let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)!
        try await export.export(to: fixture, as: .mov)
        let rotated = try await AtmosphereVideoImport.prepare(source: fixture, directory: temp.appendingPathComponent("out"))
        try await verify(rotated, duration: 12, landscape: true)
        rotated.discard()

        // A 1536-pixel, 60 fps input must become at most 1280 pixels and 24 fps.
        let highRate = temp.appendingPathComponent("large-fast.mp4")
        let writer = try AVAssetWriter(outputURL: highRate, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1536, AVVideoHeightKey: 864])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 1536, kCVPixelBufferHeightKey as String: 864])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &buffer)
        let frame = buffer!
        CVPixelBufferLockBaseAddress(frame, [])
        memset(CVPixelBufferGetBaseAddress(frame)!, 64, CVPixelBufferGetDataSize(frame))
        CVPixelBufferUnlockBaseAddress(frame, [])
        for n in 0..<120 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            precondition(adapter.append(frame, withPresentationTime: CMTime(value: Int64(n), timescale: 60)))
        }
        input.markAsFinished(); writer.endSession(atSourceTime: CMTime(value: 2, timescale: 1)); await writer.finishWriting()
        let bounded = try await AtmosphereVideoImport.prepare(source: highRate, directory: temp.appendingPathComponent("out"))
        try await verify(bounded, duration: 2, landscape: true)
        bounded.discard()

        let invalid = temp.appendingPathComponent("invalid.mov")
        try Data("not a video".utf8).write(to: invalid)
        do { _ = try await AtmosphereVideoImport.prepare(source: invalid, directory: temp.appendingPathComponent("bad")); fatalError("Invalid input accepted") } catch { }
        let cancelled = Task {
            try await Task.sleep(for: .seconds(1))
            return try await AtmosphereVideoImport.prepare(source: source, directory: temp.appendingPathComponent("cancelled"))
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; fatalError("Cancellation ignored") } catch is CancellationError { }
        precondition(!FileManager.default.fileExists(atPath: temp.appendingPathComponent("cancelled").path))
        print("PASS: original preserved, portrait, rotated landscape, trim to 12s, silent export, 24fps, poster, cleanup, invalid input and cancellation.")
    }
    static func verify(_ prepared: PreparedAtmosphereVideo, duration: Double, landscape: Bool) async throws {
        let asset = AVURLAsset(url: prepared.video)
        let actual = try await asset.load(.duration).seconds
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let size = try await track.load(.naturalSize)
        let rate = try await track.load(.nominalFrameRate)
        precondition(abs(actual - duration) < 0.1 && audio.isEmpty)
        precondition(max(size.width, size.height) <= 1280 && (size.width > size.height) == landscape)
        precondition(abs(rate - 24) < 0.1)
        let poster = try Data(contentsOf: prepared.poster)
        precondition(poster.count > 100)
        print("PASS: \(size.width)x\(size.height), \(rate) fps, \(actual)s, no audio")
    }
}
