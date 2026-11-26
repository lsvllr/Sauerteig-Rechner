import ActivityKit
import Foundation

/// Live-Aktivität des Back-Timers (Abschnitt 6.5): startet ab „Backen beginnen“ und folgt jeder Änderung des Laufs
/// (abhaken, beenden). Weiter geht es nur mit dem Abhaken, deshalb ohne Push vom Weckdienst. Die Reifezeit davor
/// zeigt sie nicht: iOS beendet Live-Aktivitäten nach höchstens 8 Stunden.
@MainActor
final class BackLive {
    static let shared = BackLive()

    /// Lauf (`start`) und Installation, für die schon eine Aktivität gestartet wurde. Hat man sie auf dem
    /// Sperrbildschirm weggewischt, startet sie für diesen Lauf nicht von selbst neu. Nach einem Update oder einer
    /// Neuinstallation (iOS beendet dabei alle Aktivitäten der App) aber schon.
    private let gestartetKey = "back-live-gestartet-fuer"
    private static let installation: String = {
        let datei = Bundle.main.executableURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path) }
        let datum = (datei?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") + "-" + String(Int(datum))
    }()
    private static func marke(_ l: BackLauf) -> String { "\(Int(l.start.rounded()))@\(installation)" }

    private var laufende: [Activity<BackAktivitaet>] {
        Activity<BackAktivitaet>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// Aktivität auf den Stand von `lauf` bringen: starten, aktualisieren oder beenden. In den Einstellungen
    /// ausgeschaltet: beenden (wieder eingeschaltet startet sie für den laufenden Lauf neu).
    func abgleichen(_ lauf: BackLauf?) async {
        guard Einstellungen.liveAktivitaet, let l = lauf, l.phase == .backen, l.schritte.count > BackLauf.beginn + 1 else {
            UserDefaults.standard.removeObject(forKey: gestartetKey)
            await beendeAlle()
            return
        }
        let attr = Self.attribute(l)
        let state = Self.stand(l)
        let i = state.laufend
        let content = ActivityContent(state: state, staleDate: Self.veraltet(state, i))
        let fertig = state.naechster(nach: i) == nil

        let aktiv = laufende
        if var a = aktiv.first(where: { $0.attributes.start == l.start }) ?? aktiv.first {
            // Titel geändert (anderes Rezept): Attribute sind fest, also neu starten. Geht nur im Vordergrund; klappt
            // es nicht, bleibt die alte mit neuen Zeiten stehen.
            if (a.attributes.titel != attr.titel || a.attributes.dauer != attr.dauer) && !fertig,
               let neu = starte(attr, content) {
                await a.end(nil, dismissalPolicy: .immediate)
                a = neu
            }
            for b in laufende where b.id != a.id { await b.end(nil, dismissalPolicy: .immediate) }
            UserDefaults.standard.set(Self.marke(l), forKey: gestartetKey)
            if fertig {
                await a.end(content, dismissalPolicy: .after(Self.abbauen(state)))
            } else if a.content.state != state {
                // Aktualisieren statt beenden und neu starten (auch bei neuer Startzeit): sonst verschwindet sie kurz.
                await a.update(content)
            }
            return
        }
        guard !fertig, UserDefaults.standard.string(forKey: gestartetKey) != Self.marke(l),
              ActivityAuthorizationInfo().areActivitiesEnabled, starte(attr, content) != nil else { return }
        UserDefaults.standard.set(Self.marke(l), forKey: gestartetKey)
    }

    /// Starten (nur im Vordergrund möglich).
    private func starte(_ attr: BackAktivitaet, _ content: ActivityContent<BackAktivitaet.ContentState>) -> Activity<BackAktivitaet>? {
        try? Activity.request(attributes: attr, content: content, pushType: nil)
    }

    private func beendeAlle() async {
        for a in laufende { await a.end(nil, dismissalPolicy: .immediate) }
    }

    static func attribute(_ l: BackLauf) -> BackAktivitaet {
        let s = l.schritte.dropFirst(BackLauf.beginn)
        return BackAktivitaet(start: l.start.rounded(), titel: s.map(\.titel), dauer: s.map(\.dauer))
    }

    /// Stand ab „Backen beginnt“: Zeiten, laufender Schritt (bleibt bis zum Abhaken) und erster offener Schritt.
    static func stand(_ l: BackLauf) -> BackAktivitaet.ContentState {
        let zeiten = l.schritte.dropFirst(BackLauf.beginn).map { $0.at.rounded() }
        return BackAktivitaet.ContentState(zeiten: zeiten, aktuell: max(l.laufend - BackLauf.beginn, 0),
                                           weiter: l.offenAb - BackLauf.beginn, dampf: l.dampfEnde != nil ? l.dampf : nil)
    }

    /// Kurz nach dem Ende des laufenden Schritts gilt die Anzeige als veraltet: iOS zeichnet sie neu, die Ansicht
    /// bittet dann ums Abhaken bzw. Starten. Beim Backen mit Dampf stattdessen gleich nach dem Ende dieser Stufe, damit
    /// der Countdown auf die Stufe ohne Dampf wechselt (iOS zeichnet nur einmal neu).
    private static func veraltet(_ s: BackAktivitaet.ContentState, _ i: Int) -> Date? {
        if let e = s.dampfEnde, e > Date() { return e.addingTimeInterval(1) }
        return s.naechster(nach: i).map { s.datum($0).addingTimeInterval(30) }
    }

    /// Nach dem letzten Schritt bleibt die Aktivität 2 Stunden stehen (Auskühlen).
    private static func abbauen(_ s: BackAktivitaet.ContentState) -> Date {
        (s.zeiten.last.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()).addingTimeInterval(2 * 3600)
    }
}

/// Adresse des eigenen Servers aus Config/Sauerteig.xcconfig (`WECKER_URL`, Name aus der Zeit des Weckdiensts für
/// die Live-Aktivität); leer = ohne Server.
enum Wecker {
    static let basis: URL? = {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "WeckerURL") as? String,
              s.hasPrefix("http"), let u = URL(string: s) else { return nil }
        return u
    }()
}

#if DEBUG
import SwiftUI

#Preview("Live-Aktivität") { BackAktivitaetGalerie() }
#endif
