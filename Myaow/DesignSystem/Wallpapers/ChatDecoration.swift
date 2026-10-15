import Foundation

/// Stable wire identifiers. Assets are bundled; peers cannot supply URLs or paths.
nonisolated enum ChatDecoration: String, Codable, CaseIterable, Identifiable, Sendable {
    case lava, lavaViolet, lavaTeal, orbit, orbitBlue, silk, ember, water, waves, nebula, aurora, portal, grid, eclipse, titan, neonRain, binaryDunes, orbitalGarden, vertigo, silverScreen, deco, cosmicOpera, alienCrystal, classic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .lava: "Lava ámbar"
        case .lavaViolet: "Lava violeta"
        case .lavaTeal: "Lava turquesa"
        case .orbit: "Órbita cobre"
        case .orbitBlue: "Órbita azul"
        case .silk: "Seda"
        case .ember: "Brasa"
        case .water: "Agua nocturna"
        case .waves: "Marea"
        case .nebula: "Nebulosa violeta"
        case .aurora: "Aurora ionizada"
        case .portal: "Portal ámbar"
        case .grid: "Retícula neón"
        case .eclipse: "Eclipse de cobre"
        case .titan: "Mar de Titán"
        case .neonRain: "Lluvia neón"
        case .binaryDunes: "Dunas binarias"
        case .orbitalGarden: "Jardín orbital"
        case .vertigo: "Vértigo"
        case .silverScreen: "Proyector nocturno"
        case .deco: "Palacio art déco"
        case .cosmicOpera: "Ópera cósmica"
        case .alienCrystal: "Cristal alienígena"
        case .classic: "Clásico"
        }
    }
    var resource: String? {
        switch self {
        case .classic: nil
        default: "Wallpaper" + rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

/// A Lamport revision and stable event ID converge even after concurrent/offline changes.
nonisolated struct ChatDecorationEvent: Codable, Equatable, Sendable {
    let version: Int
    let id: String
    let revision: Int64
    let decoration: ChatDecoration
    let actor: String
    let participants: [String]?
    let group: String?

    func validate(sender: String, recipient: String, groupID: String?) throws {
        guard version == 1, UUID(uuidString: id) != nil, revision > 0, revision < 1_000_000_000,
              actor == sender, sender != recipient else { throw DecorationError.invalid }
        if let groupID {
            guard UUID(uuidString: groupID) != nil, group == groupID.lowercased(), participants == nil else { throw DecorationError.invalid }
        } else {
            guard group == nil, participants == [sender, recipient].sorted() else { throw DecorationError.invalid }
        }
    }
    static func canEditGroup(actor: String, recipient: String, roles: [String: String]) -> Bool {
        roles[recipient] != nil && ["admin", "owner"].contains(roles[actor] ?? "")
    }
    func supersedes(_ previous: Self?) -> Bool {
        guard let previous else { return true }
        return revision > previous.revision || (revision == previous.revision && id > previous.id)
    }
    var json: String { get throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    } }
    static func decode(_ json: String?) -> Self? {
        guard let json, json.utf8.count <= 2048 else { return nil }
        return try? JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }
}

nonisolated enum DecorationError: LocalizedError {
    case invalid, administratorRequired, unavailable
    var errorDescription: String? {
        switch self {
        case .invalid: "No pudimos verificar la decoración de este chat."
        case .administratorRequired: "Solo los administradores pueden decorar el grupo."
        case .unavailable: "Abre una conversación con un contacto para compartir su decoración."
        }
    }
}
