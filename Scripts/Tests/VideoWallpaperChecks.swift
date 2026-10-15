import Foundation
import AVFoundation
import CoreGraphics

@main struct VideoWallpaperChecks {
    static func pixels(_ image: CGImage) -> [UInt8] {
        let w = 90, h = 160
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress!, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        let sum = zip(a, b).enumerated().filter { $0.offset % 4 != 3 }.reduce(0.0) { $0 + abs(Double($1.element.0) - Double($1.element.1)) }
        return sum / Double(a.count / 4 * 3)
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundle = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
        var checks = 0
        var totalBytes = 0
        func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
            precondition(condition(), reason); checks += 1
        }
        for name in ["WallpaperOrbit", "WallpaperSilk", "WallpaperEmber", "WallpaperLava", "WallpaperLavaViolet", "WallpaperLavaTeal", "WallpaperOrbitBlue", "WallpaperWater", "WallpaperWaves", "WallpaperNebula", "WallpaperAurora", "WallpaperPortal", "WallpaperGrid", "WallpaperEclipse", "WallpaperTitan", "WallpaperNeonRain", "WallpaperBinaryDunes", "WallpaperOrbitalGarden", "WallpaperVertigo", "WallpaperSilverScreen", "WallpaperDeco", "WallpaperCosmicOpera", "WallpaperAlienCrystal"] {
            let url = root.appendingPathComponent("Myaow/Resources/Wallpapers/\(name).mp4")
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration)
            check(abs(duration.seconds - 10) < 0.05, "Must be a ten second movie")
            let videos = try await asset.loadTracks(withMediaType: .video)
            let audio = try await asset.loadTracks(withMediaType: .audio)
            check(videos.count == 1 && audio.isEmpty, "One video track and no audio track")
            let size = try await videos[0].load(.naturalSize)
            let frameRate = try await videos[0].load(.nominalFrameRate)
            check(size == CGSize(width: 540, height: 960) && frameRate == 24, "Portrait dimensions and 24 fps")
            let generator = AVAssetImageGenerator(asset: asset)
            generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
            let first = try await generator.image(at: .zero).image
            let quarter = try await generator.image(at: CMTime(value: 60, timescale: 24)).image
            let middle = try await generator.image(at: CMTime(value: 120, timescale: 24)).image
            let last = try await generator.image(at: CMTime(value: 239, timescale: 24)).image
            // A breathing/pendulum loop can cross the same pose at 0 and 5 s.
            // Sample the quarter cycle as well, without relaxing the seam threshold.
            let motion = max(difference(pixels(first), pixels(quarter)), difference(pixels(first), pixels(middle)))
            let seam = difference(pixels(first), pixels(last))
            FileHandle.standardError.write(Data("\(name): motion=\(motion), wrap=\(seam)\n".utf8))
            check(motion > 0.08, "Movie must actually move")
            check(seam < 2.5 && seam < motion, "Last to first wrap should be visually continuous")
            let file = try Data(contentsOf: url)
            totalBytes += file.count
            check(file.count < 2_000_000, "Keep each bundled movie under 2 MB")
            if let bundle {
                let installed = try Data(contentsOf: bundle.appendingPathComponent("\(name).mp4"))
                check(installed == file, "Built app must contain the exact movie")
            }
            print("\(name): PASS, motion=\(String(format: "%.3f", motion)), wrap=\(String(format: "%.3f", seam)), bytes=\(file.count)")
        }
        print("PASS: \(checks) media checks. Total video payload: \(totalBytes) bytes.")
    }
}
