import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class MyaowStorageController {
    private(set) var container: ModelContainer?
    private(set) var errorMessage: String?

    private let configuration: ModelConfiguration?

    init(configuration: ModelConfiguration? = nil) {
        self.configuration = configuration
        open()
    }

    func open() {
        guard container == nil else { return }
        do {
            let schema = Schema(versionedSchema: MyaowSchemaV1.self)
            let configuration = self.configuration ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(
                for: ContactModel.self, ConversationModel.self, MessageModel.self, MeshNodeModel.self, MomentModel.self,
                migrationPlan: MyaowMigrationPlan.self, configurations: configuration
            )
            errorMessage = nil
        } catch {
            // Never delete, replace, or open an empty store when an existing store cannot be read.
            container = nil
            errorMessage = "No pudimos abrir tus conversaciones. Tus archivos siguen en este iPhone. Desbloquéalo, revisa el espacio disponible y vuelve a intentar."
        }
    }
}
