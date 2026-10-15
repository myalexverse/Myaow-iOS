import Foundation

/// Shares one preparation between ringing and answering; cancellation releases the per-call task.
@MainActor final class CallResourcePreparation<Resource: Sendable> {
    private var task: Task<Resource, Error>?
    var isStarted: Bool { task != nil }
    func start(_ load: @escaping @MainActor @Sendable () async throws -> Resource) {
        guard task == nil else { return }
        task = Task { try await load() }
    }
    func value() async throws -> Resource {
        guard let task else { throw CancellationError() }
        let value = try await task.value
        try Task.checkCancellation()
        return value
    }
    func cancel() { task?.cancel(); task = nil }
}
