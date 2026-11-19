import Foundation

// Tabellen der App auf der lokalen Datenbank. Verweise nur über die uid.

/// Gespeichertes Rezept (Tabelle `rezept`): Name, Datum, Einstellungen als **ein** JSON-Feld im Format der Web-App.
struct Rezept: Identifiable, Hashable {
    var id: String // uid
    var name: String
    var datum: String
    var werte: SauerteigWerte
    var erstellt: String
}

/// Füttern (Tabelle `profil`, eine Zeile): zuletzt gefüttert (Tag) und Rhythmus in Tagen.
struct Fuetterung: Hashable {
    var zuletzt: Date?
    var intervall: Int

    /// Wieder fällig: Tag „zuletzt + Rhythmus“, mittags (Vergleich nach Kalendertagen).
    var faellig: Date? {
        zuletzt.flatMap { Calendar.current.date(byAdding: .day, value: intervall, to: Calendar.current.startOfDay(for: $0)) }
            .map { $0.addingTimeInterval(12 * 3600) }
    }

    /// Ab so vielen Tagen über der Fälligkeit gilt der Sauerteig als dringend (Glas rot, Erinnerung jeden Tag).
    static let dringendAb = 2

    /// Tage bis zur Fälligkeit nach Kalendertagen: 0 = heute fällig, negativ = überfällig; `nil` = nie eingetragen.
    func restTage(heute: Date = Date()) -> Int? {
        guard let faellig else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: heute), to: cal.startOfDay(for: faellig)).day
    }

    enum Stand { case ruhig, faellig, dringend }

    /// Farbe des Glases oben links: fällig (gelb) ab dem Fälligkeitstag, dringend (rot) ab `dringendAb` Tagen drüber.
    func stand(heute: Date = Date()) -> Stand {
        guard let rest = restTage(heute: heute) else { return .ruhig }
        if rest <= -Self.dringendAb { return .dringend }
        return rest <= 0 ? .faellig : .ruhig
    }
}

extension Datenbank {
    static let rezeptTabelle = "rezept"
    static let profilTabelle = "profil"
    /// Feste uid der einen Profilzeile: zwei Geräte schreiben später in dieselbe Zeile statt zwei anzulegen.
    static let profilUid = "00000000-0000-4000-8000-000000000001"

    private static let tagFormat: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let datumFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    // MARK: Rezepte

    var rezepte: [Rezept] {
        zeilen(Self.rezeptTabelle).compactMap { uid, z in
            guard let name = z["name"]?.text else { return nil }
            let e = z["einstellungen"]?.json([String: Wert].self) ?? [:]
            return Rezept(id: uid, name: name, datum: z["datum"]?.text ?? "", werte: SauerteigWerte(einstellungen: e),
                          erstellt: z.z["name"] ?? "")
        }
        .sorted { $0.erstellt > $1.erstellt }
    }

    func speichereRezept(_ name: String, _ w: SauerteigWerte, jetzt: Date = Date()) {
        schreibe(Self.rezeptTabelle, UUID().uuidString.lowercased(), [
            "name": .text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))),
            "datum": .text(Self.datumFormat.string(from: jetzt)),
            "einstellungen": .json(w.einstellungen),
        ], jetzt: jetzt)
    }

    func loescheRezept(_ uid: String) { loesche(Self.rezeptTabelle, uid) }

    // MARK: Füttern

    var fuetterung: Fuetterung {
        let z = zeile(Self.profilTabelle, Self.profilUid)
        let tag = z?["sauerteig_gefuettert"]?.text.flatMap { Self.tagFormat.date(from: $0) }
        let i = z?["sauerteig_intervall"]?.int ?? 7
        return Fuetterung(zuletzt: tag, intervall: (1...60).contains(i) ? i : 7)
    }

    func setzeFuetterung(zuletzt: Date?, intervall: Int) {
        schreibe(Self.profilTabelle, Self.profilUid, [
            "sauerteig_gefuettert": zuletzt.map { .text(Self.tagFormat.string(from: $0)) } ?? .null,
            "sauerteig_intervall": .zahl(Double(min(max(intervall, 1), 60))),
        ])
    }

    // MARK: Back-Lauf

    /// Laufender Lauf: jüngste nicht gelöschte Zeile.
    var backlauf: (uid: String, lauf: BackLauf)? {
        zeilen(BackLauf.tabelle).compactMap { uid, z in BackLauf(z).map { (uid, $0, z.z["start"] ?? "") } }
            .max { ($0.2, $0.0) < ($1.2, $1.0) }
            .map { ($0.0, $0.1) }
    }

    /// Neuer Lauf: alte beenden (Löschmarken), neue Zeile.
    func starteBacklauf(_ l: BackLauf) {
        for (uid, _) in zeilen(BackLauf.tabelle) { loesche(BackLauf.tabelle, uid) }
        schreibe(BackLauf.tabelle, UUID().uuidString.lowercased(), l.felder)
    }

    func aendereBacklauf(_ uid: String, _ l: BackLauf) { schreibe(BackLauf.tabelle, uid, l.felder) }

    func beendeBacklauf() {
        for (uid, _) in zeilen(BackLauf.tabelle) { loesche(BackLauf.tabelle, uid) }
    }
}

#if DEBUG && canImport(UIKit)
import SwiftUI

#Preview("Füttern · überfällig") { FuetternKarte().vorschauKarte().vorschau(fuettern: .ueberfaellig) }
#Preview("Gespeicherte Rezepte") { HauptAnsicht().vorschau(rezepte: true) }
#endif
