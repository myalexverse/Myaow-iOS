import UIKit
import UserNotifications
import Observation

@MainActor @Observable
public final class APNsNotificationManager: NSObject {
    public static let shared = APNsNotificationManager()
    public private(set) var isPermissionGranted = false
    public private(set) var registrationError: String?
    public private(set) var apnsDeviceTokenHex: String?
    private var voipToken: String?
    private var syncTask: Task<Void, Never>?
    private var lastRegistration: Data?
    private var installation: String {
        if let value = UserDefaults.standard.string(forKey: "myaow_push_installation") { return value }
        let value = UUID().uuidString; UserDefaults.standard.set(value, forKey: "myaow_push_installation"); return value
    }
    public func requestNotificationPermissions() {
        Task {
            do { isPermissionGranted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]) }
            catch { registrationError = "No pudimos solicitar permiso para las notificaciones." }
            await refreshRegistration()
        }
    }
    func refreshRegistration() async {
        guard IdentityManager.shared.hasCompletedOnboarding, !DesignPreviewData.isEnabled else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        isPermissionGranted = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        if isPermissionGranted { UIApplication.shared.registerForRemoteNotifications() }
        CallSystemCoordinator.shared.start()
        synchronizeDevice()
    }
    public func handleDeviceToken(_ data: Data) {
        apnsDeviceTokenHex = data.map { String(format: "%02x", $0) }.joined()
        synchronizeDevice()
    }
    func handleVoIPToken(_ data: Data?) {
        voipToken = data?.map { String(format: "%02x", $0) }.joined()
        synchronizeDevice()
    }
    func registrationFailed() { registrationError = "Este dispositivo todavía no pudo registrar sus notificaciones con Apple." }
    func synchronizeDevice() {
        guard !DesignPreviewData.isEnabled, OnlineMessagingService.shared.status == .online,
              let session = OnlineMessagingService.shared.sessionToken else { return }
        let owner = IdentityManager.shared.currentIdentity.myaowId
        let environment = Bundle.main.object(forInfoDictionaryKey: "MyaowPushEnvironment") as? String ?? ""
        guard ["sandbox","production"].contains(environment) else { registrationError = "Falta configurar el entorno de notificaciones."; return }
        let body: [String: Any] = ["installation": installation, "environment": environment,
            "bundleId": Bundle.main.bundleIdentifier ?? "",
            "alertToken": isPermissionGranted ? (apnsDeviceTokenHex as Any? ?? NSNull()) : NSNull(),
            "voipToken": voipToken as Any? ?? NSNull(), "callers": CallSystemCoordinator.shared.allowedCallers]
        guard let marker = try? JSONSerialization.data(withJSONObject: ["owner":owner,"session":session,"body":body], options:.sortedKeys), marker != lastRegistration else { return }
        syncTask?.cancel()
        syncTask = Task {
            do {
                let data = try await RelayAPI.request("/api/v1/push/device", method: "PUT", body: body)
                guard !Task.isCancelled, owner == IdentityManager.shared.currentIdentity.myaowId else { return }
                if let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any], result["deliveryEnabled"] as? Bool == false {
                    registrationError = "Las notificaciones de Apple aún no están activadas en este servidor."
                    return
                }
                lastRegistration = marker; registrationError = nil
            } catch { if !Task.isCancelled { registrationError = "No pudimos activar los avisos en el servidor. Se reintentará al conectar." } }
        }
    }
}
