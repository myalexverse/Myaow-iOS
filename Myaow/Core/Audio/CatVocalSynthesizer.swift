import AVFoundation
import UIKit
import Observation

/// One mastered asset per sound, shared by previews and received messages.
@MainActor @Observable
public final class CatVocalSynthesizer: NSObject, AVAudioPlayerDelegate {
    public static let shared = CatVocalSynthesizer()
    public enum CatSoundType: String, CaseIterable, Identifiable, Sendable {
        // Keep wire identifiers compatible with previously sent maullidos.
        case classic, electric, purr = "cosmic", melodic, hiss = "claw", lazy, kiss, giggle, party, question, sleepy, echo, mentada, admiration
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .classic: "Miau"
            case .electric: "Chispa"
            case .purr: "Ronroneo"
            case .melodic: "Canturreo"
            case .hiss: "Zarpazo"
            case .lazy: "Bostezo"
            case .kiss: "Besito"
            case .giggle: "Risita"
            case .party: "Fiesta"
            case .question: "¿Miau?"
            case .sleepy: "Dulces sueños"
            case .echo: "Eco lunar"
            case .mentada: "La mentada"
            case .admiration: "Fiu miau"
            }
        }
        public var subtitle: String {
            switch self {
            case .classic: "Un saludo con personalidad"
            case .electric: "Un toque de energía"
            case .purr: "Cerca, aunque estés lejos"
            case .melodic: "Tres notas para alegrar el día"
            case .hiss: "Para llamar su atención"
            case .lazy: "Sin prisa, aquí estoy"
            case .kiss: "Un beso que sí se escucha"
            case .giggle: "La risa es contagiosa"
            case .party: "Esto merece celebrarse"
            case .question: "Tengo una pequeña pregunta"
            case .sleepy: "Nos vemos en los sueños"
            case .echo: "Un saludo desde otra órbita"
            case .mentada: "Cinco notas. Ya te la sabes."
            case .admiration: "Ese look merece un chiflido"
            }
        }
        public var iconSymbol: String { "🐾" }
        public var duration: Double {
            switch self {
            case .classic: 0.82
            case .electric: 0.66
            case .purr: 1.24
            case .melodic: 1.08
            case .hiss: 0.70
            case .lazy: 1.36
            case .kiss: 0.72
            case .giggle: 1.12
            case .party: 1.45
            case .question: 0.94
            case .sleepy: 1.60
            case .echo: 1.48
            case .mentada: 1.72
            case .admiration: 1.58
            }
        }
        public var catState: MyaowCatState {
            switch self {
            case .classic: .friendly
            case .electric: .cool
            case .purr, .kiss: .inLove
            case .melodic, .giggle: .playful
            case .hiss: .ninja
            case .lazy: .bored
            case .party: .party
            case .question: .curious
            case .sleepy: .sleeping
            case .echo: .thinking
            case .mentada: .mischievous
            case .admiration: .inLove
            }
        }
        public var effectSymbol: String {
            switch self {
            case .classic: "waveform"
            case .electric: "bolt.fill"
            case .purr, .kiss: "heart.fill"
            case .melodic: "music.note"
            case .hiss: "sparkles"
            case .lazy, .sleepy: "moon.stars.fill"
            case .giggle: "face.smiling.fill"
            case .party: "party.popper.fill"
            case .question: "questionmark"
            case .echo: "sparkle"
            case .mentada: "bolt.fill"
            case .admiration: "heart.fill"
            }
        }
        public var wireText: String { "[NUDGE:\(rawValue)] \(displayName)" }
        public static func from(message: String) -> Self? {
            allCases.first { message.hasPrefix("[NUDGE:\($0.rawValue)]") }
        }
    }
    public private(set) var playingType: CatSoundType?
    public private(set) var playbackSourceID: UUID?
    public private(set) var playbackProgress = 0.0
    public private(set) var lastError: String?
    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private override init() {
        super.init()
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification, UIApplication.willResignActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.stop() }
            })
        }
    }
    public var audioIsAvailable: Bool {
        [.idle, .ended].contains(CallSessionService.shared.callState) &&
        !VoiceRecordingService.shared.isRecording && !VoicePlaybackService.shared.isPlaying &&
        !WalkieTalkieService.shared.transport.isActive
    }
    @discardableResult
    public func playCatSound(_ type: CatSoundType, haptic: Bool = true, sourceID: UUID? = nil) -> Bool {
        stop(); lastError = nil
        guard UIApplication.shared.applicationState == .active, audioIsAvailable else {
            lastError = "Escucha el maullido cuando termines la llamada, Radio o el audio actual."
            return false
        }
        guard let url = Bundle.main.url(forResource: "myaow-\(type.rawValue)", withExtension: "wav") else {
            lastError = "Este sonido no está disponible. Actualiza Myaow e inténtalo de nuevo."
            return false
        }
        do {
            // Ambient respects Silent Mode and does not interrupt other apps' music.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let next = try AVAudioPlayer(contentsOf: url)
            next.delegate = self
            next.prepareToPlay()
            guard next.play() else { throw CocoaError(.fileReadCorruptFile) }
            player = next; playingType = type; playbackSourceID = sourceID
            if haptic && UserDefaults.standard.object(forKey: "myaow_nudge_haptics") as? Bool != false {
                UIImpactFeedbackGenerator(style: type == .purr ? .soft : .light).impactOccurred(intensity: 0.65)
            }
            progressTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(40))
                    guard !Task.isCancelled, let self, let player = self.player else { return }
                    guard self.audioIsAvailable else { self.stop(); return }
                    self.playbackProgress = min(1, player.currentTime / max(player.duration, 0.01))
                }
            }
            return true
        } catch {
            lastError = "No pudimos reproducir el maullido. Vuelve a intentarlo."
            stop(); return false
        }
    }
    public func stop() {
        progressTask?.cancel(); progressTask = nil
        player?.stop(); player = nil; playingType = nil; playbackSourceID = nil; playbackProgress = 0
        // Do not deactivate the shared session: a call may have just taken ownership.
    }
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.stop()
        }
    }
}
