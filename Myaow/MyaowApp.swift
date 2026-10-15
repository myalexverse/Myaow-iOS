//
//  MyaowApp.swift
//  Myaow
//
//  Created by Alex Doven on 22/08/26.
//

import SwiftUI
import SwiftData
import UserNotifications

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG && targetEnvironment(simulator)
        if DesignPreviewData.isEnabled && ProcessInfo.processInfo.arguments.contains("--notification-preview") {
            APNsNotificationManager.shared.requestNotificationPermissions()
        }
        #endif
        CallSystemCoordinator.shared.start()
        Task { await APNsNotificationManager.shared.refreshRegistration() }
        return true
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // The open app receives messages through its authenticated connection.
        completionHandler([])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        OnlineMessagingService.shared.startConnectionHeartbeat()
        completionHandler()
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        APNsNotificationManager.shared.handleDeviceToken(deviceToken)
    }
    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { await APNsNotificationManager.shared.refreshRegistration() }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        APNsNotificationManager.shared.registrationFailed()
    }
}

@main
struct MyaowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var storage = MyaowStorageController()

    var body: some Scene {
        WindowGroup {
            if let container = storage.container {
                ContentView()
                    .modelContainer(container)
                    .onAppear { DesignPreviewData.prepare(context: container.mainContext) }
            } else {
                MyaowRecoveryView(message: storage.errorMessage ?? "No pudimos abrir tus datos.") {
                    storage.open()
                }
            }
        }
    }
}
