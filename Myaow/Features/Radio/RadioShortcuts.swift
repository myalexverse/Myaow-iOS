import AppIntents

struct ToggleMyaowRadioIntent: AppIntent {
    static let title: LocalizedStringResource = "Hablar o escuchar por Radio"
    static let description = IntentDescription("Alterna tu micrófono en una conversación de Radio ya conectada. Puedes asignarlo al botón de Acción desde Atajos.")
    static let openAppWhenRun = true
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let call = CallSessionService.shared
        if call.callType == .radio, call.callState == .connected {
            if call.radioTransmitting || call.radioRequestPending { call.stopRadioTransmission(); return .result(dialog: "Ahora escuchas.") }
            guard call.canRequestRadioTurn else { return .result(dialog: "Espera a que tu contacto termine y el canal esté listo.") }
            call.startRadioTransmission()
            return .result(dialog: "Turno solicitado. Toca otra vez el botón de Acción para terminar.")
        }
        let radio = WalkieTalkieService.shared
        if radio.isTransmitting { radio.stopTransmitting(); return .result(dialog: "Ahora escuchas.") }
        guard radio.canTalk else { return .result(dialog: "Primero conecta con un contacto en Radio de Myaow.") }
        radio.startTransmitting()
        return .result(dialog: "Radio activada. Toca otra vez el botón de Acción para terminar.")
    }
}
struct MyaowRadioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToggleMyaowRadioIntent(), phrases: ["Hablar por radio con \(.applicationName)"], shortTitle: "Hablar por Radio", systemImageName: "antenna.radiowaves.left.and.right")
    }
}
