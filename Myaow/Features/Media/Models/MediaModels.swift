//
//  MediaModels.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public enum MediaQualityMode: String, CaseIterable, Identifiable, Sendable {
    case hdOptimized = "HD optimizado"
    case losslessOriginal = "Original"
    
    public var id: String { rawValue }
    
    public var badgeTitle: String {
        switch self {
        case .hdOptimized: return "HD"
        case .losslessOriginal: return "LOSSLESS"
        }
    }
    
    public var description: String {
        switch self {
        case .hdOptimized:
            return "Compresión inteligente de alta definición. Ideal para envío rápido."
        case .losslessOriginal:
            return "Archivo original sin recomprimir; puede contener metadatos."
        }
    }
}

public struct MediaAttachmentPayload: Sendable {
    public let data: Data
    public let isVideo: Bool
    public let quality: MediaQualityMode
    public let caption: String
    public let fileSizeFormatted: String
    public let dimensionsFormatted: String
    
    nonisolated public init(
        data: Data,
        isVideo: Bool,
        quality: MediaQualityMode,
        caption: String,
        fileSizeFormatted: String,
        dimensionsFormatted: String
    ) {
        self.data = data
        self.isVideo = isVideo
        self.quality = quality
        self.caption = caption
        self.fileSizeFormatted = fileSizeFormatted
        self.dimensionsFormatted = dimensionsFormatted
    }
}
