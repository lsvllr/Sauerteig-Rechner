import SwiftUI
import UserNotifications

@main
struct SauerteigApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppState.shared
    @StateObject private var db = Datenbank.shared
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            HauptAnsicht()
                .environmentObject(app)
                .environmentObject(db)
                .tint(Brand().accent)
                .onOpenURL { app.open(link: $0.absoluteString) }
        }
        .onChange(of: phase) { _, p in
            guard p == .active else { return }
            Task {
                await BackTimer.shared.aufwachen()
                await Mitteilungen.planeFuettern(Datenbank.shared.fuetterung)
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Knopf „Erledigt“ in der Live-Aktivität: läuft hier im Prozess der App, auch wenn iOS sie dafür nur im
        // Hintergrund weckt.
        BackAbhaken.ausfuehren = { schritt, at in
            await BackTimer.shared.hakeAbAusAktivitaet(schritt, at: at)
        }
        return true
    }

    /// Auch bei offener App als Banner zeigen.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Tippen auf eine Mitteilung öffnet ihre Adresse (`userInfo["url"]`).
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let url = response.notification.request.content.userInfo["url"] as? String ?? "/backen"
        await MainActor.run { AppState.shared.open(link: url) }
    }
}
