import Foundation
import UserNotifications

/// Lokale Mitteilungen (Abschnitt 6.3 und 7): Das Gerät plant sie selbst, sie kommen auch bei geschlossener App,
/// ein Server ist dafür nicht nötig.
@MainActor
enum Mitteilungen {
    private static let backPraefix = "backtimer."
    private static let fuetternPraefix = "fuettern."
    /// Uhrzeit der Füttern-Erinnerung.
    static let fuetternStunde = 8

    /// Erlaubnis erfragen (bei „Sauerteig angesetzt“ und beim ersten Füttern). Rückgabe: erlaubt.
    static func erlaubnis() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private static func entferne(_ praefix: String) async {
        let c = UNUserNotificationCenter.current()
        let ids = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(praefix) }
        c.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Back-Timer: alle alten entfernen und aus `meldungen` neu planen. iOS hält höchstens 64 ausstehende
    /// Mitteilungen je App; ältere fielen still weg, deshalb höchstens 60 (Rest für Füttern).
    static func planeBackTimer(_ lauf: BackLauf?) async {
        await entferne(backPraefix)
        guard let l = lauf else { return }
        let c = UNUserNotificationCenter.current()
        let jetzt = Date().timeIntervalSince1970 * 1000
        for m in l.meldungen(jetzt: jetzt).prefix(60) {
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

    /// Füttern: am Fälligkeitstag morgens, und falls dann nichts passiert, an den beiden Tagen danach noch einmal.
    /// Ist der Tag schon vorbei, ab morgen früh.
    static func planeFuettern(_ f: Fuetterung) async {
        await entferne(fuetternPraefix)
        guard let faellig = f.faellig else { return }
        let cal = Calendar.current
        let jetzt = Date()
        var tag = cal.startOfDay(for: faellig)
        if let erster = cal.date(bySettingHour: fuetternStunde, minute: 0, second: 0, of: tag), erster <= jetzt {
            tag = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: jetzt)!)
        }
        let c = UNUserNotificationCenter.current()
        for n in 0..<3 {
            guard let d = cal.date(byAdding: .day, value: n, to: tag) else { continue }
            var k = cal.dateComponents([.year, .month, .day], from: d)
            k.hour = fuetternStunde
            let content = UNMutableNotificationContent()
            let ueber = cal.dateComponents([.day], from: cal.startOfDay(for: faellig), to: d).day ?? 0
            content.title = "Sauerteig füttern"
            content.body = ueber <= 0 ? "Heute ist Füttern dran." : ueber == 1 ? "Seit gestern fällig." : "Seit \(ueber) Tagen fällig."
            content.sound = .default
            content.threadIdentifier = "fuettern"
            content.userInfo = ["url": "/fuettern"]
            let trigger = UNCalendarNotificationTrigger(dateMatching: k, repeats: false)
            try? await c.add(UNNotificationRequest(identifier: fuetternPraefix + "\(n)", content: content, trigger: trigger))
        }
    }
}
