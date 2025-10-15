import SwiftUI
import UserNotifications

@main
struct BillsAgentApp: App {
    @UIApplicationDelegateAdaptor(BillsAppDelegate.self) var appDelegate
    @StateObject private var pushManager: PushManager
    @StateObject private var billsViewModel: BillsViewModel

    init() {
        let baseURL = URL(string: ProcessInfo.processInfo.environment["BILLS_API_BASE_URL"] ?? "http://localhost:4000")!
        let api = BillsAPI(baseURL: baseURL)
        let pushManager = PushManager(api: api)
        _pushManager = StateObject(wrappedValue: pushManager)
        _billsViewModel = StateObject(wrappedValue: BillsViewModel(api: api))
        BillsAppDelegate.sharedPushManager = pushManager
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                BillsDashboardView()
                    .environmentObject(billsViewModel)
                    .environmentObject(pushManager)
            }
            .task {
                await billsViewModel.loadBillsIfNeeded()
            }
        }
    }
}

final class BillsAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var sharedPushManager: PushManager?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { [token] in
            await BillsAppDelegate.sharedPushManager?.registerDeviceToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task {
            await BillsAppDelegate.sharedPushManager?.markRegistrationFailed(reason: error.localizedDescription)
        }
    }
}
