import SwiftUI

/// Back-Timer: Stand aus der lokalen Datenbank (Tabelle `backlauf`). Jede Änderung (eigene, aus der Live-Aktivität
/// oder später per Abgleich empfangen) plant die Mitteilungen neu und bringt die Live-Aktivität auf den Stand.
@MainActor
final class BackTimer: ObservableObject {
    static let shared = BackTimer()

    @Published private(set) var lauf: BackLauf?
    private var uid: String?
    private let db: Datenbank

    init(db: Datenbank? = nil) {
        self.db = db ?? .shared
        lies(animiert: false)
    }

    private var now: Double { Date().timeIntervalSince1970 * 1000 }

    private func lies(animiert: Bool = true) {
        let x = db.backlauf
        uid = x?.uid
        guard x?.lauf != lauf else { return }
        if animiert { withAnimation(Metrics.move) { lauf = x?.lauf } } else { lauf = x?.lauf }
    }

    /// Nach jeder Änderung: neu lesen, Mitteilungen planen, Live-Aktivität abgleichen (startet sie bei Bedarf,
    /// meldet dem Weckdienst neue Zeiten).
    private func nachAenderung() async {
        lies()
        let l = lauf
        await Mitteilungen.planeBackTimer(l)
        await BackLive.shared.abgleichen(l)
        await Abgleich.shared.meldeZeitplan(l) // Web-Push der Browser im Konto
    }

    /// App im Vordergrund oder gestartet: abgelaufenen Lauf abräumen, Aktivität nachholen oder weiterschalten.
    /// Außerdem nach Änderungen von außen (Abgleich, später).
    func aufwachen() async {
        if let x = db.backlauf, x.lauf.abgelaufen(now) {
            db.eintragAusLauf(x.uid, x.lauf, jetzt: now)
            db.beendeBacklauf()
        }
        await nachAenderung()
    }

    /// Einstellungen für Mitteilungen oder Live-Aktivität geändert: neu planen und abgleichen.
    func einstellungenGeaendert() async { await nachAenderung() }

    /// „Sauerteig angesetzt“ mit den Einstellungen `w` (für den Eintrag im Tagebuch). Rückgabe: Mitteilungen erlaubt.
    func starte(_ l: BackLauf, werte w: SauerteigWerte? = nil) async -> Bool {
        let ok = await Mitteilungen.erlaubnis()
        db.starteBacklauf(l, einstellungen: w)
        await nachAenderung()
        return ok
    }

    /// Vorwarnung in den Einstellungen geändert: Mitteilungen neu planen. Der Wert geht auch in den laufenden Lauf,
    /// weil Web-App und Web-Push ihn von dort lesen; die Mitteilungen dieses Geräts nehmen immer die Einstellung.
    func vorlaufGeaendert() async {
        let v = Einstellungen.vorlauf
        if var l = lauf, let uid, l.vorlauf != v {
            l.vorlauf = v
            db.aendereBacklauf(uid, l)
        }
        await nachAenderung()
    }

    /// Sauerteig reif: der erste Backschritt beginnt um `am` (Standard jetzt).
    func beginneBacken(am: Date? = nil) { aendere { $0.hakeAb(BackLauf.beginn, am: $1(am)) } }

    /// Schritt `i` fertig, um `am` (Standard jetzt): Der nächste beginnt dann.
    func erledige(_ i: Int, am: Date? = nil) { aendere { $0.erledige(i, am: $1(am)) } }

    /// Schritt `i` mit eigenem Start (Ofen) beginnt um `am` (Standard jetzt); der vorige endet damit.
    func starte(_ i: Int, am: Date? = nil) { aendere { $0.starte(i, am: $1(am)) } }

    private func aendere(_ f: (BackLauf, (Date?) -> Double) -> BackLauf) {
        guard let l = lauf, let uid else { return }
        let neu = f(l) { (($0 ?? Date()).timeIntervalSince1970 * 1000).rounded() }
        guard neu != l else { return }
        db.aendereBacklauf(uid, neu)
        Task { await nachAenderung() }
    }

    /// Ansetzzeit ändern (Standard jetzt); spätere Schritte sind danach wieder offen.
    func setzeStart(am: Date? = nil) {
        guard let l = lauf, let uid else { return }
        let neu = l.setzeStart(am: ((am ?? Date()).timeIntervalSince1970 * 1000).rounded())
        guard neu != l else { return }
        db.aendereBacklauf(uid, neu)
        Task { await nachAenderung() }
    }

    /// Lauf beenden. War er fertig gebacken, steht er danach im Tagebuch; Rückgabe: uid des Eintrags.
    @discardableResult
    func beende() -> String? {
        let eintrag = db.backlauf.flatMap { db.eintragAusLauf($0.uid, $0.lauf, jetzt: now) }
        db.beendeBacklauf()
        Task { await nachAenderung() }
        return eintrag
    }

    /// Knopf „Erledigt“ in der Live-Aktivität (BackAbhakenIntent): Schritt `schritt` (Index ab „Backen beginnt“) jetzt
    /// fertig. `at` ist seine Zeit, wie die Aktivität sie zeigte; passt sie nicht mehr (inzwischen anders geändert),
    /// passiert nichts. Wartet bis zum Ende, sonst legt iOS die App vorher schlafen.
    func hakeAbAusAktivitaet(_ schritt: Int, at: Double) async {
        lies(animiert: false)
        let i = schritt + BackLauf.beginn
        guard let l = lauf, let uid, l.phase == .backen, l.schritte.indices.contains(i),
              l.schritte[i].at.rounded() == at.rounded() else { return }
        let neu = l.erledige(i, am: now)
        guard neu != l else { return }
        db.aendereBacklauf(uid, neu)
        await nachAenderung()
    }
}

#if DEBUG
#Preview("Timer · reift") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .reift) }
#Preview("Timer · Backen läuft") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .backen) }
#Preview("Timer · fertig") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .fertig) }
#endif
