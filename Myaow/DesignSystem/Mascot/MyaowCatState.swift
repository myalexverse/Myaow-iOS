//
//  MyaowCatState.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI

/// Representa los estados emocionales, humanos y operativos de la mascota Myaow
public enum MyaowCatState: String, CaseIterable, Identifiable, Sendable {
    // 1. Estados Emocionales y Humanos
    case happy = "Feliz"
    case purring = "Ronroneando"
    case playful = "Juguetón"
    case curious = "Curioso"
    case busy = "Ocupado"
    case thinking = "Pensativo"
    case bored = "Aburrido"
    case gossiping = "Chismoso"
    case cool = "Fachero"
    case hungry = "Hambriento"
    case inLove = "Enamorado"
    case sad = "Triste"
    case angry = "Enojado"
    case exhausted = "Agotado"
    case party = "Celebración"
    case ninja = "Modo Ninja"
    case calm = "Tranquilo"
    case surprised = "Sorprendido"
    case friendly = "Amigable"
    case neutral = "Neutro"
    
    case drunk = "Borracho"
    case laughing = "Risueño"
    case shy = "Tímido"
    case crying = "Llorando"
    case skeptical = "Escéptico"
    case mischievous = "Travieso"

    // 2. Estados Operativos y de Conexión
    case connecting = "Conectando"
    case connected = "Conectado"
    case sleeping = "Durmiendo"
    case protected = "Protegido"
    case openingEyes = "Bienvenida"
    
    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

/// Estilo de color del gato
public enum MyaowCatStyle {
    /// Gato naranja sobre fondo oscuro (Estilo predeterminado)
    case orangeOnDark
    /// Gato oscuro sobre fondo naranja (Estilo badge/app icon)
    case darkOnOrange
    /// Gato blanco sobre fondo transparente
    case whiteOnTransparent
    /// Gato naranja sobre fondo transparente
    case orangeOnTransparent
    /// Gato con color personalizado
    case custom(foreground: Color, background: Color?)
}

extension MyaowCatStyle: Equatable {
    public static func == (lhs: MyaowCatStyle, rhs: MyaowCatStyle) -> Bool {
        switch (lhs, rhs) {
        case (.orangeOnDark, .orangeOnDark),
             (.darkOnOrange, .darkOnOrange),
             (.whiteOnTransparent, .whiteOnTransparent),
             (.orangeOnTransparent, .orangeOnTransparent):
            return true
        case (.custom, .custom):
            return true // Custom styles are treated as equal for diff purposes
        default:
            return false
        }
    }
}
