import Foundation
import Security
import UIKit

/// Konto und Abgleich zwischen Geräten (LOCAL-FIRST.md Abschnitt 5), gleiches Protokoll wie die Web-App
/// (src/abgleich.ts) über den Server dieses Repos (`/api/sync/*`, server/server.ts).
///
/// - Ohne Konto läuft alles nur auf dem Gerät. Ein Konto braucht es nur, um Geräte zu verknüpfen (Einladungscode
///   für ein neues Konto, Gerätecode für ein weiteres Gerät).
/// - Mit nur einem Gerät im Konto liegt nichts am Server; „ausstehend“ wird dann verworfen, weil beim Einstieg in
///   einen Abgleich ohnehin alles gesendet wird.
/// - Ab zwei Geräten: holen (seitenweise ab dem eigenen Stand), einmal alles senden (Schnappschuss, je Kennung),
///   danach nur die ausstehenden Änderungen. Neue Kennung (Konto war zwischendurch nur ein Gerät): von vorn.
/// - Ende-zu-Ende verschlüsselt (Core/Verschluesselung.swift): Der Server sieht nur Tabelle, uid und Zeit. Den
///   Schlüssel bringt der Gerätecode mit; ein Gerät ohne Schlüssel bekommt nichts und holt ihn mit einem Code nach.
/// - Verteilen: Im Vordergrund hält die App eine Verbindung zum Server (Server-Sent Events) und holt, sobald er
///   „neu“ meldet. Geschlossen weckt sie ein stiller Push (AppDelegate). Dazu Anstoß nach jeder eigenen Änderung,
///   beim Öffnen und zur Sicherheit jede Minute.
///
/// Sitzungs-Schlüssel und Kontoschlüssel liegen im Schlüsselbund, Name des Kontos und Stand in UserDefaults.
@MainActor
final class Abgleich: ObservableObject {
    static let shared = Abgleich()

    struct Konto: Codable, Equatable { var name: String }

    @Published private(set) var konto: Konto?
    /// Geräte im Konto beim letzten Abgleich (0 = noch nicht bekannt).
    @Published private(set) var geraete = 0
    /// Das Konto hat einen Schlüssel, dieses Gerät nicht (oder einen anderen).
    @Published private(set) var schluesselFehlt = false

    private struct Zustand: Codable {
        var kennung = ""
        var ab = 0
        var gesendet = ""
    }

    private var z: Zustand
    private let db: Datenbank
    private var laeuft = false
    private var nochmal = false
    private var verzoegert: Task<Void, Never>?
    private var takt: Task<Void, Never>?
    private var live: Task<Void, Never>?
    private var pushGemeldet: String?
    private var zeitplanGemeldet: String?

    private static let kontoKey = "konto"
    private static let zustandKey = "abgleich"
    private static let geraeteKey = "abgleich-geraete"
    private static let pushKey = "abgleich-push"
    private static let seite = 500

    init(db: Datenbank? = nil) {
        self.db = db ?? .shared
        let d = UserDefaults.standard
        konto = d.data(forKey: Self.kontoKey).flatMap { try? JSONDecoder().decode(Konto.self, from: $0) }
        z = d.data(forKey: Self.zustandKey).flatMap { try? JSONDecoder().decode(Zustand.self, from: $0) } ?? Zustand()
        geraete = d.integer(forKey: Self.geraeteKey)
        pushGemeldet = d.string(forKey: Self.pushKey)
        // Schlüssel ohne Konto (App neu installiert, Schlüsselbund blieb): verwerfen.
        if konto == nil || Tresor.sitzung == nil {
            konto = nil
            Tresor.sitzung = nil
            Tresor.kontoSchluessel = nil
        }
    }

    /// Derselbe Server wie der Weckdienst (`WECKER_URL` in Config/Sauerteig.xcconfig); ohne ihn kein Konto.
    var verfuegbar: Bool { Wecker.basis != nil }

    // MARK: Konto

    /// Neues Konto mit Einladungscode, mit neuem Schlüssel. Rückgabe: Fehlertext oder nil.
    func registriere(code: String, name: String) async -> String? {
        await anmelden("api/registrieren", ["code": code, "name": name], geheim: nil)
    }

    /// Dieses Gerät mit einem Gerätecode (16 Zeichen, mit Schlüssel) an ein bestehendes Konto hängen.
    func verknuepfe(code: String) async -> String? {
        let t = Verschluesselung.zerlegeCode(code)
        return await anmelden("api/anmelden", ["code": t.server], geheim: t.geheim ?? "")
    }

    /// `geheim == nil`: neues Konto; "" : Code ohne Geheimnis (vom Admin), Schlüssel später nachholen.
    private func anmelden(_ pfad: String, _ felder: [String: String], geheim: String?) async -> String? {
        var body: [String: Any] = felder
        body["app"] = true
        body["geraet"] = "\(UIDevice.current.model), App"
        let r: Antwort
        do { r = try await rufe(pfad, methode: "POST", json: body, mitSchluessel: false) } catch {
            return "Keine Verbindung. Zum Verknüpfen braucht es Internet."
        }
        guard r.status == 200, let token = r.json["token"] as? String, let name = r.json["name"] as? String else {
            return r.fehler
        }
        Tresor.sitzung = token
        if let geheim {
            Tresor.kontoSchluessel = (r.json["schluessel"] as? String).flatMap { geheim.isEmpty ? nil : Verschluesselung.entpacke($0, geheim: geheim) }
        } else {
            Tresor.kontoSchluessel = Verschluesselung.neuerSchluessel()
        }
        setzeKonto(Konto(name: name))
        merke(Zustand())
        pushGemeldet = nil
        UIApplication.shared.registerForRemoteNotifications()
        await gleicheAb()
        return nil
    }

    /// Code für ein weiteres Gerät (15 Minuten, einmal): Teil für den Server + Geheimnis, mit dem der Schlüssel
    /// verpackt beim Server liegt. Das Geheimnis geht nie an den Server.
    func geraetecode() async -> Result<(code: String, bis: Date), FehlerText> {
        let k = Tresor.kontoSchluessel ?? {
            let neu = Verschluesselung.neuerSchluessel()
            Tresor.kontoSchluessel = neu
            return neu
        }()
        let geheim = Verschluesselung.neuesGeheimnis()
        guard let verpackt = try? Verschluesselung.verpacke(k, geheim: geheim) else { return .failure(FehlerText("Das hat nicht geklappt")) }
        do {
            let r = try await rufe("api/geraetecode", methode: "POST", json: ["schluessel": verpackt])
            if r.status == 401 { abgemeldet(); return .failure(FehlerText("Nicht mehr angemeldet")) }
            guard r.status == 200, let c = r.json["code"] as? String, let bis = r.json["gueltigBis"] as? Double else {
                return .failure(FehlerText(r.fehler))
            }
            return .success((Verschluesselung.zeigeCode(c, geheim), Date(timeIntervalSince1970: bis / 1000)))
        } catch {
            return .failure(FehlerText("Keine Verbindung"))
        }
    }

    /// Schlüssel mit dem Gerätecode eines anderen Geräts holen (dieses Gerät ist schon im Konto).
    func holeSchluessel(code: String) async -> String? {
        let t = Verschluesselung.zerlegeCode(code)
        guard let geheim = t.geheim else { return "Bitte den ganzen Code mit 16 Zeichen eingeben" }
        do {
            let r = try await rufe("api/schluessel", methode: "POST", json: ["code": t.server])
            guard r.status == 200, let blob = r.json["schluessel"] as? String,
                  let k = Verschluesselung.entpacke(blob, geheim: geheim) else {
                return r.status == 200 ? "Code passt nicht" : r.fehler
            }
            Tresor.kontoSchluessel = k
            await gleicheAb()
            return nil
        } catch {
            return "Keine Verbindung"
        }
    }

    /// Ein verknüpftes Gerät des Kontos (Sitzung am Server). `diese`: dieses Gerät.
    struct VerknuepftesGeraet: Decodable, Identifiable {
        var id: Int
        var geraet: String
        var erstellt: Double
        var zuletzt: Double
        var diese: Int
        var name: String { geraet.isEmpty ? "Unbekanntes Gerät" : geraet }
        var istDieses: Bool { diese != 0 }
        var seit: Date { Date(timeIntervalSince1970: erstellt / 1000) }
        var zuletztAktiv: Date { Date(timeIntervalSince1970: zuletzt / 1000) }
    }

    /// Alle verknüpften Geräte des Kontos, zuletzt aktive zuerst.
    func verknuepfteGeraete() async -> Result<[VerknuepftesGeraet], FehlerText> {
        struct Liste: Decodable { var sitzungen: [VerknuepftesGeraet] }
        do {
            let r = try await rufe("api/sitzungen")
            if r.status == 401 { abgemeldet(); return .failure(FehlerText("Nicht mehr angemeldet")) }
            guard r.status == 200, let l = try? JSONDecoder().decode(Liste.self, from: r.daten) else { return .failure(FehlerText(r.fehler)) }
            return .success(l.sitzungen)
        } catch {
            return .failure(FehlerText("Keine Verbindung"))
        }
    }

    /// Ein anderes Gerät aus dem Konto entfernen (verloren, verkauft, alte Anmeldung). Rückgabe: Fehlertext oder nil.
    func entferne(_ g: VerknuepftesGeraet) async -> String? {
        do {
            let r = try await rufe("api/sitzungen/\(g.id)", methode: "DELETE")
            if r.status == 401 { abgemeldet(); return "Nicht mehr angemeldet" }
            guard r.status == 200 else { return r.fehler }
        } catch {
            return "Keine Verbindung"
        }
        await gleicheAb()
        return nil
    }

    /// Dieses Gerät vom Konto trennen. Die Daten bleiben auf dem Gerät.
    func trenne() async -> String? {
        do {
            let r = try await rufe("api/abmelden", methode: "POST", json: [:])
            guard r.status == 200 || r.status == 401 else { return r.fehler }
        } catch {
            return "Keine Verbindung. Trennen geht nur online."
        }
        abgemeldet()
        return nil
    }

    /// Der Server kennt die Sitzung nicht mehr (getrennt, Konto gelöscht): nur noch lokal.
    private func abgemeldet() {
        Tresor.sitzung = nil
        Tresor.kontoSchluessel = nil
        setzeKonto(nil)
        merke(Zustand())
        setzeGeraete(0)
        schluesselFehlt = false
        vordergrund(false)
    }

    private func setzeKonto(_ k: Konto?) {
        konto = k
        UserDefaults.standard.set(k.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.kontoKey)
    }

    private func setzeGeraete(_ n: Int) {
        if geraete != n { geraete = n }
        UserDefaults.standard.set(n, forKey: Self.geraeteKey)
    }

    private func merke(_ neu: Zustand) {
        z = neu
        UserDefaults.standard.set(try? JSONEncoder().encode(neu), forKey: Self.zustandKey)
    }

    // MARK: Push und Zeitplan

    /// Push-Token für den stillen Push „es gibt Neues“ (AppDelegate). Nur mit Konto, nur bei Änderung.
    func meldePush(_ endpoint: String) async {
        guard konto != nil, endpoint != pushGemeldet,
              let r = try? await rufe("api/sync/push", methode: "POST", json: ["push": endpoint]), r.status == 200 else { return }
        pushGemeldet = endpoint
        UserDefaults.standard.set(endpoint, forKey: Self.pushKey)
    }

    /// Zeitplan ab „Backen beginnen“ für den Web-Push der Browser im Konto (der Server merkt ihn sich nur, wenn das
    /// Konto Browser mit Push hat). Bewusste Ausnahme von der Verschlüsselung, wie beim Weckdienst.
    func meldeZeitplan(_ l: BackLauf?) async {
        guard konto != nil else { return }
        let plan: [String: Any]? = l.flatMap { l in
            l.phase == .backen ? ["phase": "backen", "vorlauf": l.vorlauf,
                                  "schritte": l.schritte.map { ["at": $0.at.rounded(), "titel": $0.titel, "dauer": $0.dauer] }] : nil
        }
        let text = plan.flatMap { try? JSONSerialization.data(withJSONObject: $0, options: .sortedKeys) }.map { String(decoding: $0, as: UTF8.self) } ?? ""
        guard text != zeitplanGemeldet else { return }
        let r = plan == nil ? try? await rufe("api/timer/stop", methode: "POST", json: [:])
                            : try? await rufe("api/timer", methode: "POST", json: ["lauf": plan!])
        if r?.status == 200 { zeitplanGemeldet = text }
    }

    // MARK: KI

    /// Krume analysieren lassen (server/ki.ts): Der Server reicht Fotos und Angaben an Gemini weiter und speichert
    /// nichts davon. Bewusste Ausnahme von der Verschlüsselung, nur auf Knopfdruck. Braucht ein Konto, damit nicht
    /// jeder den Schlüssel am Server nutzen kann.
    func analysiereKrume(_ body: Data) async -> Result<KrumenAnalyse, FehlerText> {
        guard konto != nil else { return .failure(FehlerText("Die Analyse braucht ein Konto (Einstellungen → Geräte verknüpfen)")) }
        do {
            let r = try await rufe("api/ki/krume", methode: "POST", daten: body, timeout: 120)
            if r.status == 401 { abgemeldet(); return .failure(FehlerText("Nicht mehr angemeldet")) }
            guard r.status == 200 else { return .failure(FehlerText(r.fehler)) }
            struct AnalyseAntwort: Decodable { var analyse: KrumenAnalyse }
            guard let a = try? JSONDecoder().decode(AnalyseAntwort.self, from: r.daten) else {
                return .failure(FehlerText("Antwort der KI nicht lesbar"))
            }
            return .success(a.analyse)
        } catch {
            return .failure(FehlerText("Keine Verbindung"))
        }
    }

    // MARK: Abgleich

    /// App im Vordergrund: jetzt abgleichen, Live-Verbindung halten und jede Minute nachsehen; im Hintergrund nicht.
    func vordergrund(_ aktiv: Bool) {
        takt?.cancel()
        live?.cancel()
        takt = nil
        live = nil
        guard aktiv, konto != nil else { return }
        takt = Task { [weak self] in
            while !Task.isCancelled {
                await self?.gleicheAb()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        live = Task { [weak self] in
            while !Task.isCancelled {
                await self?.horche()
                try? await Task.sleep(nanoseconds: 5_000_000_000) // getrennt: kurz warten, neu verbinden
            }
        }
    }

    /// Server-Sent Events: bei „neu“ holen. Kehrt zurück, wenn die Verbindung abbricht.
    private func horche() async {
        guard let req = try? anfrage("api/sync/live", timeout: 3600) else { return }
        do {
            let (bytes, r) = try await URLSession.shared.bytes(for: req)
            guard (r as? HTTPURLResponse)?.statusCode == 200 else { return }
            for try await zeile in bytes.lines where zeile.hasPrefix("event: neu") {
                Task { await gleicheAb() }
            }
        } catch {}
    }

    /// Eigene Änderung: kurz warten (mehrere schnell hintereinander zusammen), dann senden.
    func nachEigenerAenderung() {
        guard konto != nil else { return }
        verzoegert?.cancel()
        verzoegert = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.gleicheAb()
        }
    }

    func gleicheAb() async {
        guard konto != nil else { return }
        if laeuft {
            nochmal = true
            return
        }
        laeuft = true
        defer { laeuft = false }
        repeat {
            nochmal = false
            do { try await einmal() } catch { return } // offline: beim nächsten Anstoß
        } while nochmal && konto != nil
    }

    private struct Holen: Decodable {
        var kennung: String
        var geraete: Int
        var schluessel: Bool
        var schluesselDa: Bool?
        var aenderungen: [Aenderung]
        var bis: Int
        var mehr: Bool
    }

    private struct Senden: Encodable {
        var kennung: String
        var schluessel: String
        var aenderungen: [Aenderung]
    }

    private func einmal() async throws {
        let k = Tresor.kontoSchluessel
        let id = k.map(Verschluesselung.kennung) ?? ""
        // Holen bis zum Ende
        while true {
            var q = URLComponents()
            q.queryItems = [URLQueryItem(name: "kennung", value: z.kennung), URLQueryItem(name: "ab", value: String(z.ab)),
                            URLQueryItem(name: "schluessel", value: id)]
            let r = try await rufe("api/sync/holen?" + (q.percentEncodedQuery ?? ""))
            if r.status == 401 { return abgemeldet() }
            guard r.status == 200, let h = try? JSONDecoder().decode(Holen.self, from: r.daten) else { return }
            setzeGeraete(h.geraete)
            guard h.schluessel, let k else {
                // Älteres Konto ohne Schlüssel: dieses Gerät erzeugt ihn und legt ihn beim nächsten Holen fest
                if k == nil && h.schluesselDa != true {
                    Tresor.kontoSchluessel = Verschluesselung.neuerSchluessel()
                    nochmal = true
                } else if !schluesselFehlt { schluesselFehlt = true }
                return
            }
            if schluesselFehlt { schluesselFehlt = false }
            let neueKennung = h.kennung != z.kennung
            db.wende(h.aenderungen.compactMap { Verschluesselung.entschluessele(k, $0) })
            merke(Zustand(kennung: h.kennung, ab: h.bis, gesendet: neueKennung ? "" : z.gesendet))
            if !h.mehr { break }
        }
        // Allein im Konto: nichts senden, nichts aufheben
        guard geraete >= 2, let k else {
            if !db.aus.isEmpty { db.quittiere(Set(db.aus.map(\.zeit))) }
            return
        }
        let alles = z.gesendet != z.kennung
        let aus = db.aus
        let liste = alles ? db.schnappschuss() : aus
        guard alles || !liste.isEmpty else { return }
        var i = 0
        repeat {
            let teil = Array(liste[i..<min(i + Self.seite, liste.count)])
            let geheim = try teil.map { try Verschluesselung.verschluessele(k, $0) }
            let body = try JSONEncoder().encode(Senden(kennung: z.kennung, schluessel: id, aenderungen: geheim))
            let r = try await rufe("api/sync/senden", methode: "POST", daten: body)
            if r.status == 401 { return abgemeldet() }
            // Kennung neu oder allein: beim nächsten Mal von vorn
            guard r.status == 200, r.json["angenommen"] as? Bool == true else { return }
            db.quittiere(Set((alles ? aus : teil).map(\.zeit)))
            i += Self.seite
        } while i < liste.count
        if alles { merke(Zustand(kennung: z.kennung, ab: z.ab, gesendet: z.kennung)) }
    }

    // MARK: HTTP

    struct FehlerText: Error { var text: String; init(_ t: String) { text = t } }

    private struct Antwort {
        var status: Int
        var daten: Data
        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: daten)) as? [String: Any] ?? [:] }
        /// Fehlertext des Servers; fehlt er, kam die Antwort nicht von ihm (z. B. Cloudflare): Status und Anfang zeigen.
        var fehler: String {
            if let e = json["error"] as? String { return e }
            let text = String(decoding: daten.prefix(300), as: UTF8.self)
            print("Abgleich: HTTP \(status), Antwort: \(text)")
            let kurz = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(80)
            return "Das hat nicht geklappt (HTTP \(status)\(kurz.isEmpty ? "" : ": \(kurz)"))"
        }
    }

    private func anfrage(_ pfad: String, timeout: TimeInterval = 20, mitSchluessel: Bool = true) throws -> URLRequest {
        guard let basis = Wecker.basis,
              let url = URL(string: pfad, relativeTo: basis.hasDirectoryPath ? basis : basis.appendingPathComponent("")) else {
            throw FehlerText("Kein Server eingestellt")
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        if mitSchluessel, let t = Tresor.sitzung { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private func rufe(_ pfad: String, methode: String = "GET", json: [String: Any]? = nil, daten: Data? = nil,
                      mitSchluessel: Bool = true, timeout: TimeInterval = 20) async throws -> Antwort {
        var req = try anfrage(pfad, timeout: timeout, mitSchluessel: mitSchluessel)
        req.httpMethod = methode
        if let body = daten ?? json.flatMap({ try? JSONSerialization.data(withJSONObject: $0) }) {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (d, r) = try await URLSession.shared.data(for: req)
        return Antwort(status: (r as? HTTPURLResponse)?.statusCode ?? 0, daten: d)
    }
}

/// Sitzungs-Schlüssel und Kontoschlüssel im Schlüsselbund (nur dieses Gerät, nicht in Backups).
enum Tresor {
    static var sitzung: String? {
        get { lies("sauerteig-sitzung").flatMap { String(data: $0, encoding: .utf8) } }
        set { setze("sauerteig-sitzung", newValue.map { Data($0.utf8) }) }
    }

    static var kontoSchluessel: Data? {
        get { lies("sauerteig-schluessel").flatMap { $0.count == 32 ? $0 : nil } }
        set { setze("sauerteig-schluessel", newValue) }
    }

    private static func lies(_ dienst: String) -> Data? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var r: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &r) == errSecSuccess else { return nil }
        return r as? Data
    }

    private static func setze(_ dienst: String, _ d: Data?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst]
        SecItemDelete(q as CFDictionary)
        guard let d else { return }
        var neu = q
        neu[kSecValueData as String] = d
        neu[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(neu as CFDictionary, nil)
    }
}
