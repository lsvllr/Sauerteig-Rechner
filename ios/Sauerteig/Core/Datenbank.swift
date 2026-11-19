import Foundation

// Lokale Datenbank (ios/LOCAL-FIRST.md, Abschnitt 3): Das Gerät hat alle Daten, die Datei auf dem Gerät ist die
// Wahrheit. Jede Zeile hat eine uid, jedes Feld die Zeit seiner letzten Änderung (hybride logische Uhr). Jede
// Schreiboperation erzeugt eine Änderung `{tabelle, uid, daten, geloescht, zeit}` und landet in „ausstehend“.
// Der Abgleich (App/Abgleich.swift, nur mit Konto und ab zwei Geräten) sendet diese Liste und spielt fremde
// Änderungen über `wende(_:)` ein; die Sicherung in iCloud (App/Sicherung.swift) nutzt dieselbe Zusammenführung.

/// Feldwert, wie er im JSON steht. Tolerant beim Lesen (Zahl als Text, Bool als 0/1).
enum Wert: Codable, Hashable, Sendable {
    case text(String)
    case zahl(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .zahl(d) }
        else { self = .text(try c.decode(String.self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .zahl(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }

    var text: String? {
        switch self {
        case .text(let s): return s
        case .zahl(let d): return d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return nil
        }
    }

    var zahl: Double? {
        switch self {
        case .zahl(let d): return d
        case .text(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        case .bool(let b): return b ? 1 : 0
        case .null: return nil
        }
    }

    var int: Int? { zahl.flatMap { $0.isFinite ? Int($0) : nil } }

    var bool: Bool? {
        switch self {
        case .bool(let b): return b
        case .zahl(let d): return d != 0
        case .text(let s): return s == "true" || s == "1"
        case .null: return nil
        }
    }

    /// Werte, die als Ganzes gelten müssen (Zeitplan, Einstellungen eines Rezepts), stehen als JSON-Text in einem Feld.
    static func json<T: Encodable>(_ v: T) -> Wert {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return .text((try? e.encode(v)).flatMap { String(data: $0, encoding: .utf8) } ?? "null")
    }

    func json<T: Decodable>(_ t: T.Type) -> T? {
        guard let s = text, let d = s.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(t, from: d)
    }
}

/// Eine Änderung für den Abgleich. Neue Zeile: alle Felder; geänderte: nur die geänderten; Löschen: `geloescht`.
struct Aenderung: Codable, Hashable, Sendable {
    var tabelle: String
    var uid: String
    var daten: [String: Wert]
    var geloescht: Bool
    var zeit: String
}

/// Zeile: Werte `d` und je Feld die Zeit der letzten Änderung `z`. Gelöscht = Feld `_geloescht` (bleibt als Marke
/// stehen, sonst käme die Zeile beim nächsten Abgleich zurück).
struct Zeile: Codable, Hashable, Sendable {
    var d: [String: Wert] = [:]
    var z: [String: String] = [:]

    static let loeschFeld = "_geloescht"
    var geloescht: Bool { d[Self.loeschFeld]?.bool == true }
    subscript(_ feld: String) -> Wert? { d[feld] }
}

/// Hybride logische Uhr: `<ms seit 1970, 13-stellig>-<Zähler, 4 hex>-<Gerät>`, als Text sortierbar. Geht nie hinter
/// die späteste gesehene Zeit zurück (auch fremde aus dem Abgleich); gleiche Millisekunde → Zähler + 1.
struct Uhr: Codable, Hashable, Sendable {
    var geraet: String
    var ms: Int64 = 0
    var zaehler: Int = 0

    static func neuesGeraet() -> String {
        "ios" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(16)
    }

    mutating func naechste(_ jetzt: Date = Date()) -> String {
        let t = Int64((jetzt.timeIntervalSince1970 * 1000).rounded(.down))
        if t > ms {
            ms = t
            zaehler = 0
        } else {
            zaehler += 1
        }
        return Self.text(ms, zaehler, geraet)
    }

    /// Fremde Zeit gesehen: die eigene Uhr zieht nach.
    mutating func sieh(_ zeit: String) {
        guard let (m, c) = Self.lies(zeit) else { return }
        if m > ms || (m == ms && c > zaehler) {
            ms = m
            zaehler = c
        }
    }

    static func text(_ ms: Int64, _ c: Int, _ geraet: String) -> String {
        // Interpolation statt String(format: "%d"): %d liest nur 32 Bit, ms-Zeiten würden falsch.
        let m = String(ms)
        let h = String(c, radix: 16)
        return String(repeating: "0", count: max(0, 13 - m.count)) + m + "-"
            + String(repeating: "0", count: max(0, 4 - h.count)) + h + "-" + geraet
    }

    static func lies(_ zeit: String) -> (Int64, Int)? {
        let teile = zeit.split(separator: "-", maxSplits: 2)
        guard teile.count == 3, let m = Int64(teile[0]), let c = Int(teile[1], radix: 16) else { return nil }
        return (m, c)
    }
}

/// Die Datenbank des Geräts. Eine JSON-Datei in Application Support, geschrieben nur bei Änderung. Reicht für
/// einige tausend Zeilen; erst bei viel mehr Daten auf SQLite wechseln (gleiches Protokoll).
@MainActor
final class Datenbank: ObservableObject {
    static let shared = Datenbank()

    private struct Datei: Codable {
        var tabellen: [String: [String: Zeile]] = [:]
        /// Ausstehende eigene Änderungen (noch nicht gesendet).
        var aus: [Aenderung] = []
        var uhr: Uhr
    }

    @Published private(set) var tabellen: [String: [String: Zeile]]
    private(set) var aus: [Aenderung]
    /// Nach jeder gespeicherten Änderung; `true`, wenn sie von außen kam (Abgleich, Sicherung).
    var beiAenderung: ((_ fremd: Bool) -> Void)?
    private var uhr: Uhr
    private let url: URL?

    /// `url == nil`: nur im Speicher (Tests, Vorschau).
    init(url: URL? = Datenbank.standardURL, geraet: String? = nil) {
        self.url = url
        let gelesen = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Datei.self, from: $0) }
        let g = geraet ?? Self.geraetKennung()
        tabellen = gelesen?.tabellen ?? [:]
        aus = gelesen?.aus ?? []
        uhr = gelesen?.uhr ?? Uhr(geraet: g)
    }

    nonisolated static var standardURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("daten.json")
    }

    /// Einmal zufällig erzeugt, in UserDefaults.
    private static func geraetKennung() -> String {
        let key = "geraet"
        if let g = UserDefaults.standard.string(forKey: key), g.count >= 8 { return g }
        let g = Uhr.neuesGeraet()
        UserDefaults.standard.set(g, forKey: key)
        return g
    }

    // MARK: Lesen

    func zeile(_ tabelle: String, _ uid: String) -> Zeile? {
        guard let z = tabellen[tabelle]?[uid], !z.geloescht else { return nil }
        return z
    }

    /// Nicht gelöschte Zeilen einer Tabelle.
    func zeilen(_ tabelle: String) -> [(uid: String, zeile: Zeile)] {
        (tabellen[tabelle] ?? [:]).filter { !$0.value.geloescht }.map { ($0.key, $0.value) }.sorted { $0.uid < $1.uid }
    }

    // MARK: Schreiben

    /// Felder einer Zeile setzen (neue Zeile: alle angegebenen Felder). Gleicher Wert zählt nicht. Eine gelöschte
    /// Zeile bleibt gelöscht.
    @discardableResult
    func schreibe(_ tabelle: String, _ uid: String, _ felder: [String: Wert], jetzt: Date = Date()) -> Aenderung? {
        let alt = tabellen[tabelle]?[uid]
        if alt?.geloescht == true { return nil }
        let geaendert = felder.filter { k, v in k != Zeile.loeschFeld && alt?.d[k] != v }
        guard !geaendert.isEmpty else { return nil }
        let a = Aenderung(tabelle: tabelle, uid: uid, daten: geaendert, geloescht: false, zeit: uhr.naechste(jetzt))
        wendeAn(a)
        merke(a)
        speichere()
        return a
    }

    @discardableResult
    func loesche(_ tabelle: String, _ uid: String, jetzt: Date = Date()) -> Aenderung? {
        guard let alt = tabellen[tabelle]?[uid], !alt.geloescht else { return nil }
        let a = Aenderung(tabelle: tabelle, uid: uid, daten: [:], geloescht: true, zeit: uhr.naechste(jetzt))
        wendeAn(a)
        merke(a)
        speichere()
        return a
    }

    /// Fremde Änderung aus dem Abgleich einspielen: je Feld gilt die spätere Zeit, gelöscht bleibt gelöscht.
    func wende(_ fremd: [Aenderung]) {
        guard !fremd.isEmpty else { return }
        let vorher = tabellen
        for a in fremd {
            uhr.sieh(a.zeit)
            wendeAn(a)
        }
        guard tabellen != vorher else { return }
        speichere(fremd: true)
    }

    /// Beim Server angekommen (oder nicht mehr nötig, weil beim Einstieg ohnehin alles gesendet wird).
    func quittiere(_ zeiten: Set<String>) {
        let n = aus.count
        aus.removeAll { zeiten.contains($0.zeit) }
        if aus.count != n { speichere(fremd: nil) }
    }

    /// Alles als Änderungen (Einstieg in einen Abgleich, Sicherung).
    func schnappschuss() -> [Aenderung] { Self.schnappschuss(tabellen) }

    /// Je Zeile gruppiert nach Feldzeit, damit die Zeiten erhalten bleiben; Löschmarken als `geloescht`.
    nonisolated static func schnappschuss(_ tabellen: [String: [String: Zeile]]) -> [Aenderung] {
        var out: [Aenderung] = []
        for (t, zeilen) in tabellen {
            for (uid, z) in zeilen {
                if z.geloescht {
                    if let zeit = z.z[Zeile.loeschFeld] { out.append(Aenderung(tabelle: t, uid: uid, daten: [:], geloescht: true, zeit: zeit)) }
                    continue
                }
                var jeZeit: [String: [String: Wert]] = [:]
                for (k, v) in z.d { if let zeit = z.z[k] { jeZeit[zeit, default: [:]][k] = v } }
                for (zeit, daten) in jeZeit { out.append(Aenderung(tabelle: t, uid: uid, daten: daten, geloescht: false, zeit: zeit)) }
            }
        }
        return out.sorted { $0.zeit < $1.zeit }
    }

    /// Inhalt für die Sicherung: nur die Tabellen (Uhr und „ausstehend“ gehören zum Gerät).
    func sicherung() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        return try? e.encode(tabellen)
    }

    /// Sicherung einspielen: wie fremde Änderungen, je Feld gewinnt die spätere Zeit.
    func uebernimmSicherung(_ d: Data) {
        guard let t = try? JSONDecoder().decode([String: [String: Zeile]].self, from: d) else { return }
        wende(Self.schnappschuss(t))
    }

    private func wendeAn(_ a: Aenderung) {
        var z = tabellen[a.tabelle]?[a.uid] ?? Zeile()
        if a.geloescht {
            z.d[Zeile.loeschFeld] = .bool(true)
            z.z[Zeile.loeschFeld] = max(z.z[Zeile.loeschFeld] ?? "", a.zeit)
        } else {
            for (k, v) in a.daten where k != Zeile.loeschFeld {
                if let t = z.z[k], t >= a.zeit { continue }
                z.d[k] = v
                z.z[k] = a.zeit
            }
        }
        tabellen[a.tabelle, default: [:]][a.uid] = z
    }

    /// In „ausstehend“ aufnehmen. Felder, die eine spätere eigene Änderung überschreibt, fallen aus den früheren
    /// heraus; Löschen ersetzt alles davor. So wächst die Liste ohne Senden höchstens auf ein Eintrag je Feld.
    private func merke(_ a: Aenderung) {
        if a.geloescht {
            aus.removeAll { $0.tabelle == a.tabelle && $0.uid == a.uid }
        } else {
            for i in aus.indices where aus[i].tabelle == a.tabelle && aus[i].uid == a.uid && !aus[i].geloescht {
                for k in a.daten.keys { aus[i].daten.removeValue(forKey: k) }
            }
            aus.removeAll { !$0.geloescht && $0.daten.isEmpty }
        }
        aus.append(a)
    }

    /// `fremd == nil`: keine Datenänderung (nur „ausstehend“), nicht melden.
    private func speichere(fremd: Bool? = false) {
        if let url, let d = try? JSONEncoder().encode(Datei(tabellen: tabellen, aus: aus, uhr: uhr)) {
            try? d.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        if let fremd { beiAenderung?(fremd) }
    }
}

#if DEBUG && canImport(UIKit)
import SwiftUI

/// Inhalt der Datenbank als Tabelle: jede Zeile mit ihren Feldern.
private struct DatenbankInhalt: View {
    @ObservedObject var db: Datenbank

    var body: some View {
        List {
            ForEach(db.tabellen.keys.sorted(), id: \.self) { t in
                Section(t) {
                    ForEach(db.zeilen(t), id: \.uid) { uid, z in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(uid).font(.caption.monospaced()).foregroundStyle(.secondary)
                            ForEach(z.d.keys.sorted(), id: \.self) { k in
                                Text("\(k): \(String(describing: z.d[k]!))").font(.caption2.monospaced()).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview("Datenbank · Beispieldaten") {
    DatenbankInhalt(db: Vorschau.datenbank(timer: .backen, fuettern: .ok, rezepte: true))
}
#endif
