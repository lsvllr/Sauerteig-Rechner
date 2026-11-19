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
        if let l = db.backlauf?.lauf, l.abgelaufen(now) { db.beendeBacklauf() }
        await nachAenderung()
    }

    /// Einstellungen für Mitteilungen oder Live-Aktivität geändert: neu planen und abgleichen.
    func einstellungenGeaendert() async { await nachAenderung() }

    /// „Sauerteig angesetzt“. Rückgabe: Mitteilungen erlaubt.
    func starte(_ l: BackLauf) async -> Bool {
        let ok = await Mitteilungen.erlaubnis()
        db.starteBacklauf(l)
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

    func beginneBacken() { hakeAb(BackLauf.beginn) }

    /// Schritt `i` erledigt, um `am` (Standard jetzt).
    func hakeAb(_ i: Int, am: Date? = nil) {
        guard let l = lauf, let uid else { return }
        let neu = l.hakeAb(i, am: (am?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000)
        guard neu != l else { return }
        db.aendereBacklauf(uid, neu)
        Task { await nachAenderung() }
    }

    func beende() {
        db.beendeBacklauf()
        Task { await nachAenderung() }
    }

    /// Knopf „Erledigt“ in der Live-Aktivität (BackAbhakenIntent): Schritt `schritt` (Index ab „Backen beginnt“) jetzt
    /// erledigt. `at` ist seine Zeit, wie die Aktivität sie zeigte; passt sie nicht mehr (inzwischen anders geändert),
    /// passiert nichts. Wartet bis zum Ende (Weckdienst inklusive), sonst legt iOS die App vorher schlafen.
    func hakeAbAusAktivitaet(_ schritt: Int, at: Double) async {
        lies(animiert: false)
        let i = schritt + BackLauf.beginn
        guard let l = lauf, let uid, l.phase == .backen, l.schritte.indices.contains(i),
              l.schritte[i].at.rounded() == at.rounded() else { return }
        let neu = l.hakeAb(i, am: now, ueberspringen: true)
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
