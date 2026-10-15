import Foundation

public enum MessageDeliveryStatus: String, Codable, Sendable {
    case queued         // En cola offline (esperando conexión o nodo mesh)
    case sending        // Cifrando y preparando el envío
    case sent           // Aceptado por el servidor para entrega
    case delivered      // Guardado por el destinatario
    case read           // Visto / Leído con resplandor Naranja Myaow
    case meshRelayed    // Entregado mediante saltos entre teléfonos sin Internet
    
    public var labelText: String {
        switch self {
        case .queued: return "En cola local"
        case .sending: return "Cifrando..."
        case .sent: return "Enviado"
        case .delivered: return "Entregado"
        case .read: return "Leído"
        case .meshRelayed: return "Entregado vía Mesh Offline"
        }
    }
}

