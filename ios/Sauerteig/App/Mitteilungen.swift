import Foundation
import UserNotifications

/// Lokale Mitteilungen (Abschnitt 6.3 und 7): Das Gerät plant sie selbst, sie kommen auch bei geschlossener App,
/// ein Server ist dafür nicht nötig.
@MainActor
enum Mitteilungen {
    private static let backPraefix = "backtimer."
    private static let fuetternPraefix = "fuettern."
    /// Erlaubnis erfragen (bei „Sauerteig angesetzt“ und beim ersten Füttern). Rückgabe: erlaubt.
    static func erlaubnis() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Stand der Erlaubnis in iOS (für die Einstellungen).
    static func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private static func entferne(_ praefix: String) async {
        let c = UNUserNotificationCenter.current()
        let ids = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(praefix) }
        c.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Back-Timer: alle alten entfernen und aus `meldungen` neu planen. iOS hält höchstens 64 ausstehende
    /// Mitteilungen je App; ältere fielen still weg, deshalb höchstens `backHoechstens` (Rest für Füttern). In den Einstellungen
    /// ausgeschaltet: keine.
    static func planeBackTimer(_ lauf: BackLauf?) async {
        await entferne(backPraefix)
        guard Einstellungen.backMitteilungen, let l = lauf else { return }
        let c = UNUserNotificationCenter.current()
        let jetzt = Date().timeIntervalSince1970 * 1000
        for m in l.meldungen(jetzt: jetzt, vorlauf: Einstellungen.vorlauf).prefix(backHoechstens) {
            let content = UNMutableNotificationContent()
            content.title = m.titel
            content.body = m.text
            content.sound = .default
            content.threadIdentifier = "backtimer"
            content.userInfo = ["url": "/backen"]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, (m.at - jetzt) / 1000), repeats: false)
            try? await c.add(UNNotificationRequest(identifier: backPraefix + m.id, content: content, trigger: trigger))
        }
    }

    /// Füttern: am Fälligkeitstag zur eingestellten Uhrzeit, dann ab `Fuetterung.dringendAb` Tagen drüber (Glas rot)
    /// jeden Tag, bis gefüttert ist. Vorbeigegangene Termine fallen weg. Vorausgeplant sind höchstens
    /// `fuetternTage` dringende Tage; die App plant bei jedem Öffnen neu und schiebt das Fenster weiter.
    /// In den Einstellungen ausgeschaltet: keine.
    static func planeFuettern(_ f: Fuetterung) async {
        await entferne(fuetternPraefix)
        guard Einstellungen.fuetternMitteilungen, let faellig = f.faellig else { return }
        let cal = Calendar.current
        let jetzt = Date()
        let minute = Einstellungen.fuetternMinute
        let tag0 = cal.startOfDay(for: faellig)
        let c = UNUserNotificationCenter.current()
        let tage = [0] + Array(Fuetterung.dringendAb..<Fuetterung.dringendAb + fuetternTage)
        for ueber in tage {
            guard let d = cal.date(byAdding: .day, value: ueber, to: tag0),
                  let um = cal.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: d),
                  um > jetzt else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Sauerteig füttern"
            content.body = ueber == 0 ? "Heute ist Füttern dran." : "Seit \(ueber) Tagen überfällig – bitte heute füttern."
            content.sound = .default
            content.threadIdentifier = "fuettern"
            content.userInfo = ["url": "/fuettern"]
            let k = cal.dateComponents([.year, .month, .day, .hour, .minute], from: um)
            let trigger = UNCalendarNotificationTrigger(dateMatching: k, repeats: false)
            try? await c.add(UNNotificationRequest(identifier: fuetternPraefix + "\(ueber)", content: content, trigger: trigger))
        }
    }

    /// Dringende Füttern-Tage im Voraus (plus der Fälligkeitstag). Zusammen mit `backHoechstens` unter den 64
    /// ausstehenden Mitteilungen, die iOS je App hält.
    private static let fuetternTage = 10
    private static let backHoechstens = 52
}

#if DEBUG
import SwiftUI

/// Was die App als Mitteilung planen würde (BackLauf.meldungen), je Zustand des Timers.
private struct GeplanteMitteilungen: View {
    let timer: Vorschau.Timer

    var body: some View {
        let jetzt = Date().timeIntervalSince1970 * 1000
        let m = Vorschau.lauf(timer)?.meldungen(jetzt: jetzt) ?? []
        List {
            if m.isEmpty { Text("Keine geplanten Mitteilungen").foregroundStyle(.secondary) }
            ForEach(m, id: \.id) { x in
                VStack(alignment: .leading, spacing: 3) {
                    Text(BackLauf.uhrzeit(x.at, jetzt: jetzt)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(x.titel).font(.headline)
                    Text(x.text).font(.subheadline)
                }
            }
        }
    }
}

#Preview("Mitteilungen · reift") { GeplanteMitteilungen(timer: .reift) }
#Preview("Mitteilungen · Backen läuft") { GeplanteMitteilungen(timer: .backen) }
#Preview("Mitteilungen · fertig") { GeplanteMitteilungen(timer: .fertig) }
#endif
