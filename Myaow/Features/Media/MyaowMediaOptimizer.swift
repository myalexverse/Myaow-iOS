//
//  MyaowMediaOptimizer.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import AVFoundation

/// Optimizador de alto rendimiento para decodificación asíncrona, caché de imágenes y compresión sin bloquear el hilo principal
public final class MyaowMediaOptimizer: @unchecked Sendable {
    public static let shared = MyaowMediaOptimizer()
    
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB
    }
    
    /// Obtiene o genera una miniatura optimizada en segundo plano con ImageIO
    public func getOptimizedThumbnail(for data: Data, maxDimension: CGFloat = 480, cacheKey: String? = nil, isVideo: Bool = false) async -> UIImage? {
        let key = (cacheKey ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()) + "_\(Int(maxDimension))_\(isVideo)"
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if isVideo {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("myaow-thumbnail-" + UUID().uuidString + ".mov")
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    try data.write(to: url, options: [.atomic, .completeFileProtection])
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                    generator.appliesPreferredTrackTransform = true
                    generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
                    let frame = try await generator.image(at: .zero).image
                    let image = UIImage(cgImage: frame)
                    MyaowMediaOptimizer.shared.cache.setObject(image, forKey: key as NSString, cost: frame.bytesPerRow * frame.height)
                    return image
                } catch { return nil }
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
            ]
            
            guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                // Reject unreadable content without decoding an unbounded full-resolution fallback.
                return nil
            }
            
            let thumbnail = UIImage(cgImage: cgImage)
            MyaowMediaOptimizer.shared.cache.setObject(thumbnail, forKey: key as NSString, cost: cgImage.bytesPerRow * cgImage.height)
            return thumbnail
        }.value
    }
    
    /// Procesa y comprime fotos seleccionadas de forma asíncrona fuera del hilo de interfaz
    public func optimizeSelectedPhoto(data: Data) async -> (optimizedData: Data, thumbnail: UIImage?) {
        return await Task.detached(priority: .userInitiated) {
            let thumb = await MyaowMediaOptimizer.shared.getOptimizedThumbnail(for: data, maxDimension: 600)
            
            // Si la imagen es gigantesca (> 4MB), optimizarla para envío fluido
            if data.count > 4 * 1024 * 1024, let uiImage = UIImage(data: data) {
                let compressed = uiImage.jpegData(compressionQuality: 0.85) ?? data
                return (compressed, thumb)
            }
            return (data, thumb)
        }.value
    }
}

/// Vista asíncrona de miniatura con caché para evitar bloqueos del Main Thread
public struct MyaowAsyncThumbnailView: View {
    public let data: Data?
    public var maxDimension: CGFloat = 480
    public var cornerRadius: CGFloat = 14
    public var isVideo: Bool = false
    public var contentMode: ContentMode = .fill
    @State private var failed = false
    
    @State private var loadedImage: UIImage? = nil
    
    public init(data: Data?, maxDimension: CGFloat = 480, cornerRadius: CGFloat = 14, isVideo: Bool = false, contentMode: ContentMode = .fill) {
        self.data = data
        self.maxDimension = maxDimension
        self.cornerRadius = cornerRadius
        self.isVideo = isVideo
        self.contentMode = contentMode
    }
    
    public var body: some View {
        ZStack {
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(hex: "#1E1E22"))
                    .overlay(
                        Group {
                            if failed { Image(systemName: isVideo ? "video" : "photo").foregroundStyle(MyaowColor.textSecondary) }
                            else { ProgressView().tint(MyaowColor.orange) }
                        }
                    )
            }
        }
        .task(id: data) {
            loadedImage = nil; failed = false
            guard let data = data else { return }
            let img = await MyaowMediaOptimizer.shared.getOptimizedThumbnail(for: data, maxDimension: maxDimension, isVideo: isVideo)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.loadedImage = img
                self.failed = img == nil
            }
        }
    }
}
