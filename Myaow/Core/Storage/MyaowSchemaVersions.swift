import SwiftData
import Foundation

// MARK: - Schema V1 (Current baseline)
enum MyaowSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    static var models: [any PersistentModel.Type] {
        [
            ContactModel.self,
            ConversationModel.self,
            MessageModel.self,
            MeshNodeModel.self,
            MomentModel.self
        ]
    }
}

// MARK: - Migration Plan
enum MyaowMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MyaowSchemaV1.self]
    }
    
    static var stages: [MigrationStage] {
        []
        // Future migrations go here, e.g.:
        // .lightweight(fromVersion: MyaowSchemaV1.self, toVersion: MyaowSchemaV2.self)
    }
}
