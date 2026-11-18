import ActivityKit
import AppIntents
import Foundation

// Gehört zur App und zur Widget-Erweiterung (Ordner Shared, in beiden Zielen).

/// Live-Aktivität des Back-Timers (Sperrbildschirm, Dynamic Island) ab „Backen beginnen“.
///
/// Inhalt getrennt: Titel und Dauer der Schritte stehen in den Attributen (fest, nur auf dem Gerät). Der
/// `ContentState` hat nur Zeitpunkte, so braucht der Weckdienst am Server (server/wecker.ts) nichts Lesbares. Sein
/// Push schickt genau `{"zeiten": [ms…], "aktuell": i}`; deshalb muss `ContentState` als JSON exakt dazu passen
/// (fehlt ein Pflichtfeld, verwirft iOS das Update still). Zeiten als Zahl in ms, kein `Date`: Der Decoder von
/// ActivityKit liest `Date` als Sekunden seit 2001.
struct BackAktivitaet: ActivityAttributes {
    /// „Sauerteig angesetzt“ (ms): erkennt den Lauf wieder.
    var start: Double
    /// Schritte ab „Backen beginnt“.
    var titel: [String]
    var dauer: [String]

    struct ContentState: Codable, Hashable, Sendable {
        /// ms je Schritt (ab „Backen beginnt“), ändert sich beim Abhaken.
        var zeiten: [Double]
        /// Laufender Schritt laut Absender.
        var aktuell: Int
        /// Erster noch nicht abgehakter Schritt. Nur die App kennt ihn, der Push lässt ihn weg (`nil`): dann gilt
        /// der laufende Schritt als offen.
        var weiter: Int? = nil

        /// Laufender Schritt jetzt: Kam der Push zum nächsten Schritt nicht an, schiebt ihn die Uhr weiter.
        func laufend(_ jetzt: Date) -> Int {
            let ms = jetzt.timeIntervalSince1970 * 1000
            let nachUhr = zeiten.lastIndex { $0 <= ms } ?? 0
            return min(max(aktuell, nachUhr, 0), max(zeiten.count - 1, 0))
        }

        /// Knopf „Erledigt“ für Schritt `i`: nicht beim letzten (auskühlen) und nicht, wenn schon abgehakt.
        func abhakbar(_ i: Int) -> Bool { i + 1 < zeiten.count && i >= (weiter ?? 0) }

        /// Index des nächsten Schritts nach `i`, `nil` = `i` ist der letzte (fertig gebacken, auskühlen).
        func naechster(nach i: Int) -> Int? { i + 1 < zeiten.count ? i + 1 : nil }

        func datum(_ i: Int) -> Date { Date(timeIntervalSince1970: zeiten[i] / 1000) }
    }

    func titel(_ i: Int) -> String { titel.indices.contains(i) ? titel[i] : "" }
    func dauer(_ i: Int) -> String { dauer.indices.contains(i) ? dauer[i] : "" }
}

/// Knopf „Erledigt“ in der Live-Aktivität: Der laufende Schritt ist jetzt erledigt, die folgenden rücken mit (wie
/// Abhaken in der App). Als `LiveActivityIntent` läuft `perform` im Prozess der App (iOS weckt sie dafür im
/// Hintergrund); die Arbeit macht `BackTimer.hakeAbAusAktivitaet`.
struct BackAbhakenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Back-Schritt erledigt"
    static let isDiscoverable = false

    /// Index in `ContentState.zeiten`.
    @Parameter(title: "Schritt")
    var schritt: Int

    /// Zeit des Schritts (ms), wie die Aktivität sie zeigte: Hat sich der Zeitplan inzwischen geändert, passiert nichts.
    @Parameter(title: "Zeit")
    var at: Double

    init() {}

    init(schritt: Int, at: Double) {
        self.schritt = schritt
        self.at = at
    }

    func perform() async throws -> some IntentResult {
        // Auf das Ende warten: sonst legt iOS die App schlafen, bevor gespeichert ist.
        await BackAbhaken.ausfuehren?(schritt, at)
        return .result()
    }
}

/// Setzt die App beim Start (AppDelegate). In der Widget-Erweiterung bleibt es leer.
enum BackAbhaken {
    nonisolated(unsafe) static var ausfuehren: (@Sendable (_ schritt: Int, _ at: Double) async -> Void)?
}
