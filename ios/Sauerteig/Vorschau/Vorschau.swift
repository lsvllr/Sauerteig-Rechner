#if DEBUG
import SwiftUI

// Xcode-Canvas für die ganze App: Beispieldaten in einer Datenbank nur im Speicher (nichts landet in der echten
// Datei) und ein Back-Timer darauf. Die Vorschauen selbst stehen am Ende der jeweiligen Datei (Canvas zeigt die der
// offenen Datei). Nur in Debug-Builds.

@MainActor
enum Vorschau {
    enum Timer { case keiner, reift, reifUeberfaellig, backen, fertig }
    enum Fuettern { case nie, ok, heute, ueberfaellig }

    static let werte = SauerteigWerte()
    static var rezept: Berechnung { Rechner.rezept(werte.eingabe) }

    private static var jetzt: Double { Date().timeIntervalSince1970 * 1000 }
    private static let stunde = 3_600_000.0

    /// Lauf zum Standard-Rezept im gewünschten Zustand.
    static func lauf(_ t: Timer) -> BackLauf? {
        let r = rezept
        let reife = Rechner.spanne(r.zeitplan.sauerteigZeit) ?? (0, 0)
        func neu(vor h: Double) -> BackLauf { BackLauf.neu(r.schritte, start: (jetzt - h * stunde).rounded(), vorlauf: 10, reife: reife) }
        switch t {
        case .keiner: return nil
        case .reift: return neu(vor: 2)
        case .reifUeberfaellig: return neu(vor: 12)
        case .backen:
            // Vor 9 h angesetzt, vor 20 Min „Backen beginnen“, der Mischschritt läuft.
            return neu(vor: 9).hakeAb(BackLauf.beginn, am: jetzt - stunde / 3)
        case .fertig:
            var l = neu(vor: 20).hakeAb(BackLauf.beginn, am: jetzt - 6 * stunde)
            let letzter = l.schritte.count - 1
            l = l.hakeAb(letzter, am: jetzt - stunde / 4, ueberspringen: true)
            return l
        }
    }

    static func datenbank(timer: Timer = .keiner, fuettern: Fuettern = .ok, rezepte: Bool = false) -> Datenbank {
        let db = Datenbank(url: nil, geraet: "vorschau-geraet")
        if let l = lauf(timer) { db.starteBacklauf(l) }
        let tag = 86_400.0
        switch fuettern {
        case .nie: break
        case .ok: db.setzeFuetterung(zuletzt: Date().addingTimeInterval(-2 * tag), intervall: 7)
        case .heute: db.setzeFuetterung(zuletzt: Date().addingTimeInterval(-7 * tag), intervall: 7)
        case .ueberfaellig: db.setzeFuetterung(zuletzt: Date().addingTimeInterval(-10 * tag), intervall: 7)
        }
        if rezepte {
            db.speichereRezept("Roggenmischbrot", werte)
            var w = werte
            w.brotGroesse = 800
            db.speichereRezept("Kleines Brot", w)
        }
        return db
    }
}

extension View {
    /// Umgebung wie in der App (SauerteigApp), aber mit Beispieldaten.
    @MainActor
    func vorschau(timer: Vorschau.Timer = .keiner, fuettern: Vorschau.Fuettern = .ok, rezepte: Bool = false,
                  toast: AppState.Toast? = nil) -> some View {
        let db = Vorschau.datenbank(timer: timer, fuettern: fuettern, rezepte: rezepte)
        let app = AppState()
        app.toast = toast
        return self
            .environmentObject(app)
            .environmentObject(db)
            .environmentObject(BackTimer(db: db))
            .environmentObject(Abgleich(db: db))
            .environmentObject(Sicherung(db: db))
            .tint(Brand().accent)
    }

    /// Einzelne Karte auf dem Seitenhintergrund.
    func vorschauKarte() -> some View {
        ScrollView { self.padding(Metrics.gutter) }.hhBackground()
    }
}
#endif

#if DEBUG
#Preview("Übersicht") { HauptAnsicht().vorschau(timer: .backen, rezepte: true) }
#Preview("Live-Aktivität") { BackAktivitaetGalerie() }
#endif
