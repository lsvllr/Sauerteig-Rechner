import ActivityKit
import Foundation

/// Live-Aktivität des Back-Timers (Abschnitt 6.5): startet ab „Backen beginnen“, folgt jeder Änderung des Laufs
/// (abhaken, beenden) und meldet ihren Push-Token mit den Zeiten an den Weckdienst, der sie bei geschlossener App zu
/// jedem Schritt weiterschaltet. Die Reifezeit davor zeigt sie nicht: iOS beendet Live-Aktivitäten nach höchstens
/// 8 Stunden.
@MainActor
final class BackLive {
    static let shared = BackLive()

    /// Lauf (`start`), für den schon eine Aktivität gestartet wurde. Hat man sie auf dem Sperrbildschirm weggewischt,
    /// startet sie für diesen Lauf nicht von selbst neu.
    private let gestartetKey = "back-live-gestartet"
    private var beobachtet: String?
    /// `apns:<Token>` der laufenden Aktivität, `nil` = keine oder noch kein Token.
    private var token: String?
    /// Zuletzt an die Aktivität gegebene Zeiten (für den Weckdienst, sobald der Token kommt).
    private var zeiten: [Double] = []
    /// Was der Weckdienst schon hat; erneut melden nur bei Änderung.
    private var gemeldet: (token: String, zeiten: [Double])?

    private var laufende: [Activity<BackAktivitaet>] {
        Activity<BackAktivitaet>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    /// Aktivität auf den Stand von `lauf` bringen: starten, aktualisieren oder beenden.
    func abgleichen(_ lauf: BackLauf?) async {
        guard let l = lauf, l.phase == .backen, l.schritte.count > BackLauf.beginn + 1 else {
            UserDefaults.standard.removeObject(forKey: gestartetKey)
            await beendeAlle()
            return
        }
        let jetzt = Date()
        let attr = Self.attribute(l)
        let state = Self.stand(l, jetzt: jetzt)
        let i = state.laufend(jetzt)
        let content = ActivityContent(state: state, staleDate: Self.veraltet(state, i))
        let fertig = state.naechster(nach: i) == nil
        zeiten = state.zeiten

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
            UserDefaults.standard.set(l.start, forKey: gestartetKey)
            beobachte(a)
            if fertig {
                await a.end(content, dismissalPolicy: .after(Self.abbauen(state)))
            } else if a.content.state != state {
                // Aktualisieren statt beenden und neu starten (auch bei neuer Startzeit): sonst verschwindet sie kurz.
                await a.update(content)
            }
            await meldeWecker()
            return
        }
        guard !fertig, UserDefaults.standard.double(forKey: gestartetKey) != l.start,
              ActivityAuthorizationInfo().areActivitiesEnabled, let a = starte(attr, content) else { return }
        UserDefaults.standard.set(l.start, forKey: gestartetKey)
        beobachte(a)
        await meldeWecker()
    }

    /// Starten (nur im Vordergrund möglich). Mit Weckdienst per Push-Token; ohne Push-Berechtigung (kostenloses
    /// Konto) ohne Token.
    private func starte(_ attr: BackAktivitaet, _ content: ActivityContent<BackAktivitaet.ContentState>) -> Activity<BackAktivitaet>? {
        if Wecker.basis != nil, let a = try? Activity.request(attributes: attr, content: content, pushType: .token) { return a }
        return try? Activity.request(attributes: attr, content: content, pushType: nil)
    }

    private func beendeAlle() async {
        for a in laufende { await a.end(nil, dismissalPolicy: .immediate) }
        if let t = token ?? gemeldet?.token { await Wecker.stop(t) }
        token = nil
        gemeldet = nil
        beobachtet = nil
        zeiten = []
    }

    /// Push-Token verfolgen: kommt erst nach dem Start und kann wechseln. Jeder neue Token geht an den Weckdienst.
    private func beobachte(_ a: Activity<BackAktivitaet>) {
        guard beobachtet != a.id else { return }
        beobachtet = a.id
        token = a.pushToken.map(Self.endpoint)
        Task { [weak self] in
            for await t in a.pushTokenUpdates {
                guard let self, self.beobachtet == a.id else { return }
                self.token = Self.endpoint(t)
                await self.meldeWecker()
            }
        }
    }

    /// Token und Zeiten an den Weckdienst, wenn sich etwas geändert hat. Ohne Netz: beim nächsten Abgleich erneut.
    private func meldeWecker() async {
        guard let t = token, zeiten.count >= 2 else { return }
        if let g = gemeldet, g.token == t, g.zeiten == zeiten { return }
        let z = zeiten
        if await Wecker.melde(t, zeiten: z) { gemeldet = (t, z) }
    }

    private static func endpoint(_ token: Data) -> String {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        return "apns-sandbox:" + hex // Debug-Builds bekommen Tokens für den Sandbox-Server von APNs
        #else
        return "apns:" + hex
        #endif
    }

    static func attribute(_ l: BackLauf) -> BackAktivitaet {
        let s = l.schritte.dropFirst(BackLauf.beginn)
        return BackAktivitaet(start: l.start.rounded(), titel: s.map(\.titel), dauer: s.map(\.dauer))
    }

    /// Stand ab „Backen beginnt“: Zeiten, laufender Schritt, erster offener Schritt.
    static func stand(_ l: BackLauf, jetzt: Date) -> BackAktivitaet.ContentState {
        let zeiten = l.schritte.dropFirst(BackLauf.beginn).map { $0.at.rounded() }
        let ms = jetzt.timeIntervalSince1970 * 1000
        return BackAktivitaet.ContentState(zeiten: zeiten, aktuell: zeiten.lastIndex { $0 <= ms } ?? 0,
                                           weiter: l.offenAb - BackLauf.beginn)
    }

    /// Kurz nach dem nächsten Schritt gilt die Anzeige als veraltet: iOS zeichnet sie neu, die Ansicht rechnet den
    /// laufenden Schritt dann aus der Uhr (`laufend`), auch wenn kein Push kam.
    private static func veraltet(_ s: BackAktivitaet.ContentState, _ i: Int) -> Date? {
        s.naechster(nach: i).map { s.datum($0).addingTimeInterval(30) }
    }

    /// Nach dem letzten Schritt bleibt die Aktivität 2 Stunden stehen (Auskühlen).
    private static func abbauen(_ s: BackAktivitaet.ContentState) -> Date {
        (s.zeiten.last.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()).addingTimeInterval(2 * 3600)
    }
}

/// Weckdienst am Server (server/wecker.ts): kennt nur den Token der Aktivität und die Zeitpunkte.
enum Wecker {
    /// Aus Config/Sauerteig.xcconfig (`WECKER_URL`); leer = ohne Weckdienst.
    static let basis: URL? = {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "WeckerURL") as? String,
              s.hasPrefix("http"), let u = URL(string: s) else { return nil }
        return u
    }()

    private static func post(_ pfad: String, _ body: [String: Any]) async -> Bool {
        guard let basis else { return false }
        var req = URLRequest(url: basis.appendingPathComponent(pfad), timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (_, r) = try? await URLSession.shared.data(for: req) else { return false }
        return (r as? HTTPURLResponse)?.statusCode == 200
    }

    static func melde(_ token: String, zeiten: [Double]) async -> Bool {
        await post("api/wecker", ["token": token, "zeiten": zeiten.map { $0.rounded() }])
    }

    static func stop(_ token: String) async {
        _ = await post("api/wecker/stop", ["token": token])
    }
}
