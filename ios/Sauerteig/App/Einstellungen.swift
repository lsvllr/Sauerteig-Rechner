import Foundation

/// Einstellungen dieses Geräts (UserDefaults, nicht in der Datenbank): Mitteilungen und Live-Aktivität gelten je
/// Gerät, auch wenn später Rezepte und Timer abgeglichen werden. Die Ansicht liest sie mit `@AppStorage` und
/// denselben Schlüsseln und Standardwerten.
enum Einstellungen {
    static let backMitteilungenKey = "einstellung-back-mitteilungen"
    static let fuetternMitteilungenKey = "einstellung-fuettern-mitteilungen"
    /// Uhrzeit der Füttern-Erinnerung in Minuten nach Mitternacht.
    static let fuetternMinuteKey = "einstellung-fuettern-minute"
    static let liveAktivitaetKey = "einstellung-live-aktivitaet"
    /// Vorwarnung vor jedem Back-Schritt in Minuten (0 = keine). Alter Schlüssel, damit die letzte Wahl bleibt.
    static let vorlaufKey = "sauerteig-vorlauf"

    static let fuetternMinuteStandard = 8 * 60
    static let vorlaufStandard = 10

    private static func an(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

    static var backMitteilungen: Bool { an(backMitteilungenKey) }
    static var fuetternMitteilungen: Bool { an(fuetternMitteilungenKey) }
    static var liveAktivitaet: Bool { an(liveAktivitaetKey) }

    static var fuetternMinute: Int {
        let m = UserDefaults.standard.object(forKey: fuetternMinuteKey) as? Int ?? fuetternMinuteStandard
        return (0..<24 * 60).contains(m) ? m : fuetternMinuteStandard
    }

    static var vorlauf: Int {
        let v = UserDefaults.standard.object(forKey: vorlaufKey) as? Int ?? vorlaufStandard
        return BackLauf.vorlaufWahl.contains(v) ? v : vorlaufStandard
    }

    /// „8:00“, „18:30“.
    static func uhrzeit(_ minute: Int) -> String { String(format: "%d:%02d", minute / 60, minute % 60) }
}
