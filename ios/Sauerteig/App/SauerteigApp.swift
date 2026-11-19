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
                .environmentObject(BackTimer.shared)
                .environmentObject(Abgleich.shared)
                .environmentObject(Sicherung.shared)
                .tint(Brand().accent)
                .onOpenURL { app.open(link: $0.absoluteString) }
        }
        .onChange(of: phase) { _, p in
            Abgleich.shared.vordergrund(p == .active)
            if p == .background { Sicherung.shared.imHintergrund() }
            guard p == .active else { return }
            Task {
                await BackTimer.shared.aufwachen()
                await Mitteilungen.planeFuettern(Datenbank.shared.fuetterung)
                await Sicherung.shared.abgleichen()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // Jede gespeicherte Änderung: sichern (iCloud); eigene an die anderen Geräte, fremde (Abgleich, Sicherung)
        // in Timer, Mitteilungen und Live-Aktivität übernehmen.
        Datenbank.shared.beiAenderung = { fremd in
            Task { @MainActor in
                Sicherung.shared.vormerken()
                if fremd {
                    await BackTimer.shared.aufwachen()
                    await Mitteilungen.planeFuettern(Datenbank.shared.fuetterung)
                } else {
                    Abgleich.shared.nachEigenerAenderung()
                }
            }
        }
        // Knopf „Erledigt“ in der Live-Aktivität: läuft hier im Prozess der App, auch wenn iOS sie dafür nur im
        // Hintergrund weckt.
        // Stiller Push „es gibt Neues“ vom Server (Abgleich): Token anfordern, braucht keine Erlaubnis.
        if Abgleich.shared.konto != nil { application.registerForRemoteNotifications() }
        BackAbhaken.ausfuehren = { schritt, at in
            await BackTimer.shared.hakeAbAusAktivitaet(schritt, at: at)
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let endpoint = "apns-sandbox:" + hex // Debug-Builds bekommen Tokens für den Sandbox-Server von APNs
        #else
        let endpoint = "apns:" + hex
        #endif
        Task { await Abgleich.shared.meldePush(endpoint) }
    }

    /// Stiller Push: ein anderes Gerät hat etwas geändert. Holen, dann Mitteilungen und Live-Aktivität auf den
    /// Stand bringen, bevor iOS die App wieder schlafen legt (rund 30 s).
    /// Mit Completion-Handler statt `async`: Die async-Variante reicht das nicht-Sendable `userInfo` über die
    /// Actor-Grenze (Swift-6-Warnung); gebraucht wird es ohnehin nicht.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler fertig: @escaping (UIBackgroundFetchResult) -> Void) {
        Task { fertig(await Self.holeFremdeAenderungen()) }
    }

    private static func holeFremdeAenderungen() async -> UIBackgroundFetchResult {
        let vorher = Datenbank.shared.tabellen
        await Abgleich.shared.gleicheAb()
        guard Datenbank.shared.tabellen != vorher else { return .noData }
        await BackTimer.shared.aufwachen()
        await Mitteilungen.planeFuettern(Datenbank.shared.fuetterung)
        return .newData
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

#if DEBUG
#Preview("App") { HauptAnsicht().vorschau(timer: .backen, rezepte: true) }
#endif
