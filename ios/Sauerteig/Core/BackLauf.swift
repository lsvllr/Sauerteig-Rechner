import Foundation

// Back-Timer (Regeln wie src/gemeinsam/timer.ts und Haushalt Core/Sauerteig.swift). Zeiten als Zahl in ms, nie als
// `Date` im Codable-Modell.

struct TimerSchritt: Codable, Hashable, Sendable {
    var at: Double // ms seit 1970
    var titel: String
    var dauer: String
}

struct BackLauf: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Sendable { case reifen, backen }

    var phase: Phase
    /// Sauerteig angesetzt (ms)
    var start: Double
    /// reif zwischen [von, bis] (ms)
    var reife: [Double]
    /// Vorwarnung in Minuten
    var vorlauf: Int
    /// Schritt 0 = ansetzen, Schritt 1 = „Backen beginnt“ (`beginn`)
    var schritte: [TimerSchritt]
    /// erster noch nicht abgehakter Schritt
    var weiter: Int?

    static let beginn = 1
    static let vorlaufWahl = [0, 5, 10, 15, 20, 30, 45, 60]
    static let min = 60_000.0
    /// So lange nach dem letzten Schritt räumt sich der Lauf von selbst ab.
    static let aufraeumenNach = 3 * 3600 * 1000.0

    static func neu(_ schritte: [Schritt], start: Double, vorlauf: Int, reife: (Int, Int)) -> BackLauf {
        BackLauf(phase: .reifen, start: start, reife: [start + Double(reife.0) * min, start + Double(reife.1) * min],
                 vorlauf: vorlauf,
                 schritte: schritte.map { TimerSchritt(at: start + Double(jsRound(Double($0.t) / 5) * 5) * min, titel: $0.titel, dauer: $0.dauer) },
                 weiter: nil)
    }

    /// Index des nächsten nicht abgehakten Schritts.
    var offenAb: Int { weiter ?? (phase == .reifen ? Self.beginn : Self.beginn + 1) }

    /// Index des nächsten noch nicht fälligen Schritts, -1 wenn alle durch sind.
    func naechster(_ jetzt: Double) -> Int { schritte.firstIndex { $0.at > jetzt } ?? -1 }

    /// Lange nach dem letzten Schritt: weg damit.
    func abgelaufen(_ jetzt: Double) -> Bool { (schritte.last?.at ?? start) + Self.aufraeumenNach < jetzt }

    /// Schritt `i` um `am` erledigt (Standard jetzt; früher, wenn das Weiterklicken vergessen wurde): Er bekommt diese
    /// Uhrzeit, alle späteren verschieben sich um denselben Betrag. Danach Phase „backen“. Abhaken geht nur für den
    /// nächsten offenen oder einen schon erledigten Schritt (der wird aktualisiert). `ueberspringen`: auch wenn
    /// frühere noch offen sind (Knopf in der Live-Aktivität, die nur den laufenden Schritt zeigt).
    func hakeAb(_ i: Int, am: Double, ueberspringen: Bool = false) -> BackLauf {
        guard i >= Self.beginn, i <= offenAb || ueberspringen, i < schritte.count else { return self }
        var l = self
        let d = am - schritte[i].at
        l.phase = .backen
        l.weiter = i + 1
        for j in i..<l.schritte.count { l.schritte[j].at += d }
        return l
    }

    /// Zu meldende Zeitpunkte (lokale Mitteilungen), nur künftige. `vorlauf`: Vorwarnung dieses Geräts
    /// (Einstellungen), Standard der Wert im Lauf.
    func meldungen(jetzt: Double, vorlauf: Int? = nil) -> [(id: String, at: Double, titel: String, text: String)] {
        var out: [(String, Double, String, String)] = []
        let vorlauf = vorlauf ?? self.vorlauf
        let v = Double(vorlauf) * Self.min
        if phase == .reifen {
            guard schritte.count > Self.beginn else { return [] }
            let b = schritte[Self.beginn]
            out.append(("\(Self.beginn):jetzt", b.at, "Sauerteig prüfen", "Wenn er reif ist: „Backen beginnen“ tippen. Als Erstes: \(b.titel)."))
            if vorlauf > 0 {
                out.append(("\(Self.beginn):bald", b.at - v, "In \(vorlauf) Min beginnt das Backen", "Um ca. \(Self.uhrzeit(b.at, jetzt: jetzt)): \(b.titel)."))
            }
        } else {
            for (i, s) in schritte.enumerated() where i >= offenAb {
                let danach = i + 1 < schritte.count ? " Danach um \(Self.uhrzeit(schritte[i + 1].at, jetzt: jetzt)): \(schritte[i + 1].titel)." : ""
                out.append(("\(i):jetzt", s.at, "Jetzt: \(s.titel)", "\(s.dauer).\(danach)"))
                if vorlauf > 0 {
                    out.append(("\(i):bald", s.at - v, "In \(vorlauf) Min: \(s.titel)", "Um \(Self.uhrzeit(s.at, jetzt: jetzt)) (\(s.dauer))."))
                }
            }
        }
        return out.filter { $0.1 > jetzt }
    }

    private static let fHeute: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let fTag: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE HH:mm"
        return f
    }()

    /// „14:35“, an einem anderen Tag „Mi 14:35“.
    static func uhrzeit(_ ms: Double, jetzt: Double) -> String {
        let d = Date(timeIntervalSince1970: ms / 1000)
        let heute = Calendar.current.isDate(d, inSameDayAs: Date(timeIntervalSince1970: jetzt / 1000))
        return (heute ? fHeute : fTag).string(from: d)
    }

    /// „1:23 h“, unter einer Stunde „12:05“ (Min:Sek).
    static func restzeit(_ ms: Double) -> String {
        let s = max(0, Int((ms / 1000).rounded(.up)))
        func zwei(_ x: Int) -> String { x < 10 ? "0\(x)" : "\(x)" }
        if s >= 3600 { return "\(s / 3600):" + zwei((s % 3600) / 60) + " h" }
        return "\(s / 60):" + zwei(s % 60)
    }
}

// MARK: - Tabelle `backlauf`

/// Je „Sauerteig angesetzt“ eine neue Zeile (neue uid); der laufende Lauf ist die jüngste nicht gelöschte. Beenden =
/// Löschmarke. Der Zeitplan steht als **ein** Feld (`schritte`, JSON), sonst mischte der Abgleich pro Feld Schritte
/// aus zwei Fassungen.
extension BackLauf {
    static let tabelle = "backlauf"

    var felder: [String: Wert] {
        [
            "phase": .text(phase.rawValue), "start": .zahl(start.rounded()), "reife": .json(reife.map { $0.rounded() }),
            "vorlauf": .zahl(Double(vorlauf)), "weiter": weiter.map { .zahl(Double($0)) } ?? .null,
            "schritte": .json(schritte.map { TimerSchritt(at: $0.at.rounded(), titel: $0.titel, dauer: $0.dauer) }),
        ]
    }

    init?(_ z: Zeile) {
        guard let p = z["phase"]?.text.flatMap(Phase.init(rawValue:)), let start = z["start"]?.zahl,
              let schritte = z["schritte"]?.json([TimerSchritt].self), !schritte.isEmpty else { return nil }
        let reife = z["reife"]?.json([Double].self) ?? [start, start]
        let v = z["vorlauf"]?.int ?? 10
        self.init(phase: p, start: start, reife: reife.count == 2 ? reife : [start, start],
                  vorlauf: Self.vorlaufWahl.contains(v) ? v : 10, schritte: schritte,
                  weiter: z["weiter"]?.int.map { Swift.min(Swift.max($0, Self.beginn), schritte.count) })
    }
}

#if DEBUG && canImport(UIKit)
import SwiftUI

#Preview("Timer · reift") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .reift) }
#Preview("Timer · Backen läuft") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .backen) }
#Preview("Seite · Backen läuft") { HauptAnsicht().vorschau(timer: .backen) }
#endif
