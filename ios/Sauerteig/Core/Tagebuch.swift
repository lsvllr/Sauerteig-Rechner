import Foundation

// Backtagebuch (Tabelle `backeintrag`): Jedes Backen und jedes gesicherte Rezept ist ein Eintrag mit allen
// Einstellungen, den berechneten Mengen, dem tatsächlichen Verlauf des Back-Timers, Bewertung, Notiz, Fotos und
// optional der KI-Analyse der Krume. Was als Ganzes gelten muss, steht als **ein** JSON-Feld (LOCAL-FIRST.md 3).
// Fotos liegen nur auf dem Gerät (App/Bilder.swift); im Eintrag stehen nur ihre IDs.

/// Mengen und Zeiten der Berechnung beim Sichern. Bleibt so, auch wenn sich der Rechner später ändert.
struct Mengen: Codable, Hashable, Sendable {
    var anstellgut, sauerteigMehl, sauerteigWasser: Int
    var mehl: Anteile
    var hauptteigWasser, salz, teiggewicht: Int
    var sauerteigZeit, gareZeit, ersteGare, stueckgare, backZeit: String
    var ofenTemp, anbackTemp, dampfMin: Int

    init(_ r: Berechnung) {
        anstellgut = r.anstellgut
        sauerteigMehl = r.sauerteigMehl
        sauerteigWasser = r.sauerteigWasser
        mehl = r.mehl
        hauptteigWasser = r.hauptteigWasser
        salz = r.salz
        teiggewicht = r.teiggewicht
        sauerteigZeit = r.zeitplan.sauerteigZeit
        gareZeit = r.zeitplan.gareZeit
        ersteGare = r.ersteGare
        stueckgare = r.stueckgare
        backZeit = r.backZeit
        ofenTemp = r.ofenTemp
        anbackTemp = r.anbackTemp
        dampfMin = r.dampfMin
    }
}

/// Einzelne Bewertungen, je 0 (nicht bewertet) bis 5.
struct Kriterien: Codable, Hashable, Sendable {
    var krume = 0
    var kruste = 0
    var ofentrieb = 0
    var geschmack = 0

    enum Art: String, CaseIterable, Sendable {
        case krume, kruste, ofentrieb, geschmack
        var name: String {
            switch self {
            case .krume: return "Krume"
            case .kruste: return "Kruste"
            case .ofentrieb: return "Ofentrieb"
            case .geschmack: return "Geschmack"
            }
        }
    }

    subscript(a: Art) -> Int {
        get {
            switch a {
            case .krume: return krume
            case .kruste: return kruste
            case .ofentrieb: return ofentrieb
            case .geschmack: return geschmack
            }
        }
        set {
            let v = min(max(newValue, 0), 5)
            switch a {
            case .krume: krume = v
            case .kruste: kruste = v
            case .ofentrieb: ofentrieb = v
            case .geschmack: geschmack = v
            }
        }
    }

    var leer: Bool { Art.allCases.allSatisfy { self[$0] == 0 } }
}

/// Ergebnis der KI-Analyse (Antwort von `/api/ki/krume`, server/ki.ts, gleiches Schema).
struct KrumenAnalyse: Codable, Hashable, Sendable {
    struct Krume: Codable, Hashable, Sendable {
        /// offen | mittel | dicht
        var porung: String
        var gleichmaessig: Bool
        var auffaelligkeiten: [String]
    }

    struct Vorschlag: Codable, Hashable, Sendable {
        /// Schlüssel aus `Stellgroesse` oder "" für einen reinen Hinweis
        var parameter: String
        var aenderung: Double
        var text: String
        var grund: String
    }

    var krume: Krume
    /// unter | optimal | ueber | unklar
    var gare: String
    var kruste: String
    var diagnose: String
    var vorschlaege: [Vorschlag]
    /// hoch | mittel | niedrig
    var sicherheit: String
    /// Zeitpunkt der Analyse (ms), setzt die App
    var zeit: Double?

    var gareText: String {
        switch gare {
        case "unter": return "Untergare"
        case "ueber": return "Übergare"
        case "optimal": return "Gare passt"
        default: return "Gare unklar"
        }
    }

    /// Vorschläge, die sich als Einstellung übernehmen lassen.
    var stellbar: [Vorschlag] { vorschlaege.filter { Stellgroesse(rawValue: $0.parameter) != nil && $0.aenderung != 0 } }
}

/// Einstellungen am Rechner, die die KI ändern darf. Bereiche und Schritte wie die Regler der Hauptansicht.
enum Stellgroesse: String, CaseIterable, Sendable {
    case anstellgut, sauerteigTemp, gareTemp, brotGroesse, hydration, ofenTemp

    var name: String {
        switch self {
        case .anstellgut: return "Anstellgut"
        case .sauerteigTemp: return "Sauerteig-Temperatur"
        case .gareTemp: return "Gare-Temperatur"
        case .brotGroesse: return "Teiggewicht"
        case .hydration: return "Hydration"
        case .ofenTemp: return "Ofentemperatur"
        }
    }

    var einheit: String {
        switch self {
        case .anstellgut, .brotGroesse: return "g"
        case .sauerteigTemp, .gareTemp, .ofenTemp: return "°C"
        case .hydration: return "%"
        }
    }

    var bereich: ClosedRange<Int> {
        switch self {
        case .anstellgut: return 30...200
        case .sauerteigTemp: return 18...32
        case .gareTemp: return 20...32
        case .brotGroesse: return 600...2000
        case .hydration: return 50...85
        case .ofenTemp: return 200...250
        }
    }

    var schritt: Int {
        switch self {
        case .brotGroesse: return 100
        case .ofenTemp: return 5
        default: return 1
        }
    }

    var pfad: WritableKeyPath<SauerteigWerte, Int> {
        switch self {
        case .anstellgut: return \.anstellgut
        case .sauerteigTemp: return \.sauerteigTemp
        case .gareTemp: return \.gareTemp
        case .brotGroesse: return \.brotGroesse
        case .hydration: return \.hydration
        case .ofenTemp: return \.ofenTemp
        }
    }

    /// Wert nach der Änderung: auf den Schritt gerundet und im Bereich.
    func neu(_ alt: Int, _ aenderung: Double) -> Int {
        let roh = Double(alt) + aenderung
        let gerundet = Int((roh / Double(schritt)).rounded()) * schritt
        return min(max(gerundet, bereich.lowerBound), bereich.upperBound)
    }
}

extension SauerteigWerte {
    /// Einstellungen mit den übernehmbaren Vorschlägen der KI.
    func mitVorschlaegen(_ v: [KrumenAnalyse.Vorschlag]) -> SauerteigWerte {
        var w = self
        for x in v {
            guard let p = Stellgroesse(rawValue: x.parameter), x.aenderung.isFinite else { continue }
            w[keyPath: p.pfad] = p.neu(w[keyPath: p.pfad], x.aenderung)
        }
        return w
    }
}

struct Backeintrag: Identifiable, Hashable {
    var id: String // uid
    /// Selbst gewählter Name; leer = aus der Mehlmischung
    var eigenerName: String
    var gebacken: Date
    var werte: SauerteigWerte
    var mengen: Mengen?
    /// Back-Timer, wie er am Ende stand (tatsächliche Zeiten); nil = nur gesichert, nicht mit Timer gebacken
    var verlauf: BackLauf?
    var bewertung: Int
    var kriterien: Kriterien
    var notiz: String
    var bilder: [String]
    var analyse: KrumenAnalyse?

    var name: String { eigenerName.isEmpty ? Self.automatischerName(werte) : eigenerName }

    /// Name aus der Mehlmischung: „Roggen Optimal“, eigene Mischung „Roggen 60 % · Dinkel 40 %“.
    static func automatischerName(_ w: SauerteigWerte) -> String {
        if w.mischung != "custom", let m = SauerteigDaten.mischung(w.mischung) { return m.name }
        let a = w.anteile
        let teile = Sorte.allCases.filter { a[$0] > 0 }.sorted { a[$0] > a[$1] }.map { "\($0.name) \(a[$0]) %" }
        return teile.isEmpty ? "Eigene Mischung" : teile.joined(separator: " · ")
    }

    /// Reifezeit des Sauerteigs in Minuten: geplant (Spanne aus dem Rechner) und tatsächlich (bis „Backen beginnen“).
    var reife: (geplant: (Int, Int)?, tatsaechlich: Int?) {
        let g = mengen.flatMap { Rechner.spanne($0.sauerteigZeit) }
        guard let l = verlauf, l.offenAb > BackLauf.beginn, l.schritte.count > BackLauf.beginn else { return (g, nil) }
        return (g, Int(((l.schritte[BackLauf.beginn].at - l.start) / BackLauf.min).rounded()))
    }
}

extension Datenbank {
    static let eintragTabelle = "backeintrag"

    private static let eintragTagFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    private static func eintrag(_ uid: String, _ z: Zeile) -> Backeintrag? {
        guard let e = z["einstellungen"]?.json([String: Wert].self) else { return nil }
        let werte = SauerteigWerte(einstellungen: e)
        let ms = z["gebacken"]?.zahl ?? 0
        return Backeintrag(id: uid, eigenerName: z["name"]?.text ?? "", gebacken: Date(timeIntervalSince1970: ms / 1000),
                           werte: werte, mengen: z["mengen"]?.json(Mengen.self), verlauf: z["verlauf"]?.json(BackLauf.self),
                           bewertung: min(max(z["bewertung"]?.int ?? 0, 0), 5),
                           kriterien: z["kriterien"]?.json(Kriterien.self) ?? Kriterien(), notiz: z["notiz"]?.text ?? "",
                           bilder: z["bilder"]?.json([String].self) ?? [], analyse: z["analyse"]?.json(KrumenAnalyse.self))
    }

    /// Alle Einträge, zuletzt gebackene zuerst.
    var backeintraege: [Backeintrag] {
        zeilen(Self.eintragTabelle).compactMap { Self.eintrag($0.uid, $0.zeile) }
            .sorted { ($0.gebacken, $0.id) > ($1.gebacken, $1.id) }
    }

    func backeintrag(_ uid: String) -> Backeintrag? { zeile(Self.eintragTabelle, uid).flatMap { Self.eintrag(uid, $0) } }

    /// Neuer Eintrag. Mengen rechnet der Rechner jetzt aus, damit sie im Eintrag bleiben. Rückgabe: uid.
    @discardableResult
    func legeEintragAn(_ w: SauerteigWerte, name: String = "", verlauf: BackLauf? = nil, gebacken: Date = Date(),
                       uid: String = UUID().uuidString.lowercased(), jetzt: Date = Date()) -> String {
        var felder: [String: Wert] = [
            "name": .text(Self.saubererName(name, w)),
            "gebacken": .zahl((gebacken.timeIntervalSince1970 * 1000).rounded()),
            "einstellungen": .json(w.einstellungen),
            "mengen": .json(Mengen(Rechner.rezept(w.eingabe))),
        ]
        if let verlauf { felder["verlauf"] = .json(verlauf) }
        schreibe(Self.eintragTabelle, uid, felder, jetzt: jetzt)
        return uid
    }

    /// Leer oder gleich dem automatischen Namen: leer speichern, dann folgt der Name der Mischung.
    private static func saubererName(_ name: String, _ w: SauerteigWerte) -> String {
        let n = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        return n == Backeintrag.automatischerName(w) ? "" : n
    }

    func benenneEintrag(_ uid: String, _ name: String) {
        guard let e = backeintrag(uid) else { return }
        schreibe(Self.eintragTabelle, uid, ["name": .text(Self.saubererName(name, e.werte))])
    }

    func bewerteEintrag(_ uid: String, gesamt: Int? = nil, kriterien: Kriterien? = nil) {
        var f: [String: Wert] = [:]
        if let gesamt { f["bewertung"] = .zahl(Double(min(max(gesamt, 0), 5))) }
        if let kriterien { f["kriterien"] = .json(kriterien) }
        schreibe(Self.eintragTabelle, uid, f)
    }

    func setzeNotiz(_ uid: String, _ text: String) {
        schreibe(Self.eintragTabelle, uid, ["notiz": .text(String(text.prefix(4000)))])
    }

    func setzeBilder(_ uid: String, _ ids: [String]) { schreibe(Self.eintragTabelle, uid, ["bilder": .json(ids)]) }

    func setzeAnalyse(_ uid: String, _ a: KrumenAnalyse?) {
        schreibe(Self.eintragTabelle, uid, ["analyse": a.map { .json($0) } ?? .null])
    }

    /// Löscht auch das alte Rezept mit derselben uid (sonst holte die Übernahme es zurück).
    func loescheEintrag(_ uid: String) {
        loesche(Self.eintragTabelle, uid)
        loesche(Self.rezeptTabelle, uid)
    }

    /// Gesicherte Rezepte (Tabelle `rezept`, auch von der Web-App) als Einträge übernehmen, je uid einmal: Gibt es
    /// den Eintrag schon (auch gelöscht), passiert nichts. Die Rezepte bleiben für die Web-App stehen.
    func uebernimmRezepte() {
        let vorhanden = tabellen[Self.eintragTabelle] ?? [:]
        for r in rezepte where vorhanden[r.id] == nil {
            let tag = Self.eintragTagFormat.date(from: r.datum) ?? Date()
            legeEintragAn(r.werte, name: r.name == "Mein Sauerteigbrot" ? "" : r.name, gebacken: tag, uid: r.id)
        }
    }

    // MARK: Back-Lauf → Eintrag

    /// Einstellungen, mit denen der Lauf `uid` angesetzt wurde (Feld `einstellungen` der Zeile `backlauf`).
    func einstellungenZuLauf(_ uid: String) -> SauerteigWerte? {
        zeile(BackLauf.tabelle, uid)?["einstellungen"]?.json([String: Wert].self).map { SauerteigWerte(einstellungen: $0) }
    }

    /// Fertig gebackener Lauf (Backen begonnen, alle Schritte vorbei) → Eintrag mit derselben uid. Zwei Geräte, die
    /// ihn gleichzeitig abräumen, schreiben so in dieselbe Zeile. Vor `beendeBacklauf` aufrufen. Rückgabe: uid des
    /// Eintrags oder nil (nicht fertig, ohne Einstellungen, schon gelöscht).
    @discardableResult
    func eintragAusLauf(_ uid: String, _ l: BackLauf, jetzt: Double) -> String? {
        guard l.phase == .backen, l.naechster(jetzt) == -1, let w = einstellungenZuLauf(uid) else { return nil }
        if let alt = tabellen[Self.eintragTabelle]?[uid] { return alt.geloescht ? nil : uid }
        let ende = Date(timeIntervalSince1970: (l.schritte.last?.at ?? jetzt) / 1000)
        return legeEintragAn(w, verlauf: l, gebacken: ende, uid: uid)
    }
}

// MARK: - Kontext für die KI

/// Was die App zur Analyse mitschickt (server/ki.ts baut daraus den Prompt). Zeiten in Minuten ab dem Ansetzen.
struct KIKontext: Codable, Sendable {
    struct Schritt: Codable, Sendable {
        var titel: String
        var dauer: String
        var geplantMin: Int
        /// nur für erledigte Schritte
        var tatsaechlichMin: Int?
    }

    struct Backen: Codable, Sendable {
        var datum: String
        var name: String
        var mischung: String
        var anteile: [String: Int]
        var einstellungen: [String: Int]
        var teigTeilen: Bool
        var mengen: Mengen?
        var reifeGeplantMin: [Int]?
        var reifeTatsaechlichMin: Int?
        var schritte: [Schritt]?
        var bewertung: Int?
        var kriterien: [String: Int]?
        var notiz: String?
        var fruehereDiagnose: String?
    }

    var aktuell: Backen
    /// Frühere Einträge mit derselben Mischung (neueste zuerst)
    var frueher: [Backen]

    private static let tag: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM.yyyy"
        return f
    }()

    static func backen(_ e: Backeintrag, mitDiagnose: Bool) -> Backen {
        let w = e.werte
        let a = w.anteile
        let r = Rechner.rezept(w.eingabe)
        var schritte: [Schritt]?
        if let l = e.verlauf, l.schritte.count == r.schritte.count {
            schritte = zip(l.schritte, r.schritte).enumerated().map { i, p in
                Schritt(titel: p.1.titel, dauer: p.1.dauer, geplantMin: p.1.t,
                        tatsaechlichMin: i < l.offenAb ? Int(((p.0.at - l.start) / BackLauf.min).rounded()) : nil)
            }
        }
        let reife = e.reife
        var krit: [String: Int] = [:]
        for k in Kriterien.Art.allCases where e.kriterien[k] > 0 { krit[k.rawValue] = e.kriterien[k] }
        return Backen(
            datum: tag.string(from: e.gebacken), name: e.name,
            mischung: SauerteigDaten.mischung(w.mischung)?.name ?? "Eigene Mischung",
            anteile: Dictionary(uniqueKeysWithValues: Sorte.allCases.filter { a[$0] > 0 }.map { ($0.rawValue, a[$0]) }),
            einstellungen: Dictionary(uniqueKeysWithValues: Stellgroesse.allCases.map { ($0.rawValue, w[keyPath: $0.pfad]) }),
            teigTeilen: w.teigTeilen, mengen: e.mengen ?? Mengen(r),
            reifeGeplantMin: reife.geplant.map { [$0.0, $0.1] }, reifeTatsaechlichMin: reife.tatsaechlich,
            schritte: schritte, bewertung: e.bewertung > 0 ? e.bewertung : nil, kriterien: krit.isEmpty ? nil : krit,
            notiz: e.notiz.isEmpty ? nil : String(e.notiz.prefix(1000)),
            fruehereDiagnose: mitDiagnose ? e.analyse?.diagnose : nil)
    }

    /// Kontext zu `e`; dazu bis zu drei frühere Einträge mit derselben Mehlmischung.
    init(_ e: Backeintrag, alle: [Backeintrag]) {
        aktuell = Self.backen(e, mitDiagnose: false)
        frueher = alle.filter { $0.id != e.id && $0.gebacken < e.gebacken && $0.werte.anteile == e.werte.anteile }
            .prefix(3).map { Self.backen($0, mitDiagnose: true) }
    }
}

#if DEBUG && canImport(UIKit)
import SwiftUI

#Preview("Tagebuch") { Wurzel().vorschau(rezepte: true, tab: .tagebuch) }
#endif
