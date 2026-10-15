//
//  ContentView.swift
//  Myaow
//
//  Created for Myaow - "Tecnología que se siente cercana"
//

import SwiftUI
import SwiftData

public struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isSplashFinished: Bool = false
    @State private var identityManager = IdentityManager.shared

    public var body: some View {
        ZStack {
            MyaowColor.charcoal
                .ignoresSafeArea()

            if let error = identityManager.storageError {
                MyaowRecoveryView(message: error) { identityManager.reloadIdentity() }
            } else if isSplashFinished && identityManager.isInitialized {
                if identityManager.hasCompletedOnboarding {
                    #if DEBUG && targetEnvironment(simulator) && canImport(WebRTC)
                    if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--radio-console-preview") {
                        RadioConsolePreview()
                    } else if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--filter-check") {
                        CallFilterSimulatorCheckView()
                    } else if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--speech-studio") {
                        CatSpeechStudioPreview()
                    } else if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--emotion-atlas") {
                        EmotionAtlasPreview()
                    } else if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--call-audio-check") {
                        CallAudioSimulatorCheckView()
                    } else {
                        MainTabView().transition(.opacity)
                    }
                    #else
                    MainTabView()
                        .transition(.opacity)
                    #endif
                } else {
                    OnboardingRegistrationView()
                        .transition(.opacity)
                }
            } else {
                SplashScreenView(isReady: identityManager.isInitialized) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                        isSplashFinished = true
                    }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ConversationModel.self, MessageModel.self, ContactModel.self, MeshNodeModel.self], inMemory: true)
}
