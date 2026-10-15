#if canImport(WebRTC)
import Foundation
import UIKit
import CoreImage
import Vision
@preconcurrency import WebRTC

/// Single in-flight frame; camera callbacks never wait for Vision or rendering.
nonisolated final class CallVideoFilterProcessor: NSObject, RTCVideoCapturerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let slot = DispatchSemaphore(value: 1)
    private let queue = DispatchQueue(label: "myaow.video.effects", qos: .userInitiated)
    private let output: RTCVideoSource
    private let preview: RTCVideoSource
    private let renderer = CallFilterRenderer()
    private var active = VideoFilterSettings()
    private var draft: VideoFilterSettings?
    private var revision = 0
    private var enabled = true
    private var stopped = false
    private var gift: (PortalGift, TimeInterval)?
    var onFailure: (@Sendable () -> Void)?
    init(output: RTCVideoSource, preview: RTCVideoSource) { self.output = output; self.preview = preview }
    func configure(active: VideoFilterSettings, draft: VideoFilterSettings?) {
        lock.lock(); defer { lock.unlock() }
        self.active = active; self.draft = draft; revision += 1
    }
    func setEnabled(_ enabled: Bool) { lock.lock(); self.enabled = enabled; revision += 1; lock.unlock() }
    func show(_ gift: PortalGift) { lock.lock(); self.gift = (gift, ProcessInfo.processInfo.systemUptime); lock.unlock() }
    func invalidate() { lock.lock(); stopped = true; revision += 1; lock.unlock() }
    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        lock.lock()
        guard enabled, !stopped else { lock.unlock(); return }
        let settings = active, draft = draft, version = revision, gift = gift
        if settings.type == .normal && draft == nil {
            output.capturer(capturer, didCapture: frame); lock.unlock(); return
        }
        lock.unlock()
        guard slot.wait(timeout: .now()) == .success else { return }
        queue.async { [self] in
            defer { slot.signal() }
            autoreleasepool {
                guard let buffer = frame.buffer as? RTCCVPixelBuffer else { onFailure?(); return }
                let raw = renderer.upright(buffer: buffer.pixelBuffer, rotation: frame.rotation)
                renderer.trackFace(in: raw, needed: settings.type == .catverse || settings.type == .pocketCat || draft?.type == .catverse || draft?.type == .pocketCat)
                let time = ProcessInfo.processInfo.systemUptime
                func make(_ config: VideoFilterSettings) -> RTCVideoFrame? {
                    if config.type == .normal { return frame }
                    guard let result = renderer.render(raw, settings: config, time: time, gift: gift) else { return nil }
                    return RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: result), rotation: ._0, timeStampNs: frame.timeStampNs)
                }
                let filtered = make(settings)
                let draftFrame = draft.map { $0 == settings ? filtered : make($0) } ?? nil
                lock.lock()
                if revision == version, enabled, !stopped {
                    if let filtered { output.capturer(capturer, didCapture: filtered) }
                    if let draftFrame { preview.capturer(capturer, didCapture: draftFrame) }
                }
                lock.unlock()
                // Never fall back to raw camera frames when an effect fails.
                if filtered == nil || (draft != nil && draftFrame == nil) { onFailure?() }
            }
        }
    }
}

/// Original vector artwork, composited into the outgoing video (not a local UI sticker).
nonisolated final class CallFilterRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pool: CVPixelBufferPool?
    private var poolSize = CGSize.zero
    private var tick = 0
    private var face: CGRect?
    private var roll: CGFloat = 0
    private var mouth: CGFloat = 0
    private var eyes: CGFloat = 1
    private var lastFace = -Double.infinity
    private var overlayRenderer: UIGraphicsImageRenderer?
    private var overlaySize = CGSize.zero

    func upright(buffer: CVPixelBuffer, rotation: RTCVideoRotation) -> CIImage {
        let orientation: CGImagePropertyOrientation = switch rotation { case ._90: .right; case ._180: .down; case ._270: .left; default: .up }
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let origin = image.extent.origin
        let normalized = image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        let scale = min(1, 720 / max(normalized.extent.width, normalized.extent.height))
        return normalized.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }
    func trackFace(in image: CIImage, needed: Bool) {
        guard needed else { return }
        tick += 1
        guard tick % 3 == 1 else { return }
        let request = VNDetectFaceLandmarksRequest()
        let scale = min(1, 360 / max(image.extent.width, image.extent.height))
        do {
            try VNImageRequestHandler(ciImage: image.transformed(by: .init(scaleX: scale, y: scale))).perform([request])
            guard let found = request.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
                if ProcessInfo.processInfo.systemUptime - lastFace > 0.45 { face = nil; mouth = 0; eyes = 1; roll = 0 }
                return
            }
            let next = found.boundingBox
            if let previous = face { face = CGRect(x: previous.minX * 0.55 + next.minX * 0.45, y: previous.minY * 0.55 + next.minY * 0.45, width: previous.width * 0.55 + next.width * 0.45, height: previous.height * 0.55 + next.height * 0.45) } else { face = next }
            roll = roll * 0.5 + CGFloat(found.roll?.doubleValue ?? 0) * 0.5
            func aspect(_ region: VNFaceLandmarkRegion2D?) -> CGFloat {
                guard let points = region?.normalizedPoints, !points.isEmpty else { return 0 }
                let xs = points.map(\.x), ys = points.map(\.y)
                return ((ys.max() ?? 0) - (ys.min() ?? 0)) / max(0.001, (xs.max() ?? 0) - (xs.min() ?? 0))
            }
            mouth = mouth * 0.35 + min(1, max(0, (aspect(found.landmarks?.innerLips) - 0.04) * 2.5)) * 0.65
            eyes = max(0.12, min(1, (aspect(found.landmarks?.leftEye) + aspect(found.landmarks?.rightEye)) * 2.1))
            lastFace = ProcessInfo.processInfo.systemUptime
        } catch { face = nil; mouth = 0; eyes = 1; roll = 0 }
    }
    func render(_ raw: CIImage, settings: VideoFilterSettings, time: TimeInterval, gift: (PortalGift, TimeInterval)? = nil) -> CVPixelBuffer? {
        let width = max(2, Int(raw.extent.width) / 2 * 2), height = max(2, Int(raw.extent.height) / 2 * 2)
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let strength = CGFloat(min(1, max(0, settings.intensity)))
        var image = raw.cropped(to: bounds)
        switch settings.type {
        case .normal: break
        case .livingInk:
            let colors = image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.30 + strength * 0.30, kCIInputContrastKey: 1.04])
                .applyingFilter("CIColorPosterize", parameters: ["inputLevels": 8 - strength * 3])
            let lines = image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.7])
                .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 0.8 + strength * 1.1])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
                .applyingFilter("CIColorInvert").cropped(to: bounds)
            let ink = lines.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: colors])
            let paper = CIImage(color: CIColor(red: 1, green: 0.94, blue: 0.82, alpha: 0.14)).cropped(to: bounds)
            image = paper.composited(over: ink).cropped(to: bounds)
        case .catverse:
            image = CIImage(color: CIColor(red: 0.045, green: 0.035, blue: 0.075)).cropped(to: bounds)
            if let overlay = artwork(size: bounds.size, settings: settings, time: time, gift: gift) { image = overlay.composited(over: image) } else { return nil }
        case .pocketCat, .duoPortal:
            if let overlay = artwork(size: bounds.size, settings: settings, time: time, gift: gift) { image = overlay.composited(over: image) } else { return nil }
        }
        if poolSize != bounds.size || pool == nil {
            poolSize = bounds.size
            let attributes: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height, kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        }
        var buffer: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, [kCVPixelBufferPoolAllocationThresholdKey as String: 8] as CFDictionary, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        context.render(image, to: buffer, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
        return buffer
    }
    private func artwork(size: CGSize, settings: VideoFilterSettings, time: TimeInterval, gift: (PortalGift, TimeInterval)?) -> CIImage? {
        if overlaySize != size || overlayRenderer == nil {
            overlaySize = size
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = false
            overlayRenderer = UIGraphicsImageRenderer(size: size, format: format)
        }
        guard let overlayRenderer else { return nil }
        let image = overlayRenderer.image { renderer in
            let c = renderer.cgContext, w = size.width, h = size.height
            let motion = settings.reducedMotion ? 0 : sin(time * 1.5)
            if settings.type == .catverse {
                for i in 0..<16 {
                    let x = CGFloat((i * 97 + 29) % 1000) / 1000 * w
                    let y = CGFloat((i * 163 + 73) % 1000) / 1000 * h
                    c.setFillColor(UIColor(red: 1, green: 0.65, blue: 0.32, alpha: 0.15).cgColor)
                    c.fillEllipse(in: CGRect(x: x, y: y, width: 3 + CGFloat(i % 3), height: 3 + CGFloat(i % 3)))
                }
                let diameter = min(w * 0.76, h * 0.65)
                let offsetX = settings.reducedMotion ? 0 : ((face?.midX ?? 0.5) - 0.5) * w * 0.22
                drawCat(c, center: CGPoint(x: w/2 + offsetX, y: h * 0.49), size: diameter, tilt: settings.reducedMotion ? 0 : -roll * 0.6, mouth: mouth, eyes: eyes, time: time, reduced: settings.reducedMotion)
            } else if settings.type == .pocketCat {
                let diameter = w * (0.21 + 0.12 * settings.intensity)
                let x = min(w - diameter * 0.58, max(diameter * 0.58, (face?.maxX ?? 0.7) * w + diameter * 0.16))
                let y = min(h - diameter * 0.68, max(diameter * 0.68, (1 - (face?.minY ?? 0.3)) * h + diameter * 0.12))
                drawCat(c, center: CGPoint(x: x, y: y), size: diameter, tilt: settings.reducedMotion ? 0 : -roll * 0.3, mouth: mouth, eyes: eyes, time: time, reduced: settings.reducedMotion)
            } else {
                let portal = CGRect(x: w * 0.07, y: h * 0.2, width: w * 0.18, height: h * 0.50)
                c.saveGState()
                c.setShadow(offset: .zero, blur: 14, color: UIColor.systemPurple.cgColor)
                c.setStrokeColor(UIColor(red: 0.70, green: 0.48, blue: 1, alpha: 0.9).cgColor)
                c.setLineWidth(w * 0.009); c.strokeEllipse(in: portal.insetBy(dx: CGFloat(motion) * 2, dy: 0))
                c.setStrokeColor(UIColor(red: 1, green: 0.69, blue: 0.32, alpha: 0.85).cgColor)
                c.setLineWidth(w * 0.004); c.strokeEllipse(in: portal.insetBy(dx: w * 0.015, dy: -h * 0.015))
                c.restoreGState()
                if let (gift, sent) = gift, time - sent >= 0, time - sent < 2.6 {
                    let progress = min(1, (time - sent) / 2.6)
                    let x = settings.reducedMotion ? w * 0.5 : portal.midX + CGFloat(progress) * w * 0.6
                    let y = settings.reducedMotion ? h * 0.4 : h * 0.45 - sin(progress * .pi) * h * 0.14
                    let font = UIFont.systemFont(ofSize: w * 0.16)
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.systemOrange]
                    (gift.symbol as NSString).draw(at: CGPoint(x: x - w * 0.08, y: y), withAttributes: attributes)
                }
            }
        }
        return image.cgImage.map { CIImage(cgImage: $0) }
    }
    private func drawCat(_ c: CGContext, center: CGPoint, size: CGFloat, tilt: CGFloat, mouth: CGFloat, eyes: CGFloat, time: Double, reduced: Bool) {
        c.saveGState(); defer { c.restoreGState() }
        c.translateBy(x: center.x, y: center.y); c.rotate(by: tilt); c.scaleBy(x: size, y: size)
        let ink = UIColor(red: 0.09, green: 0.055, blue: 0.10, alpha: 1).cgColor
        let gold = UIColor(red: 1, green: 0.55, blue: 0.19, alpha: 1).cgColor
        c.setShadow(offset: CGSize(width: 0, height: 0.035), blur: 0.065, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        c.setFillColor(gold); c.setStrokeColor(ink); c.setLineWidth(0.014); c.setLineJoin(.round)
        let silhouette = CGMutablePath()
        silhouette.move(to: CGPoint(x: -0.40, y: -0.1))
        silhouette.addQuadCurve(to: CGPoint(x: -0.40, y: -0.52), control: CGPoint(x: -0.49, y: -0.48))
        silhouette.addLine(to: CGPoint(x: -0.18, y: -0.34))
        silhouette.addQuadCurve(to: CGPoint(x: 0.18, y: -0.34), control: CGPoint(x: 0, y: -0.41))
        silhouette.addLine(to: CGPoint(x: 0.40, y: -0.52))
        silhouette.addQuadCurve(to: CGPoint(x: 0.40, y: -0.10), control: CGPoint(x: 0.49, y: -0.48))
        silhouette.addCurve(to: CGPoint(x: -0.40, y: -0.10), control1: CGPoint(x: 0.64, y: 0.48), control2: CGPoint(x: -0.64, y: 0.48))
        silhouette.closeSubpath(); c.addPath(silhouette); c.drawPath(using: .fillStroke)
        c.setShadow(offset: .zero, blur: 0)
        c.saveGState(); c.addPath(silhouette); c.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(red: 1, green: 0.81, blue: 0.47, alpha: 0.9).cgColor, UIColor(red: 1, green: 0.40, blue: 0.13, alpha: 0.1).cgColor] as CFArray, locations: [0, 1]) {
            c.drawLinearGradient(gradient, start: CGPoint(x: -0.2, y: -0.35), end: CGPoint(x: 0.2, y: 0.35), options: [])
        }
        c.restoreGState()
        c.setFillColor(UIColor(red: 0.76, green: 0.29, blue: 0.27, alpha: 1).cgColor)
        for sign: CGFloat in [-1, 1] {
            c.beginPath(); c.move(to: CGPoint(x: sign * 0.36, y: -0.41)); c.addLine(to: CGPoint(x: sign * 0.35, y: -0.20)); c.addLine(to: CGPoint(x: sign * 0.22, y: -0.31)); c.closePath(); c.fillPath()
        }
        c.setFillColor(UIColor(red: 1, green: 0.90, blue: 0.72, alpha: 0.80).cgColor)
        c.fillEllipse(in: CGRect(x: -0.24, y: 0.035, width: 0.48, height: 0.23))
        let idleBlink: CGFloat = !reduced && time.truncatingRemainder(dividingBy: 4.7) < 0.12 ? 0.14 : 1
        let eyeHeight = 0.105 * min(eyes, idleBlink)
        c.setFillColor(ink)
        for sign: CGFloat in [-1, 1] {
            c.fillEllipse(in: CGRect(x: sign * 0.18 - 0.037, y: -0.09 - eyeHeight/2, width: 0.074, height: eyeHeight))
            if eyeHeight > 0.04 { c.setFillColor(UIColor.white.withAlphaComponent(0.9).cgColor); c.fillEllipse(in: CGRect(x: sign * 0.18 - 0.012, y: -0.12, width: 0.015, height: 0.018)); c.setFillColor(ink) }
        }
        c.move(to: CGPoint(x: -0.042, y: 0.032)); c.addQuadCurve(to: CGPoint(x: 0.042, y: 0.032), control: CGPoint(x: 0, y: 0.012)); c.addLine(to: CGPoint(x: 0, y: 0.07)); c.closePath(); c.fillPath()
        c.setLineWidth(0.013); c.setLineCap(.round); c.setStrokeColor(ink)
        if mouth > 0.10 {
            let height = 0.028 + mouth * 0.10
            c.fillEllipse(in: CGRect(x: -0.046, y: 0.09, width: 0.092, height: height))
            c.setFillColor(UIColor(red: 1, green: 0.42, blue: 0.48, alpha: 1).cgColor)
            c.fillEllipse(in: CGRect(x: -0.027, y: 0.09 + height * 0.6, width: 0.054, height: height * 0.3))
        } else {
            c.move(to: CGPoint(x: -0.064, y: 0.105)); c.addQuadCurve(to: CGPoint(x: 0, y: 0.085), control: CGPoint(x: -0.04, y: 0.14)); c.addQuadCurve(to: CGPoint(x: 0.064, y: 0.105), control: CGPoint(x: 0.04, y: 0.14)); c.strokePath()
        }
        c.setLineWidth(0.009)
        for sign: CGFloat in [-1, 1] { for i in 0..<2 {
            c.move(to: CGPoint(x: sign * 0.27, y: 0.06 + CGFloat(i) * 0.045)); c.addLine(to: CGPoint(x: sign * 0.44, y: 0.03 + CGFloat(i) * 0.08)); c.strokePath()
        } }
    }
}
#endif
