import Foundation
import CoreGraphics
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Offline motion artwork. Every movement uses integer harmonics of a single
/// phase, giving each 10 second movie a continuous wrap without a duplicated frame.
@main struct ExportVideoWallpapers {
    static let width = 540, height = 960, fps = 24, frames = 240
    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: alpha)
    }
    static func glow(_ context: CGContext, x: CGFloat, y: CGFloat, radius: CGFloat, tint: UInt32, alpha: CGFloat) {
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(tint, alpha), color(tint, 0)] as CFArray, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                                   endCenter: CGPoint(x: x, y: y), endRadius: radius, options: [])
    }
    static func draw(_ context: CGContext, style: String, phase: Double) {
        let w = CGFloat(width), h = CGFloat(height), t = CGFloat(phase)
        context.setFillColor(color(0x090A0D)); context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        switch style {
        case "Eclipse", "Titan", "NeonRain", "BinaryDunes", "OrbitalGarden", "Vertigo", "SilverScreen", "Deco", "CosmicOpera", "AlienCrystal":
            drawCinema(context, style: style, phase: phase)
        case "Lava", "LavaViolet", "LavaTeal":
            drawLava(context, phase: phase, palette: style)
        case "Nebula", "Aurora", "Portal", "Grid":
            drawScienceFiction(context, style: style, phase: phase)
        case "Water":
            drawWater(context, phase: phase)
        case "Waves":
            drawWaves(context, phase: phase)
        case "Orbit", "OrbitBlue":
            let blue = style == "OrbitBlue"
            glow(context, x: w * 0.84, y: h * 0.20, radius: w * 0.82, tint: (blue ? 0x093C88 : 0xB23B08), alpha: 0.23)
            glow(context, x: w * 0.08, y: h * 0.90, radius: w * 0.7, tint: (blue ? 0x1876C5 : 0xF67720), alpha: 0.14)
            for orbit in 0..<2 {
                context.saveGState()
                context.translateBy(x: orbit == 0 ? w * 0.84 : w * 0.08, y: orbit == 0 ? h * 0.22 : h * 0.89)
                context.rotate(by: (orbit == 0 ? -0.48 : 0.45) + sin(t) * 0.045)
                let rx = w * (orbit == 0 ? 0.52 : 0.43)
                let ry = rx * (0.59 + 0.035 * cos(t))
                for layer in (0..<5).reversed() {
                    let path = CGPath(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: nil)
                    context.addPath(path)
                    context.setStrokeColor(color((blue ? 0x3BACDC : 0xFF6A12), layer == 0 ? 0.65 : 0.026))
                    context.setLineWidth(layer == 0 ? 2 : CGFloat(layer * 12)); context.strokePath()
                }
                // Moving specular highlight along a lit copper ring.
                for segment in 0..<180 {
                    let a = CGFloat(segment) / 180 * .pi * 2
                    let illumination = pow(max(0, cos(a - t - CGFloat(orbit) * .pi)), 12)
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: cos(a) * rx, y: sin(a) * ry))
                    let b = a + .pi * 2 / 180
                    path.addLine(to: CGPoint(x: cos(b) * rx, y: sin(b) * ry))
                    context.addPath(path); context.setLineWidth(2.3)
                    context.setStrokeColor(color((blue ? 0x9DDDFA : 0xFFD4A4), illumination * 0.92)); context.strokePath()
                }
                context.restoreGState()
            }
        case "Silk":
            glow(context, x: w * 0.1, y: h * 0.6, radius: h * 0.55, tint: 0x843510, alpha: 0.28)
            for ribbon in 0..<2 {
                for line in 0..<80 {
                    let v = CGFloat(line) / 79
                    let path = CGMutablePath()
                    for step in 0...100 {
                        let y = CGFloat(step) / 100 * (h + 140) - 70
                        let u = y / h
                        let bend = sin(u * .pi * 2 + t) * 0.13 + cos(u * .pi * 3 - t) * 0.045
                        let x = w * ((ribbon == 0 ? 0.02 : 0.86) + bend + v * 0.32)
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    let specular = pow(max(0, sin(v * .pi)), 7)
                    context.addPath(path); context.setLineWidth(2.2)
                    context.setStrokeColor(color(line > 34 && line < 45 ? 0xFFA764 : 0xD95114,
                                                (0.08 + specular * 0.54) * (ribbon == 0 ? 1 : 0.68)))
                    context.strokePath()
                }
            }
        default:
            glow(context, x: w * (0.5 + 0.1 * sin(t)), y: h * 1.05, radius: h * 0.75, tint: 0xE2550D, alpha: 0.45)
            glow(context, x: w * 0.92, y: h * 0.18, radius: w * 0.60, tint: 0x7D350F, alpha: 0.15)
            for i in 0..<44 {
                let seed = CGFloat(i)
                let baseX = CGFloat((i * 173 + 71) % 541) / 540
                let baseY = CGFloat((i * 137 + 39) % 961) / 960
                let x = w * baseX + sin(t + seed * 1.73) * 18
                let y = h * baseY + cos(t + seed * 0.97) * 26
                let near = i % 6 == 0
                let radius: CGFloat = near ? 12 : 2.1
                let alpha: CGFloat = (0.28 + 0.12 * sin(t + seed)) * (baseY > 0.5 ? 1 : 0.5)
                glow(context, x: x, y: y, radius: radius * 5, tint: 0xED6D21, alpha: alpha * 0.28)
                if near { glow(context, x: x, y: y, radius: radius, tint: 0xFB9445, alpha: alpha * 0.65) }
                else {
                    context.setFillColor(color(0xFFC28A, alpha)); context.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
                }
            }
        }
        // Keep the conversation center dark and edges cinematic, not flashing.
        let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x000000, 0.33), color(0x000000, 0.03), color(0x000000, 0.22)] as CFArray, locations: [0, 0.5, 1])!
        context.drawLinearGradient(shade, start: .zero, end: CGPoint(x: 0, y: h), options: [])
    }
    /// Original science-fiction scenes. All geometry is baked into silent video;
    /// the phone only decodes the active wallpaper, never this rendering work.
    static func drawScienceFiction(_ context: CGContext, style: String, phase: Double) {
        let w = CGFloat(width), h = CGFloat(height), t = CGFloat(phase)
        if style == "Nebula" {
            let rw = 270, rh = 480
            var pixels = [UInt8](repeating: 255, count: rw * rh * 4)
            for y in 0..<rh {
                for x in 0..<rw {
                    let u = Double(x) / Double(rw), v = Double(y) / Double(rh)
                    let warp = sin(u * 7 + v * 5 + sin(phase) * 0.35)
                    let curl = sin(u * 12 - v * 9 + warp * 2 + cos(phase) * 0.4)
                    let dust = pow(max(0, 0.5 + 0.5 * curl), 2)
                    let cloud = exp(-pow((u - 0.14 - 0.58 * v - 0.12 * sin(v * 7 + sin(phase) * 0.5)) * 3.3, 2))
                    let haze = cloud * (0.24 + 0.76 * dust)
                    let blue = 0.5 + 0.5 * sin(v * 5 + u * 3 + cos(phase) * 0.25)
                    let i = (y * rw + x) * 4
                    pixels[i] = UInt8(8 + 83 * haze)
                    pixels[i + 1] = UInt8(9 + 23 * haze + 15 * blue * cloud)
                    pixels[i + 2] = UInt8(20 + 95 * haze + 24 * blue * cloud)
                }
            }
            pixels.withUnsafeMutableBytes { bytes in
                let c = CGContext(data: bytes.baseAddress, width: rw, height: rh, bitsPerComponent: 8, bytesPerRow: rw * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.interpolationQuality = .high
                context.draw(c.makeImage()!, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        } else if style == "Aurora" {
            glow(context, x: w * 0.8, y: h * 0.2, radius: h * 0.7, tint: 0x12384D, alpha: 0.7)
            for curtain in 0..<2 {
                for line in 0..<100 {
                    let v = CGFloat(line) / 99
                    let path = CGMutablePath()
                    for step in 0...100 {
                        let x = CGFloat(step) / 100 * (w + 80) - 40
                        let u = x / w
                        let wave = sin(u * 4 + sin(t) * 0.4 + CGFloat(curtain)) * 0.11
                        let fold = sin(u * 10 + cos(t) * 0.6) * 0.025
                        let y = h * (0.2 + CGFloat(curtain) * 0.47 + wave + fold + v * 0.27)
                        if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    let fade = pow(1 - v, 2) * sin(v * .pi * 0.5 + 0.25)
                    context.addPath(path); context.setLineWidth(3)
                    context.setStrokeColor(color(curtain == 0 ? 0x49E6C4 : 0x846BEC, fade * 0.5)); context.strokePath()
                }
            }
        } else if style == "Portal" {
            let cx = w * 0.76, cy = h * 0.31
            glow(context, x: cx, y: cy, radius: w * 0.85, tint: 0x9A380E, alpha: 0.35)
            for ring in (0..<9).reversed() {
                let n = CGFloat(ring)
                let rx = w * (0.16 + n * 0.045), ry = rx * 1.38
                context.saveGState()
                context.translateBy(x: cx + sin(t + n * 0.18) * 4, y: cy)
                context.rotate(by: -0.32 + sin(t) * 0.035)
                let rect = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)
                context.setStrokeColor(color(0xDF692A, 0.10)); context.setLineWidth(1); context.strokeEllipse(in: rect)
                for segment in 0..<100 {
                    let a = CGFloat(segment) / 100 * .pi * 2
                    let light = pow(max(0, cos(a - t - n * 0.35)), 8)
                    let b = a + .pi * 2 / 100
                    context.move(to: CGPoint(x: cos(a) * rx, y: sin(a) * ry))
                    context.addLine(to: CGPoint(x: cos(b) * rx, y: sin(b) * ry))
                    context.setLineWidth(1.8); context.setStrokeColor(color(0xFFA064, light * 0.62)); context.strokePath()
                }
                context.restoreGState()
            }
        } else {
            // Perspective navigation lattice, with a slow energy sweep instead of flashing.
            glow(context, x: w * 0.5, y: h * 0.57, radius: w * 0.9, tint: 0x134E68, alpha: 0.38)
            let horizon = h * 0.40
            for index in -8...8 {
                let n = CGFloat(index)
                context.move(to: CGPoint(x: w * 0.5 + n * 9, y: horizon))
                context.addLine(to: CGPoint(x: w * 0.5 + n * 115, y: h * 1.1))
                context.setStrokeColor(color(0x33B7C4, 0.21)); context.setLineWidth(1); context.strokePath()
            }
            for row in 0..<18 {
                let v = CGFloat(row) / 17
                let y = horizon + pow(v, 2) * h * 0.7
                let pulse = pow(max(0, cos(v * .pi * 2 - t)), 8)
                context.move(to: CGPoint(x: 0, y: y)); context.addLine(to: CGPoint(x: w, y: y))
                context.setLineWidth(1 + pulse); context.setStrokeColor(color(0x56DBDE, 0.10 + pulse * 0.35)); context.strokePath()
            }
            glow(context, x: w * (0.5 + sin(t) * 0.3), y: h * 0.18, radius: w * 0.42, tint: 0x703EA6, alpha: 0.28)
        }
        if style == "Nebula" || style == "Aurora" {
            for star in 0..<62 {
                let n = CGFloat(star)
                let x = CGFloat((star * 173 + 37) % 540) + sin(t + n) * 2
                let y = CGFloat((star * 293 + 83) % 960) + cos(t + n) * 2
                let radius: CGFloat = star % 9 == 0 ? 2 : 1
                let alpha = 0.2 + 0.12 * sin(t + n * 0.7)
                context.setFillColor(color(0xC3DCF4, alpha))
                context.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
            }
        }
    }
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if CommandLine.arguments.contains("--cinema-sheet") { try cinemaSheet(root: root); return }
        let styles = CommandLine.arguments.contains("--cinema") ? cinemaStyles : CommandLine.arguments.contains("--scifi") ? ["Nebula", "Aurora", "Portal", "Grid"] : CommandLine.arguments.contains("--water") ? ["Water"] : CommandLine.arguments.contains("--expanded") ? ["LavaViolet", "LavaTeal", "OrbitBlue", "Water", "Waves"] : CommandLine.arguments.contains("--lava") ? ["Lava"] : ["Orbit", "Silk", "Ember"]
        for style in styles {
            let name = "Wallpaper\(style)"
            let url = root.appendingPathComponent("Myaow/Resources/Wallpapers/\(name).mp4")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 700_000, AVVideoMaxKeyFrameIntervalKey: 48,
                                                  AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
            ])
            input.expectsMediaDataInRealTime = false
            let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error! }
            writer.startSession(atSourceTime: .zero)
            for frame in 0..<frames {
                while !input.isReadyForMoreMediaData {
                    if writer.status == .failed { throw writer.error! }
                    try await Task.sleep(for: .milliseconds(3))
                }
                try autoreleasepool {
                    var pixelBuffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil, adapter.pixelBufferPool!, &pixelBuffer) == kCVReturnSuccess,
                          let pixelBuffer else { throw CocoaError(.fileWriteUnknown) }
                    CVPixelBufferLockBaseAddress(pixelBuffer, [])
                    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
                    let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height,
                                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
                    context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
                    draw(context, style: style, phase: Double(frame) / Double(frames) * .pi * 2)
                    if frame == 0 {
                        let folder = root.appendingPathComponent("Myaow/Assets.xcassets/\(name).imageset")
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        let destination = CGImageDestinationCreateWithURL(folder.appendingPathComponent("poster.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
                        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
                        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
                        let manifest: [String: Any] = ["images": [["filename": "poster.png", "idiom": "universal"]], "info": ["author": "xcode", "version": 1]]
                        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: folder.appendingPathComponent("Contents.json"))
                    }
                    guard adapter.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))) else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
                }
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value: Int64(frames), timescale: Int32(fps)))
            await writer.finishWriting()
            guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            print("Exported \(name): 540 × 960, 24 fps, 10 s, silent continuous loop")
        }
    }

    /// Original metaball artwork, rendered offline. No per-pixel work on iPhone.
    static func drawLava(_ context: CGContext, phase: Double, palette: String = "Lava") {
        let rw = 270, rh = 480
        let ratio = Double(rh) / Double(rw)
        let t = phase
        let balls: [(Double, Double, Double)] = [
            (0.10 + 0.12 * sin(t), 0.22 * ratio + 0.20 * cos(t), 0.24),
            (0.80 + 0.10 * cos(t), 0.65 * ratio + 0.32 * sin(t), 0.30),
            (0.27 + 0.15 * sin(t + 1), 0.85 * ratio + 0.18 * cos(t), 0.24),
            (0.80 + 0.08 * sin(t + 2), 0.13 * ratio + 0.22 * sin(t), 0.18),
            (0.48 + 0.14 * sin(t + 3), 0.45 * ratio + 0.33 * cos(t), 0.14),
            (-0.18, 0.62 * ratio + 0.15 * sin(t), 0.26),
            (1.1, 0.93 * ratio + 0.12 * cos(t), 0.28)
        ]
        var pixels = [UInt8](repeating: 255, count: rw * rh * 4)
        for y in 0..<rh {
            let py = Double(y) / Double(rw)
            for x in 0..<rw {
                let px = Double(x) / Double(rw)
                var field = 0.0, gx = 0.0, gy = 0.0
                for (bx, by, radius) in balls {
                    let dx = px - bx, dy = (py - by) * 0.90
                    let d = max(0.003, dx * dx + dy * dy)
                    let r2 = radius * radius
                    field += r2 / d
                    gx -= 2 * r2 * dx / (d * d)
                    gy -= 2 * r2 * dy / (d * d)
                }
                let edge = min(1, max(0, (field - 1.55) / 0.14))
                let blend = edge * edge * (3 - 2 * edge)
                let norm = max(0.01, sqrt(gx * gx + gy * gy))
                let highlight = pow(max(0, (-gx * 0.60 - gy * 0.80) / norm), 9)
                let rim = exp(-abs(field - 1.68) * 3.2)
                let depth = min(1, max(0, (field - 1.6) / 5))
                let light = 0.62 + 0.35 * depth
                let halo = min(1, field / 1.6) * 13
                let r = (8 + halo * 1.5) * (1 - blend) + min(255, 205 * light + 67 * highlight * rim) * blend
                let g = (6 + halo * 0.25) * (1 - blend) + min(255, 50 * light + 89 * highlight * rim + 28 * depth) * blend
                let b = (10 + halo * 0.1) * (1 - blend) + (6 + 15 * highlight * rim + 4 * depth) * blend
                let i = (y * rw + x) * 4
                if palette == "LavaViolet" {
                    pixels[i] = UInt8(r * 0.66); pixels[i + 1] = UInt8(g * 0.52 + b * 0.12); pixels[i + 2] = UInt8(r * 0.88)
                } else if palette == "LavaTeal" {
                    pixels[i] = UInt8(g * 0.40); pixels[i + 1] = UInt8(r * 0.68); pixels[i + 2] = UInt8(r * 0.77)
                } else { pixels[i] = UInt8(r); pixels[i + 1] = UInt8(g); pixels[i + 2] = UInt8(b) }
            }
        }
        pixels.withUnsafeMutableBytes { bytes in
            let imageContext = CGContext(data: bytes.baseAddress, width: rw, height: rh, bitsPerComponent: 8, bytesPerRow: rw * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(imageContext.makeImage()!, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    static func drawWater(_ context: CGContext, phase: Double) {
        let rw = 270, rh = 480
        var pixels = [UInt8](repeating: 255, count: rw * rh * 4)
        for y in 0..<rh {
            for x in 0..<rw {
                let u = Double(x) / Double(rw), v = Double(y) / Double(rw)
                let flow = sin(u * 9 + sin(phase) * 0.7) + cos(v * 8 + cos(phase) * 0.6) + sin((u + v) * 5 + sin(phase) * 0.9) * 0.7
                let caustic = pow(max(0, 1 - abs(sin(flow * 2.6))), 5)
                let depth = 0.5 + 0.5 * sin(v * 3 + phase)
                let i = (y * rw + x) * 4
                pixels[i] = UInt8(5 + 16 * caustic)
                pixels[i + 1] = UInt8(20 + 54 * caustic + 12 * depth)
                pixels[i + 2] = UInt8(30 + 70 * caustic + 16 * depth)
            }
        }
        pixels.withUnsafeMutableBytes { bytes in
            let c = CGContext(data: bytes.baseAddress, width: rw, height: rh, bitsPerComponent: 8, bytesPerRow: rw * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.interpolationQuality = .high
            context.draw(c.makeImage()!, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
    static func drawWaves(_ context: CGContext, phase: Double) {
        let w = CGFloat(width), h = CGFloat(height), t = CGFloat(phase)
        glow(context, x: w * 0.9, y: h * 0.85, radius: h * 0.8, tint: 0x144456, alpha: 0.7)
        for line in 0..<48 {
            let n = CGFloat(line)
            let path = CGMutablePath()
            for step in 0...100 {
                let x = CGFloat(step) / 100 * w
                let y = h * (0.16 + n * 0.018) + sin(x / w * .pi * 2 + t + n * 0.12) * 55 + cos(x / w * .pi + t * 2) * 22
                if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.addPath(path); context.setLineWidth(line % 8 == 0 ? 1.7 : 0.8)
            context.setStrokeColor(color(line % 8 == 0 ? 0x4FA3B2 : 0x236B86, line % 8 == 0 ? 0.7 : 0.32))
            context.strokePath()
        }
    }

}
