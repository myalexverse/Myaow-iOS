import SwiftUI
import UIKit

@MainActor @Observable
public final class MyaowNudgeService {
    public static let shared = MyaowNudgeService()
    public private(set) var isShaking = false
    public private(set) var shakeOffset: CGFloat = 0
    public private(set) var bubbleJitter: CGFloat = 0
    public private(set) var showingNudgeEffect = false
    public private(set) var nudgeSenderName = ""
    public private(set) var activeTheme: NudgeTheme = .electric
    public private(set) var activeSound: CatVocalSynthesizer.CatSoundType = .classic
    public private(set) var cooldownSeconds = 0
    private var effectTask: Task<Void, Never>?
    private var cooldownTask: Task<Void, Never>?
    private var lastReceivedAt = Date.distantPast

    public func triggerNudge(senderName: String, theme: NudgeTheme = .electric) {
        activeTheme = theme
        let sound: CatVocalSynthesizer.CatSoundType = switch theme {
        case .electric: .electric
        case .cosmicPurr: .purr
        case .clawSwipe: .hiss
        case .liquidSplash: .melodic
        case .ghostGaze: .lazy
        }
        present(senderName: senderName, sound: sound)
    }
    public func receive(senderName: String, text: String, timestamp: Date) {
        // History catch-up must never produce a storm of sounds on unlocking.
        guard UIApplication.shared.applicationState == .active,
              MyaowNudgePolicy.shouldPresent(sentAt: timestamp, now: Date(), lastPresentedAt: lastReceivedAt) else { return }
        lastReceivedAt = Date()
        present(senderName: senderName, sound: .from(message: text) ?? .classic)
    }
    private func present(senderName: String, sound: CatVocalSynthesizer.CatSoundType) {
        guard UIApplication.shared.applicationState == .active, CatVocalSynthesizer.shared.audioIsAvailable else { return }
        effectTask?.cancel()
        nudgeSenderName = senderName; activeSound = sound
        if UserDefaults.standard.object(forKey: "myaow_nudge_autoplay") as? Bool != false {
            CatVocalSynthesizer.shared.playCatSound(sound)
        } else if UserDefaults.standard.object(forKey: "myaow_nudge_haptics") as? Bool != false {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        }
        withAnimation(.easeOut(duration: 0.2)) { showingNudgeEffect = true }
        effectTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { showingNudgeEffect = false }
        }
    }
    public func dismissEffect() {
        effectTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { showingNudgeEffect = false }
    }
    public func startCooldown() {
        cooldownTask?.cancel()
        let until = Date().addingTimeInterval(5)
        cooldownSeconds = 5
        cooldownTask = Task { @MainActor in
            while !Task.isCancelled {
                cooldownSeconds = max(0, Int(ceil(until.timeIntervalSinceNow)))
                if cooldownSeconds == 0 { return }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}
