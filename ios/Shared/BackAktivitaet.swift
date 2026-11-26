import ActivityKit
import AppIntents
import Foundation

// Gehört zur App und zur Widget-Erweiterung (Ordner Shared, in beiden Zielen).

/// Live-Aktivität des Back-Timers (Sperrbildschirm, Dynamic Island) ab „Backen beginnen“.
///
/// Inhalt getrennt: Titel und Dauer der Schritte stehen in den Attributen (fest, nur auf dem Gerät), der
/// `ContentState` hat nur Zeitpunkte und Indizes. Weiter geht es nur mit dem Abhaken in der App, die dann den Stand
/// schickt; die Uhr schaltet nichts weiter (deshalb auch kein Weckdienst mehr). Zeiten als Zahl in ms, kein `Date`:
/// Der Decoder von ActivityKit liest `Date` als Sekunden seit 2001.
struct BackAktivitaet: ActivityAttributes {
    /// „Autolyse ansetzen“ (während der Sauerteig reift) und „Ofen vorheizen“ (während der Stückgare) werden in der
    /// App gestartet und beenden den Schritt davor (siehe `BackLauf.mitStart`).
    static func mitStart(_ titel: String) -> Bool { titel.hasPrefix("Ofen") || titel.hasPrefix("Autolyse") }

    /// Backen in zwei Stufen: `min` Minuten bei `heiss` °C mit Dampf, danach bei `temp` °C ohne.
    struct Dampf: Codable, Hashable, Sendable {
        var min: Int
        var heiss: Int
        var temp: Int
    }

    /// Titel des Schritts, der in zwei Stufen läuft (`Dampf`).
    static let backen = "Backen"

    /// Kurzer Titel: „Ofen auf 220 °C vorheizen“ → „Ofen vorheizen“, „Autolyse ansetzen (vor Sauerteig-Reife)“ →
    /// „Autolyse ansetzen“.
    static func kurz(_ titel: String) -> String {
        if titel.hasPrefix("Ofen") { return "Ofen vorheizen" }
        return titel.range(of: " (").map { String(titel[..<$0.lowerBound]) } ?? titel
    }

    /// „Sauerteig angesetzt“ (ms): erkennt den Lauf wieder.
    var start: Double
    /// Schritte ab „Backen beginnt“.
    var titel: [String]
    var dauer: [String]

    struct ContentState: Codable, Hashable, Sendable {
        /// ms je Schritt (ab „Backen beginnt“), ändert sich beim Abhaken.
        var zeiten: [Double]
        /// Laufender Schritt (bis er in der App als fertig abgehakt ist, auch nach seiner geplanten Zeit).
        var aktuell: Int
        /// Erster noch nicht begonnener Schritt.
        var weiter: Int? = nil
        /// Nur solange gebacken wird: die Stufen (Dampf ab dem Beginn des laufenden Schritts).
        var dampf: Dampf? = nil

        /// Laufender Schritt, auf die Zeiten begrenzt.
        var laufend: Int { min(max(aktuell, 0), max(zeiten.count - 1, 0)) }

        /// Index des Schritts nach `i`, `nil` = `i` ist der letzte (fertig gebacken, auskühlen).
        func naechster(nach i: Int) -> Int? { i + 1 < zeiten.count ? i + 1 : nil }

        func datum(_ i: Int) -> Date { Date(timeIntervalSince1970: zeiten[i] / 1000) }

        /// Ende der Stufe mit Dampf (laufender Schritt ist das Backen).
        var dampfEnde: Date? {
            guard let d = dampf, zeiten.indices.contains(laufend) else { return nil }
            return datum(laufend).addingTimeInterval(Double(d.min) * 60)
        }

        /// Noch in der Stufe mit Dampf.
        func mitDampf(_ jetzt: Date) -> Bool { dampfEnde.map { jetzt < $0 } ?? false }

        /// Worauf der Countdown zählt: das Ende der Dampf-Stufe, sonst der Beginn des nächsten Schritts.
        func ziel(_ jetzt: Date) -> Date? {
            if let e = dampfEnde, jetzt < e { return e }
            return naechster(nach: laufend).map(datum)
        }
    }

    /// Titel für die Anzeige, kurz („Ofen vorheizen“ ohne Temperatur).
    func titel(_ i: Int) -> String { titel.indices.contains(i) ? Self.kurz(titel[i]) : "" }
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

#if DEBUG && !WIDGET_EXTENSION // Vorschau läuft in der App (Beispieldaten in Sauerteig/Vorschau)
import SwiftUI

#Preview("Live-Aktivität") { BackAktivitaetGalerie() }
#endif
