import Foundation

public struct MyaowSticker: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let emotion: String
    // Stable, readable wire text: older versions show the expression as text.
    public var wireText: String { "🐾 " + title }
    public static let all: [Self] = [
        .init(id: "hello", title: "¡Hola!", emotion: "Amigable"),
        .init(id: "love", title: "Te quiero", emotion: "Enamorado"),
        .init(id: "yes", title: "¡Hecho!", emotion: "Fachero"),
        .init(id: "party", title: "¡Lo logramos!", emotion: "Celebración"),
        .init(id: "thinking", title: "Mmm…", emotion: "Pensativo"),
        .init(id: "wow", title: "¡Wow!", emotion: "Sorprendido"),
        .init(id: "coffee", title: "Una pausa", emotion: "Tranquilo"),
        .init(id: "busy", title: "En ello", emotion: "Ocupado"),
        .init(id: "thanks", title: "¡Gracias!", emotion: "Feliz"),
        .init(id: "sleepy", title: "Sin batería", emotion: "Agotado"),
        .init(id: "sad", title: "Hoy no", emotion: "Triste"),
        .init(id: "play", title: "¿Vamos?", emotion: "Juguetón")
    ]
    public static func match(_ text: String) -> Self? { all.first { $0.wireText == text } }
}
