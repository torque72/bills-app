import Foundation
import UserNotifications
import UIKit

@MainActor
final class PushManager: ObservableObject {
    enum AuthorizationStatus: Equatable {
        case unknown
        case requesting
        case granted
        case denied
        case failed(String)

        var description: String {
            switch self {
            case .unknown:
                return "Not requested"
            case .requesting:
                return "Requesting permission…"
            case .granted:
                return "Enabled"
            case .denied:
                return "Denied"
            case let .failed(reason):
                return "Failed: \(reason)"
            }
        }
    }

    @Published var status: AuthorizationStatus = .unknown
    @Published var token: String?
    @Published var lastNotificationSummary: PushNotificationSummary?

    private let api: BillsAPI

    init(api: BillsAPI) {
        self.api = api
    }

    func ensureAuthorizationChecked() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        updateStatus(for: settings.authorizationStatus)
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func requestAuthorization() async {
        status = .requesting
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                status = .granted
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                status = .denied
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func registerDeviceToken(_ token: String) async {
        guard self.token != token else { return }
        self.token = token
        do {
            try await api.registerPushToken(token: token, platform: "ios")
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func unregister() async {
        guard let token else { return }
        do {
            try await api.unregisterPushToken(token: token)
            self.token = nil
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func triggerUpcomingPush(monthKey: String?) async {
        do {
            let summary = try await api.sendUpcomingPush(monthKey: monthKey)
            lastNotificationSummary = summary
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func markRegistrationFailed(reason: String) {
        status = .failed(reason)
    }

    private func updateStatus(for authorization: UNAuthorizationStatus) {
        switch authorization {
        case .authorized, .provisional:
            status = .granted
        case .denied:
            status = .denied
        case .notDetermined:
            status = .unknown
        case .ephemeral:
            status = .granted
        @unknown default:
            status = .unknown
        }
    }
}
