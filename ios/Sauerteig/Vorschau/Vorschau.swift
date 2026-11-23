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
    static let eintragUid = "00000000-0000-4000-8000-0000000000e1"
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
        if let l = lauf(timer) { db.starteBacklauf(l, einstellungen: werte) }
        let tag = 86_400.0
        switch fuettern {
        case .nie: break
        case .ok: db.setzeFuetterung(zuletzt: Date().addingTimeInterval(-2 * tag), intervall: 7)
        case .heute: db.setzeFuetterung(zuletzt: Date().addingTimeInterval(-7 * tag), intervall: 7)
        case .ueberfaellig: db.setzeFuetterung(zuletzt: Date().addingTimeInterval(-10 * tag), intervall: 7)
        }
        if rezepte {
            // Ein gebackenes Brot mit Bewertung, Notiz und Analyse, dazu ein nur gesichertes Rezept.
            db.legeEintragAn(werte, verlauf: lauf(.fertig), gebacken: Date().addingTimeInterval(-3600), uid: eintragUid)
            db.bewerteEintrag(eintragUid, gesamt: 4, kriterien: Kriterien(krume: 3, kruste: 5, ofentrieb: 3, geschmack: 5))
            db.setzeNotiz(eintragUid, "Teig sehr klebrig, Sauerteig erst nach gut 10 h reif. Unten etwas dicht.")
            db.setzeAnalyse(eintragUid, KrumenAnalyse(
                krume: .init(porung: "dicht", gleichmaessig: false, auffaelligkeiten: ["Dichte, feuchte Schicht über dem Boden", "Größere Löcher unter der Kruste"]),
                gare: "unter", kruste: "Kräftig gebräunt, gleichmäßig",
                diagnose: "Das Bild spricht für eine leichte Untergare: unten dicht, oben einzelne große Poren. Bei 70 % Roggen ist eine eher dichte Krume normal, die Schicht unten aber nicht.",
                vorschlaege: [
                    .init(parameter: "gareTemp", aenderung: 2, text: "", grund: "Wärmere Stückgare, damit der Teig in der geplanten Zeit voll aufgeht."),
                    .init(parameter: "", aenderung: 0, text: "Stückgare nach Fingerprobe statt nach Uhr beenden", grund: "Die Delle soll nur langsam halb zurückfedern."),
                ],
                sicherheit: "mittel", zeit: jetzt))
            var w = werte
            w.mischung = "custom"
            w.custom = Anteile(roggen: 60, dinkel: 40)
            w.brotGroesse = 800
            db.legeEintragAn(w, name: "Kleines Probebrot", gebacken: Date().addingTimeInterval(-9 * 86_400))
        }
        return db
    }
}

extension View {
    /// Umgebung wie in der App (SauerteigApp), aber mit Beispieldaten.
    @MainActor
    func vorschau(timer: Vorschau.Timer = .keiner, fuettern: Vorschau.Fuettern = .ok, rezepte: Bool = false,
                  toast: AppState.Toast? = nil, tab: AppState.Tab = .backen) -> some View {
        let db = Vorschau.datenbank(timer: timer, fuettern: fuettern, rezepte: rezepte)
        let app = AppState()
        app.toast = toast
        app.tab = tab
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
#Preview("Übersicht") { Wurzel().vorschau(timer: .backen, rezepte: true) }
#Preview("Live-Aktivität") { BackAktivitaetGalerie() }
#endif
