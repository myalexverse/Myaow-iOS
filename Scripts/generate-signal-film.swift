// Original silent, seamless signal texture. No downloaded or third-party footage.
import Foundation
import AVFoundation
import CoreGraphics

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 640, height = 640, fps: Int32 = 24, frames = 144
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height, AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 850_000]])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
for frame in 0..<frames {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    var optional: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &optional)
    let buffer = optional!
    CVPixelBufferLockBaseAddress(buffer, [])
    let ptr = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let t = Double(frame) / Double(frames) * .pi * 2
    for y in 0..<height {
        let fy = Double(y) / Double(height)
        let wave = sin(fy * 13 + t) * 0.12 + sin(fy * 32 - t) * 0.025
        for x in 0..<width {
            let fx = Double(x) / Double(width)
            let glow = max(0, 1 - abs(fx - 0.65 - wave) * 2.8) * max(0, sin(fy * 3.4 + t) * 0.5 + 0.5)
            let noise = Double((x &* 73 ^ y &* 131 ^ (frame % frames) &* 11) & 31) / 31.0
            let scan = y % 4 == 0 ? 0.58 : 1.0
            let i = y * stride + x * 4
            ptr[i] = 255
            ptr[i+1] = UInt8(min(255, (12 + glow * 96 + noise * 7) * scan))
            ptr[i+2] = UInt8(min(255, (16 + glow * 43 + noise * 7) * scan))
            ptr[i+3] = UInt8(min(255, (20 + glow * 17 + noise * 8) * scan))
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    precondition(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: fps)))
}
input.markAsFinished()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()
precondition(writer.status == .completed, writer.error?.localizedDescription ?? "Video failed")
print("Created 6-second silent video: \(output.path)")
