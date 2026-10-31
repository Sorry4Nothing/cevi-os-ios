import Foundation
import Observation
import UIKit
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging
#endif

/// Push via Firebase Cloud Messaging (APNs underneath). Needs `GoogleService-Info.plist`, which is not in the repo;
/// without it push stays off and the app works as before. Never logs tokens.
@MainActor @Observable
final class PushManager: NSObject {
    static let shared = PushManager()

    /// The explanation sheet is shown when the system has not asked yet.
    var needsExplanation = false
    private weak var appState: AppState?
    private var fcmToken: String?
    private var registeredToken: String?

    var isConfigured: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
    }

    /// Called once at launch.
    func configure() {
        #if canImport(FirebaseMessaging)
        guard isConfigured else { return }
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
        #endif
        UNUserNotificationCenter.current().delegate = self
    }

    func attach(_ appState: AppState) {
        self.appState = appState
        appState.onSignOut.append { [weak self] in await self?.clearOnSignOut() }
    }

    /// After sign-in: ask for permission only with an explanation first. Already allowed: register right away.
    func prepare() async {
        guard isConfigured else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: needsExplanation = true
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
            await registerToken()
        default: break
        }
    }

    /// The person agreed on the explanation sheet: now the system asks.
    func requestPermission() async {
        needsExplanation = false
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
            await registerToken()
        }
    }

    func apnsTokenReceived(_ data: Data) {
        #if canImport(FirebaseMessaging)
        guard isConfigured else { return }
        Messaging.messaging().apnsToken = data
        #endif
    }

    /// Sends the current token to the server if it is new for this session.
    func registerToken() async {
        #if canImport(FirebaseMessaging)
        guard isConfigured, appState?.profile != nil else { return }
        if fcmToken == nil { fcmToken = try? await Messaging.messaging().token() }
        guard let token = fcmToken, token != registeredToken, PushToken.isValid(token) else { return }
        do {
            try await appState?.client?.registerPushToken(token)
            registeredToken = token
        } catch {
            // Try again next time (next start or token refresh).
        }
        #endif
    }

    /// Sign-out: forget the token locally. The server deletes it with the session.
    private func clearOnSignOut() async {
        registeredToken = nil
        fcmToken = nil
        #if canImport(FirebaseMessaging)
        guard isConfigured else { return }
        try? await Messaging.messaging().deleteToken()
        #endif
        UIApplication.shared.unregisterForRemoteNotifications()
    }
}

#if canImport(FirebaseMessaging)
extension PushManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in
            self.fcmToken = fcmToken
            await self.registerToken()
        }
    }
}
#endif

extension PushManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let target = PushTarget.from(userInfo: notification.request.content.userInfo)
        let hidden = await MainActor.run { target?.isHidden(openChatId: appState?.openChatId) ?? false }
        return hidden ? [] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let target = PushTarget.from(userInfo: response.notification.request.content.userInfo)
        await MainActor.run { appState?.pendingTarget = target }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { PushManager.shared.configure() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.apnsTokenReceived(deviceToken) }
    }
}
