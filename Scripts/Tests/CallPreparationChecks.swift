import Foundation
@main struct CallPreparationChecks {
    @MainActor static func main() async throws {
        var loads = 0
        let preparation = CallResourcePreparation<Int>()
        let clock = ContinuousClock()
        let start = clock.now
        preparation.start { loads += 1; try await Task.sleep(for: .milliseconds(300)); return 42 }
        let cold = try await preparation.value()
        let coldDelay = start.duration(to: clock.now)
        precondition(cold == 42 && loads == 1)
        preparation.cancel()
        preparation.start { loads += 1; try await Task.sleep(for: .milliseconds(300)); return 43 }
        // The server preparation completes while the incoming-call screen rings.
        try await Task.sleep(for: .milliseconds(500))
        preparation.start { preconditionFailure("Answer must reuse the preparation") }
        let answered = clock.now
        let warm = try await preparation.value()
        let warmDelay = answered.duration(to: clock.now)
        precondition(warm == 43 && loads == 2 && warmDelay < coldDelay / 2)
        preparation.cancel()
        preparation.start { try await Task.sleep(for: .seconds(10)); return 0 }
        preparation.cancel()
        do { _ = try await preparation.value(); preconditionFailure("A cancelled call must not reuse its preparation") }
        catch is CancellationError { }
        preparation.start { 44 }
        let next = try await preparation.value()
        precondition(next == 44)
        print("PASS call preparation: single request, reuse on answer, cancellation and next-call isolation.")
        print("Controlled 300 ms resource delay — cold answer: \(coldDelay); prepared while ringing: \(warmDelay). This is not an internet-call latency measurement.")
    }
}
