//
//  MyaowTypography.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

public struct MyaowFont {
    /// Título grande (28pt, Semibold Rounded)
    public static let largeTitle = Font.system(size: 28, weight: .bold)
    
    /// Título de pantalla (22pt, Semibold Rounded)
    public static let title = Font.system(size: 22, weight: .semibold)
    
    /// Titular secundario (18pt, Semibold Rounded)
    public static let headline = Font.system(size: 18, weight: .semibold)
    
    /// Subtítulo (16pt, Medium Rounded)
    public static let subheadline = Font.system(size: 16, weight: .medium)
    
    /// Cuerpo de texto principal (15pt, Regular Rounded)
    public static let body = Font.system(size: 16, weight: .regular)
    
    /// Cuerpo de texto con énfasis (15pt, Medium Rounded)
    public static let bodyMedium = Font.system(size: 16, weight: .medium)
    
    /// Texto de llamada o botones (14pt, Semibold Rounded)
    public static let callout = Font.system(size: 14, weight: .semibold)
    
    /// Pie de foto y metadatos (12pt, Regular Rounded)
    public static let caption = Font.system(size: 12, weight: .regular)
    
    /// Pie de foto con peso medio (12pt, Medium Rounded)
    public static let captionMedium = Font.system(size: 12, weight: .medium)
    
    /// Microtextos / Badges / Horas (10pt, Medium Rounded)
    public static let micro = Font.system(size: 11, weight: .semibold)
    
    /// Tipografía monoespaciada para IDs y hashes criptográficos
    public static let monoCode = Font.system(size: 13, weight: .semibold, design: .monospaced)
    public static let monoCodeLarge = Font.system(size: 17, weight: .bold, design: .monospaced)
}

public extension Font {
    static let myaowLargeTitle = MyaowFont.largeTitle
    static let myaowTitle = MyaowFont.title
    static let myaowHeadline = MyaowFont.headline
    static let myaowSubheadline = MyaowFont.subheadline
    static let myaowBody = MyaowFont.body
    static let myaowBodyMedium = MyaowFont.bodyMedium
    static let myaowCallout = MyaowFont.callout
    static let myaowCaption = MyaowFont.caption
    static let myaowCaptionMedium = MyaowFont.captionMedium
    static let myaowMicro = MyaowFont.micro
    static let myaowMono = MyaowFont.monoCode
    static let myaowMonoLarge = MyaowFont.monoCodeLarge
}
