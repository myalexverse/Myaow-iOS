import SwiftUI

/// A short brand entrance, followed by an indeterminate indicator only when
/// initialization is still running. It never fabricates loading percentages.
public struct SplashScreenView: View {
    public let isReady: Bool
    public let onFinished: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var eyesOpen = false
    @State private var introFinished = false
    @State private var completed = false

    public init(isReady: Bool = true, onFinished: @escaping () -> Void) {
        self.isReady = isReady
        self.onFinished = onFinished
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                MyaowColor.charcoal.ignoresSafeArea()
                RadialGradient(colors: [MyaowColor.orange.opacity(0.09), .clear], center: .center,
                               startRadius: 10, endRadius: 210)
                    .frame(width: 420, height: 420)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.43)
                    .opacity(appeared ? 1 : 0)
                VStack(spacing: 28) {
                    ZStack {
                        Circle().strokeBorder(Color.white.opacity(0.055), lineWidth: 1).frame(width: 208, height: 208)
                        Circle().strokeBorder(Color.white.opacity(0.035), lineWidth: 1).frame(width: 246, height: 246)
                        MyaowOfficialIsotype(size: 146, style: .orange, eyeProgress: eyesOpen ? 1 : 0.08)
                            .scaleEffect(appeared ? 1 : (reduceMotion ? 1 : 0.94))
                    }
                    .frame(height: 246)
                    VStack(spacing: 12) {
                        MyaowWordmarkView(fontSize: 43, textColor: MyaowColor.textPrimary)
                        Text("Cerca, a tu manera.")
                            .font(.system(size: 15)).tracking(0.2).foregroundStyle(MyaowColor.textSecondary)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 8)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.43)
                VStack(spacing: 18) {
                    if introFinished && !isReady {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small).tint(MyaowColor.orange)
                            Text("Abriendo tu espacio…").font(.system(size: 13)).foregroundStyle(MyaowColor.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    HStack(spacing: 8) {
                        Capsule().fill(MyaowColor.orange).frame(width: 16, height: 3)
                        Text("TU MUNDO. TU GENTE.")
                            .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2)
                            .foregroundStyle(MyaowColor.textTertiary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 32)
                .opacity(appeared ? 1 : 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Myaow. Abriendo tu espacio.")
        .task {
            guard !introFinished else { finishIfReady(); return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.38)) { appeared = true }
            do {
                if !reduceMotion { try await Task.sleep(for: .milliseconds(180)) }
                try Task.checkCancellation()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.32)) { eyesOpen = true }
                if !reduceMotion { try await Task.sleep(for: .milliseconds(540)) }
                try Task.checkCancellation()
                introFinished = true
                finishIfReady()
            } catch { /* SwiftUI cancels the entrance when this screen leaves. */ }
        }
        .onChange(of: isReady) { _, _ in finishIfReady() }
        .onChange(of: introFinished) { _, _ in finishIfReady() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { appeared = true; eyesOpen = true; introFinished = true; finishIfReady() }
        }
    }

    private func finishIfReady() {
        guard isReady, introFinished, !completed else { return }
        completed = true
        onFinished()
    }
}
