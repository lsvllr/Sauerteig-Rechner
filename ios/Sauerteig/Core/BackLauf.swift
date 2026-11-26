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
    /// Stufen des Schritts „Backen“: erst mit Dampf, dann ohne. nil = ohne Stufen (Lauf aus der Web-App, ältere).
    var dampf: BackAktivitaet.Dampf? = nil

    static let beginn = 1
    static let vorlaufWahl = [0, 5, 10, 15, 20, 30, 45, 60]
    static let min = 60_000.0
    /// So lange nach dem letzten Schritt räumt sich der Lauf von selbst ab.
    static let aufraeumenNach = 3 * 3600 * 1000.0

    static func neu(_ schritte: [Schritt], start: Double, vorlauf: Int, reife: (Int, Int),
                    dampf: BackAktivitaet.Dampf? = nil) -> BackLauf {
        BackLauf(phase: .reifen, start: start, reife: [start + Double(reife.0) * min, start + Double(reife.1) * min],
                 vorlauf: vorlauf,
                 schritte: schritte.map { TimerSchritt(at: start + Double(jsRound(Double($0.t) / 5) * 5) * min, titel: $0.titel, dauer: $0.dauer) },
                 weiter: nil, dampf: dampf)
    }

    /// Stufen fürs Backen aus dem Rezept: Anbacken mit Dampf, danach heruntergeschaltet ohne.
    static func dampf(_ r: Berechnung) -> BackAktivitaet.Dampf {
        BackAktivitaet.Dampf(min: r.dampfMin, heiss: r.anbackTemp, temp: r.ofenTemp)
    }

    /// Ende der Stufe mit Dampf (ms), solange gebacken wird (laufender Schritt „Backen“); sonst nil.
    var dampfEnde: Double? {
        guard phase == .backen, let d = dampf, schritte.indices.contains(laufend),
              schritte[laufend].titel == BackAktivitaet.backen else { return nil }
        return schritte[laufend].at + Double(d.min) * Self.min
    }

    /// Index des ersten noch nicht begonnenen Schritts. `at` eines Schritts ist sein Beginn (geplant, ab dem Beginn
    /// tatsächlich); begonnen ist er, sobald der vorige als fertig abgehakt ist.
    var offenAb: Int { weiter ?? (phase == .reifen ? Self.beginn : Self.beginn + 1) }

    /// Wird selbst gestartet, sobald er fällig ist, statt mit dem Ende des vorigen zu beginnen: „Autolyse ansetzen“
    /// während der Sauerteig reift, „Ofen vorheizen“ während der Stückgare. Der vorige (dessen Zeit diesen Schritt
    /// schon enthält) hat kein eigenes „Erledigt“: Er endet mit dem Start, das „Erledigt“ dieses Schritts beendet
    /// beides. Die Autolyse zu starten beginnt zugleich das Backen.
    func mitStart(_ i: Int) -> Bool { schritte.indices.contains(i) && BackAktivitaet.mitStart(schritte[i].titel) }

    /// Laufender Schritt: der zuletzt begonnene. Bleibt es, bis er abgehakt (oder der nächste gestartet) ist, auch
    /// wenn seine geplante Zeit um ist. Beim Reifen 0 (Sauerteig).
    var laufend: Int { Swift.max(Swift.min(offenAb, schritte.count) - 1, 0) }

    /// Schritt, der beginnt, wenn `i` fertig ist; nil = `i` ist der letzte.
    func folgt(auf i: Int) -> Int? { i + 1 < schritte.count ? i + 1 : nil }

    /// Schritt `i` hat ein „Erledigt“: nicht der letzte und nicht der vor einem Schritt mit eigenem Start.
    func abhakbar(_ i: Int) -> Bool { i >= Self.beginn && i + 1 < schritte.count && !mitStart(i + 1) }

    /// Schritt `i` lässt sich jetzt starten (oder seine Startzeit ändern): Er hat einen eigenen Start, und der
    /// Schritt davor (beim Reifen der Sauerteig) oder er selbst läuft.
    func startbar(_ i: Int) -> Bool {
        i >= Self.beginn && mitStart(i) && (laufend == i - 1 || phase == .backen && laufend == i)
    }

    /// Fertig gebacken: der letzte Schritt (Auskühlen) hat begonnen.
    var fertig: Bool { phase == .backen && offenAb >= schritte.count }

    /// Index des nächsten noch nicht fälligen Schritts, -1 wenn alle durch sind.
    func naechster(_ jetzt: Double) -> Int { schritte.firstIndex { $0.at > jetzt } ?? -1 }

    /// Lange nach dem letzten Schritt: weg damit. Noch nicht fertig abgehakt: erst nach einem halben Tag, der Timer
    /// wartet ja aufs Abhaken und kann weit hinter dem Plan sein.
    func abgelaufen(_ jetzt: Double) -> Bool {
        (schritte.last?.at ?? start) + (fertig ? Self.aufraeumenNach : 4 * Self.aufraeumenNach) < jetzt
    }

    /// Schritt `i` ist um `am` fertig (Standard jetzt; früher, wenn das Abhaken vergessen wurde): Der folgende Schritt
    /// beginnt dann. Geht für den laufenden oder einen schon fertigen Schritt (dann neu ab da).
    func erledige(_ i: Int, am: Double) -> BackLauf {
        guard phase == .backen, abhakbar(i), i <= laufend else { return self }
        return hakeAb(i + 1, am: am)
    }

    /// Schritt `i` mit eigenem Start beginnt um `am` (Ofen an); der vorige endet damit.
    func starte(_ i: Int, am: Double) -> BackLauf {
        guard startbar(i) else { return self }
        return hakeAb(i, am: am)
    }

    /// Schritt `i` beginnt um `am`: Er bekommt diese Uhrzeit, alle späteren verschieben sich um denselben Betrag.
    /// Danach Phase „backen“. Geht nur für den nächsten offenen oder einen schon begonnenen Schritt (der wird
    /// aktualisiert). `ueberspringen`: auch wenn frühere noch offen sind (Knopf in der Live-Aktivität). Gleiche Regel
    /// wie `hakeAbAm` in src/gemeinsam/timer.ts, deshalb bleibt der Zeitplan mit der Web-App verträglich.
    func hakeAb(_ i: Int, am: Double, ueberspringen: Bool = false) -> BackLauf {
        guard i >= Self.beginn, i <= offenAb || ueberspringen, i < schritte.count else { return self }
        var l = self
        let d = am - schritte[i].at
        l.phase = .backen
        l.weiter = i + 1
        for j in i..<l.schritte.count { l.schritte[j].at += d }
        return l
    }

    /// Lauf aus der Zeit, als ein abgehakter Schritt die Uhrzeit bekam, zu der er fertig war (bis November 2026; nur
    /// „Backen beginnen“ setzte einen Beginn). Jetzt ist `at` der Beginn eines Schritts, also das Ende des vorigen:
    /// Jede abgehakte Zeit wandert einen Schritt weiter, die nicht abgehakten rücken mit. Wann der erste Schritt nach
    /// „Backen beginnen“ endete, ist nicht bekannt; geschätzt mit der geplanten Dauer des kürzeren der beiden
    /// Schritte (Hauptteig 10 Min), vom Beginn bzw. vom Ende aus.
    func ausAltemModell() -> BackLauf {
        let b = Self.beginn
        let k = Swift.min(offenAb, schritte.count) - 1 // zuletzt abgehakt
        guard phase == .backen, k > b else { return self }
        var l = self
        for i in (b + 1)...k where i + 1 < schritte.count {
            l = l.hakeAb(i + 1, am: schritte[i].at)
        }
        if b + 2 < l.schritte.count {
            let anfang = l.schritte[b].at, ende = l.schritte[b + 2].at
            let d0 = Double(Rechner.dauerMinuten(schritte[b].dauer)) * Self.min
            let d1 = Double(Rechner.dauerMinuten(schritte[b + 1].dauer)) * Self.min
            let geschaetzt = d0 <= d1 ? anfang + d0 : ende - d1
            l.schritte[b + 1].at = Swift.min(Swift.max(geschaetzt, anfang), ende).rounded()
        }
        return l
    }

    /// Ansetzzeit nachträglich auf `am` setzen (Standard jetzt): Reife und alle Schritte rücken um denselben Betrag
    /// mit. Wie beim Aktualisieren eines früheren Schritts sind die späteren danach wieder offen (Phase „reifen“).
    func setzeStart(am: Double) -> BackLauf {
        var l = self
        l.phase = .reifen
        l.weiter = nil
        let d = am - start
        l.start += d
        l.reife = reife.map { $0 + d }
        for j in l.schritte.indices { l.schritte[j].at += d }
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
            if mitStart(Self.beginn) {
                out.append(("\(Self.beginn):jetzt", b.at, "Jetzt: \(b.titel)", "\(b.dauer), der Sauerteig reift dabei weiter. In der App „Starten“ tippen."))
            } else {
                out.append(("\(Self.beginn):jetzt", b.at, "Sauerteig prüfen", "Wenn er reif ist: „Backen beginnen“ tippen. Als Erstes: \(b.titel)."))
            }
            if vorlauf > 0 {
                out.append(("\(Self.beginn):bald", b.at - v, "In \(vorlauf) Min beginnt das Backen", "Um ca. \(Self.uhrzeit(b.at, jetzt: jetzt)): \(b.titel)."))
            }
        } else if let n = folgt(auf: laufend), offenAb == n {
            // Nur der nächste Schritt: Weiter geht es erst mit dem Abhaken, dann wird neu geplant.
            let c = schritte[laufend]
            for i in n...n {
                let s = schritte[i]
                let text = mitStart(i)
                    ? "\(s.dauer), „\(c.titel)“ läuft dabei weiter. In der App „Starten“ tippen."
                    : "\(s.dauer). Zum Weiterschalten „\(c.titel)“ als erledigt abhaken."
                out.append(("\(i):jetzt", s.at, "Jetzt: \(s.titel)", text))
                if vorlauf > 0 {
                    out.append(("\(i):bald", s.at - v, "In \(vorlauf) Min: \(s.titel)", "Um \(Self.uhrzeit(s.at, jetzt: jetzt)) (\(s.dauer))."))
                }
            }
        }
        // Weizenteig: in der laufenden ersten Gare dehnen und falten (kein eigener Schritt)
        if phase == .backen, schritte.indices.contains(laufend), schritte[laufend].titel == Rechner.gareFalten {
            let g = schritte[laufend]
            let zeiten = Rechner.faltZeiten(g.dauer)
            for (k, z) in zeiten.enumerated() {
                let text = k + 1 < zeiten.count
                    ? "Nächstes Mal um \(Self.uhrzeit(g.at + Double(zeiten[k + 1]) * Self.min, jetzt: jetzt))."
                    : "Das letzte Mal, danach in Ruhe gehen lassen."
                out.append(("\(laufend):falten\(k)", g.at + Double(z) * Self.min, "Dehnen und falten (\(k + 1) von \(zeiten.count))", text))
            }
        }
        // Backen: Wechsel von der Stufe mit Dampf auf die ohne
        if let e = dampfEnde, let d = dampf {
            let fertig = folgt(auf: laufend).map { " Fertig ca. \(Self.uhrzeit(schritte[$0].at, jetzt: jetzt))." } ?? ""
            // Bei 250 °C Ofentemperatur ist die Hitze mit Dampf dieselbe: nichts herunterschalten.
            let runter = d.heiss > d.temp
            out.append(("\(laufend):dampf", e, runter ? "Dampf raus, auf \(d.temp) °C" : "Dampf raus",
                        "Dampf ablassen bzw. Schüssel abnehmen" + (runter ? " und den Ofen auf \(d.temp) °C herunterschalten." : ", bei \(d.temp) °C weiterbacken.") + fertig))
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
            "dampf": dampf.map { Wert.json($0) } ?? .null,
        ]
    }

    init?(_ z: Zeile) {
        guard let p = z["phase"]?.text.flatMap(Phase.init(rawValue:)), let start = z["start"]?.zahl,
              let schritte = z["schritte"]?.json([TimerSchritt].self), !schritte.isEmpty else { return nil }
        let reife = z["reife"]?.json([Double].self) ?? [start, start]
        let v = z["vorlauf"]?.int ?? 10
        self.init(phase: p, start: start, reife: reife.count == 2 ? reife : [start, start],
                  vorlauf: Self.vorlaufWahl.contains(v) ? v : 10, schritte: schritte,
                  weiter: z["weiter"]?.int.map { Swift.min(Swift.max($0, Self.beginn), schritte.count) },
                  dampf: z["dampf"]?.json(BackAktivitaet.Dampf.self))
    }
}

#if DEBUG && canImport(UIKit)
import SwiftUI

#Preview("Timer · reift") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .reift) }
#Preview("Timer · Backen läuft") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .backen) }
#Preview("Seite · Backen läuft") { HauptAnsicht().vorschau(timer: .backen) }
#endif
