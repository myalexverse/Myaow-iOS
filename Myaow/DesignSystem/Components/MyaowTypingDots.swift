import SwiftUI

/// The dots animate as soon as typing appears, without delayed or repeating tasks.
struct MyaowTypingDots: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    let lift = reduceMotion || scenePhase != .active ? 0 :
                        max(0, sin(time * 2 * .pi / 1.5 - Double(index) * 0.7))
                    Circle()
                        .fill(MyaowColor.textTertiary)
                        .frame(width: 6, height: 6)
                        .offset(y: -2 * lift)
                        .opacity(0.55 + 0.45 * lift)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
