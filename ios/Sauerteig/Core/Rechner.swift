import Foundation

// Rechenkern des Sauerteig-Rechners (Port von src/gemeinsam/daten.ts und rechner.ts, übernommen aus der Haushalt-App).
// Ergebnisse müssen denen der Web-App gleichen: gleiche Rundungen, gleiche Texte.

enum Sorte: String, CaseIterable, Codable, Sendable {
    case roggen, dinkel, weizen, buchweizen

    var name: String {
        switch self {
        case .roggen: return "Roggen"
        case .dinkel: return "Dinkel"
        case .weizen: return "Weizen"
        case .buchweizen: return "Buchweizen"
        }
    }

    var mehlName: String {
        switch self {
        case .roggen: return "Roggen-Vollkornmehl"
        case .dinkel: return "Dinkel-Vollkornmehl"
        case .weizen: return "Weizen-Vollkornmehl"
        case .buchweizen: return "Buchweizenmehl"
        }
    }
}

/// Mehl, mit dem das Anstellgut geführt und der Sauerteig angesetzt wird (wie SauerteigArt im Web).
enum SauerteigArt: String, CaseIterable, Codable, Sendable {
    case roggen, weizen, dinkel

    var sorte: Sorte {
        switch self {
        case .roggen: return .roggen
        case .weizen: return .weizen
        case .dinkel: return .dinkel
        }
    }
}

/// Verhältnis Anstellgut : Mehl : Wasser beim Ansetzen. Mehr Futter je Teil Anstellgut: weniger alte Säure, reift
/// länger, schmeckt milder; weniger Futter: schneller und kräftiger. Wie Verhaeltnis (Web).
enum Verhaeltnis: String, CaseIterable, Codable, Sendable {
    case kraeftig, normal, mild

    /// Teile Mehl (und Wasser) je Teil Anstellgut
    var futter: Int {
        switch self {
        case .kraeftig: return 1
        case .normal: return 2
        case .mild: return 5
        }
    }

    var name: String {
        switch self {
        case .kraeftig: return "Kräftig"
        case .normal: return "Normal"
        case .mild: return "Mild"
        }
    }

    /// „1 : 2 : 2“
    var text: String { "1 : \(futter) : \(futter)" }
}

struct Anteile: Codable, Hashable, Sendable {
    var roggen = 0
    var dinkel = 0
    var weizen = 0
    var buchweizen = 0

    subscript(s: Sorte) -> Int {
        get {
            switch s {
            case .roggen: return roggen
            case .dinkel: return dinkel
            case .weizen: return weizen
            case .buchweizen: return buchweizen
            }
        }
        set {
            switch s {
            case .roggen: roggen = newValue
            case .dinkel: dinkel = newValue
            case .weizen: weizen = newValue
            case .buchweizen: buchweizen = newValue
            }
        }
    }

    var summe: Int { roggen + dinkel + weizen + buchweizen }
}

struct Mischung: Sendable {
    var key: String
    var anteile: Anteile
    var name: String
    var beschreibung: String
    var eigenschaften: String
}

enum SauerteigDaten {
    static let mischungen: [Mischung] = [
        Mischung(key: "roggen-pur", anteile: Anteile(roggen: 100), name: "Reines Roggen", beschreibung: "Traditionell, kräftig, kompakt", eigenschaften: "Sehr kompakt, intensiver Geschmack"),
        Mischung(key: "roggen-optimal", anteile: Anteile(roggen: 70, dinkel: 20, weizen: 10), name: "Roggen Optimal", beschreibung: "Beste Balance: Geschmack + Lockerung", eigenschaften: "Ausgewogen, gut aufgehend"),
        Mischung(key: "roggen-dinkel", anteile: Anteile(roggen: 60, dinkel: 40), name: "Roggen-Dinkel", beschreibung: "Nussig, bekömmlich, lockerer", eigenschaften: "Nussiges Aroma, gute Verdaulichkeit"),
        Mischung(key: "roggen-weizen", anteile: Anteile(roggen: 70, weizen: 30), name: "Roggen-Weizen", beschreibung: "Luftig, mild, familienfreundlich", eigenschaften: "Sehr locker, milder Geschmack"),
        Mischung(key: "vollkorn-mix", anteile: Anteile(roggen: 50, dinkel: 30, weizen: 15, buchweizen: 5), name: "Vollkorn-Mix", beschreibung: "Komplex, nährstoffreich, herzhaft", eigenschaften: "Komplexer Geschmack, sehr nährstoffreich"),
        Mischung(key: "buchweizen-spezial", anteile: Anteile(roggen: 60, dinkel: 20, weizen: 5, buchweizen: 15), name: "Buchweizen Spezial", beschreibung: "Glutenfrei-Anteil, nussig, dunkel", eigenschaften: "Dunkle Farbe, erdiger Geschmack"),
        Mischung(key: "mild-luftig", anteile: Anteile(roggen: 40, dinkel: 30, weizen: 30), name: "Mild & Luftig", beschreibung: "Für Einsteiger, sehr locker", eigenschaften: "Sehr locker, mild, toast-geeignet"),
        Mischung(key: "power-vollkorn", anteile: Anteile(roggen: 45, dinkel: 25, weizen: 20, buchweizen: 10), name: "Power Vollkorn", beschreibung: "Maximum an Nährstoffen", eigenschaften: "Sehr nährstoffreich, kräftig"),
        // Weizenteige (Weizen und Dinkel ab 70 %): eigener Ablauf mit Kneten, Dehnen und Falten, Vorformen
        Mischung(key: "weizen-pur", anteile: Anteile(weizen: 100), name: "Reines Weizen", beschreibung: "Mild, saftig, kräftige Kruste", eigenschaften: "Locker, offene Krume, milder Geschmack"),
        Mischung(key: "weizen-dinkel", anteile: Anteile(dinkel: 40, weizen: 60), name: "Weizen-Dinkel", beschreibung: "Mild-nussig, locker", eigenschaften: "Locker, nussiges Aroma"),
        Mischung(key: "dinkel-pur", anteile: Anteile(dinkel: 100), name: "Reines Dinkel", beschreibung: "Nussig, bekömmlich, nur kurz kneten", eigenschaften: "Zart, nussig, etwas flacher als Weizen"),
        Mischung(key: "weizen-roggen", anteile: Anteile(roggen: 30, weizen: 70), name: "Weizen-Roggen", beschreibung: "Weizenbrot mit würziger Roggennote", eigenschaften: "Locker, kräftiger als reines Weizen"),
    ]

    static func mischung(_ key: String) -> Mischung? { mischungen.first { $0.key == key } }

    static let tipps = [
        "Fingertest: Delle federt nur zur Hälfte zurück = fertig",
        "Bei viel Roggen: immer mit feuchten Händen arbeiten",
        "Weizen und Dinkel: mit wenig Mehl formen und den Teig straff wirken",
        "Lieber etwas früher als zu spät backen",
        "Klopftest: Fertiges Brot klingt hohl",
        "Nach dem Backen mindestens 2h auskühlen lassen",
        "Je höher der Roggen-Anteil, desto kompakter das Brot",
        "Weizenteig kann geformt über Nacht im Kühlschrank gehen (8-14 h) und kommt kalt in den Ofen",
        "Anstellgut aus dem Kühlschrank 1–2 h vorher bei Zimmertemperatur stehen lassen",
        "Warmer Ort für die Gare: Backofen mit eingeschalteter Lampe hat ca. 30 °C",
    ]

    /// Erklärung zum Mehl des Sauerteigs (Roggen- oder Weizensauerteig); wie SAUERTEIG_MEHL_INFO (Web).
    static let mehlInfo = [
        "Roggen, Weizen oder Dinkel, je nach Sauerteig: das Mehl, mit dem du dein Anstellgut führst, am besten Vollkorn. Einstellen unter „Anstellgut“; vorgewählt ist das Hauptmehl des Brotes.",
        "Weizen- und Dinkelsauerteig reifen schneller und schmecken milder. Hat er sich verdoppelt, ist er reif: Dann gleich weiter, sonst wird er sauer und verliert Triebkraft.",
        "Bei Broten mit viel Roggen (ab etwa der Hälfte) besser Roggenmehl nehmen, auch für ein Weizen-Anstellgut. Roggen braucht die Säure des Sauerteigs, sonst wird die Krume klebrig.",
    ].joined(separator: "\n\n")
}

/// JavaScripts Math.round (halbe Werte zu +∞).
@inline(__always) func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

enum SchrittArt: String, Codable, Sendable { case ansetzen, autolyse, mischen, gare, formen, ofen, backen, auskuehlen }

struct Schritt: Hashable, Sendable {
    var t: Int // Minuten ab T
    var titel: String
    var dauer: String
    var art: SchrittArt?
}

struct Zeitplan: Hashable, Sendable {
    var sauerteigZeit: String
    var gareZeit: String
}

struct Eingabe: Sendable {
    var sauerteigTemp: Int
    var gareTemp: Int
    /// Gewünschtes Teiggewicht (g); daraus folgen alle Mengen, auch das Anstellgut
    var brotGroesse: Int
    var verhaeltnis: Verhaeltnis = .normal
    var hydration: Int
    var anteile: Anteile
    var teigTeilen: Bool
    var ofenTemp: Int = 220
    /// Anbacken mit Dampf (°C); nil = 250 (nie unter der Ofentemperatur)
    var anbackTemp: Int? = nil
    /// Mehl des Sauerteigs; nil = passend zum Brot (`Rechner.sauerteigArt`)
    var sauerteigArt: SauerteigArt? = nil
}

struct Berechnung: Sendable {
    var anstellgut, sauerteigMehl, sauerteigWasser, sauerteigGesamt: Int
    var gesamtMehl: Int
    var mehl: Anteile
    var hauptteigWasser, salz: Int
    var teiggewicht: Int
    var einzelGewicht: Double
    var hydration: Int
    var zeitplan: Zeitplan
    var verhaeltnis: Verhaeltnis
    /// Prozent des Mehls im Sauerteig
    var versaeuerung: Int
    var sauerteigArt: SauerteigArt
    /// Warnung, wenn der Sauerteig nicht zum Brot passt (viel Roggen, aber kein Roggensauerteig); sonst leer
    var sauerteigHinweis: String
    var ersteGare, stueckgare, backZeit: String
    /// Weizenteig: Minuten nach Beginn der ersten Gare zum Dehnen und Falten; sonst leer
    var faltZeiten: [Int]
    var vorheizen: String
    var dampfMin, ofenTemp, anbackTemp: Int
    var autolyseZeit: String
    var mitAutolyse: Bool
    /// Weizen und Dinkel ab 70 % (`Rechner.weizenTeig`): Kneten, Dehnen und Falten, Vorformen
    var weizenTeig: Bool
    var tempHinweis: String
    var krume, geschmack, haltbarkeit: String
    var schritte: [Schritt]
    var gesamtDauer: Int
}

enum Rechner {
    /// Hauptteig mischen und kneten, danach beginnt die erste Gare.
    static let hauptteigDauer = "10 Min"
    /// Weizenteig: vorformen und entspannen lassen, bevor straff geformt wird (Minuten, vor der Stückgare).
    static let vorformenMin = 20

    /// Weizenteig: Weizen und Dinkel ab 70 %. Bildet ein Klebergerüst, wird also geknetet, in der ersten Gare
    /// gedehnt und gefaltet, vorgeformt und straff geformt. Darunter gilt der Ablauf für Roggen- und Mischteige.
    /// Wie istWeizenTeig (Web).
    static func weizenTeig(_ a: Anteile) -> Bool { a.weizen + a.dinkel >= 70 }

    /// Erste Gare (Stockgare) eines Weizenteigs: länger als bei Roggen und abhängig von der Gare-Temperatur.
    /// Mit 20 % Versäuerung: warm um 28 °C 2-3 h, bei Raumtemperatur 4-6 h.
    static func stockgareWeizen(_ gareTemp: Int) -> String { gareTemp >= 28 ? "2-3h" : gareTemp >= 24 ? "3-4h" : "4-6h" }

    /// Titel der ersten Gare eines Weizenteigs; darin erinnert der Timer ans Dehnen und Falten (`faltZeiten`).
    static let gareFalten = "Erste Gare, dehnen und falten"

    /// Dehnen und Falten: Minuten nach Beginn der ersten Gare, alle 30 Min. 3 Mal, ab 3½ h Stockgare 4 Mal; danach
    /// ruht der Teig noch mindestens eine Stunde. Wie faltZeiten (Web).
    static func faltZeiten(_ ersteGare: String) -> [Int] {
        guard let s = spanne(ersteGare) else { return [] }
        return Double(s.0 + s.1) / 2 >= 210 ? [30, 60, 90, 120] : [30, 60, 90]
    }

    /// Vorheizen auf die Anbacktemperatur: heißer dauert länger (Stein oder Topf heizen mit).
    static func vorheizDauer(_ anback: Int) -> String { anback <= 250 ? "30-40 Min" : anback <= 300 ? "40-50 Min" : "50-60 Min" }
    /// Anbacken, wenn nichts gewählt ist. Fest, damit der Regler nicht mit der Ofentemperatur wandert.
    static let anbackStandard = 250
    /// Anbacktemperatur: gewählt oder `anbackStandard`, nie unter der Ofentemperatur.
    static func anbackTemp(ofen: Int, gewaehlt: Int?) -> Int { max(ofen, gewaehlt ?? anbackStandard) }

    /// Dampfphase in Minuten: 15 (zwei Brote 10) bei 250 °C, heißer kürzer, kühler länger, wie bei Pizza. Die Hitze
    /// wirkt mit dem Abstand zum Siedepunkt im Teig (T − 100), überproportional (hoch 1,5): 350 °C → 7 Min,
    /// 300 °C → 10 Min, 230 °C → 19 Min. Die Arbeit der Dampfphase bleibt so gleich, die Zeit danach ändert sich nicht.
    static func dampfMinuten(_ anback: Int, teigTeilen: Bool) -> Int {
        let basis = teigTeilen ? 10.0 : 15.0
        return max(3, jsRound(basis * pow(150 / Double(max(anback - 100, 50)), 1.5)))
    }

    static func optimaleHydration(_ a: Anteile) -> Int {
        // Vollkorn: Weizen nimmt viel Wasser auf und hält es im Kleber; Dinkel nimmt weniger auf, sein Kleber ist
        // schwächer, zu nass wird er klebrig und läuft breit. Wie berechneOptimaleHydration (Web).
        // Mit dem Anstellgut gerechnet; Roggen und Buchweizen deshalb 2 % mehr als früher ohne, damit der Teig gleich bleibt.
        jsRound(Double(a.roggen * 77 + a.dinkel * 72 + a.weizen * 77 + a.buchweizen * 87) / 100)
    }

    /// Auf 100 % in 5er-Schritten; nil, wenn alle 0 sind.
    static func normalisiere(_ w: Anteile) -> Anteile? {
        let s = Double(w.summe)
        guard s > 0 else { return nil }
        var n = Anteile()
        for k in Sorte.allCases { n[k] = jsRound(Double(w[k]) / s * 20) * 5 }
        let ns = n.summe
        if ns != 100 {
            var maxK = Sorte.roggen
            for k in Sorte.allCases where n[k] > n[maxK] { maxK = k }
            n[maxK] += 100 - ns
        }
        return n
    }

    /// Sauerteig passend zum Brot: das Mehl mit dem größten Anteil (Buchweizen zählt nicht); bei Gleichstand
    /// Roggen vor Weizen vor Dinkel. Wie sauerteigArtFuer (Web).
    static func sauerteigArt(_ a: Anteile) -> SauerteigArt {
        if a.roggen >= a.weizen && a.roggen >= a.dinkel { return .roggen }
        return a.weizen >= a.dinkel ? .weizen : .dinkel
    }

    /// Reifezeit des Sauerteigs je Sauerteig, Verhältnis und Temperatur (bis 20, bis 24, bis 28, darüber °C).
    /// 1 : 2 : 2 wie bisher; 1 : 1 : 1 reift etwa ein Drittel schneller, 1 : 5 : 5 rund die Hälfte länger. Weizen- und
    /// Dinkelsauerteig sind schneller als Roggensauerteig. Wie REIFE (Web).
    static func reife(_ art: SauerteigArt, _ v: Verhaeltnis) -> [String] {
        switch (art == .roggen, v) {
        case (true, .kraeftig): return ["7-9h", "5-7h", "4-5h", "3-4h"]
        case (true, .normal): return ["10-12h", "8-10h", "6-8h", "4-6h"]
        case (true, .mild): return ["14-16h", "11-14h", "8-10h", "6-8h"]
        case (false, .kraeftig): return ["5-7h", "4-5h", "3-4h", "2-3h"]
        case (false, .normal): return ["8-10h", "6-8h", "4-6h", "3-5h"]
        case (false, .mild): return ["11-14h", "8-10h", "6-8h", "5-6h"]
        }
    }

    /// Reifezeit des Sauerteigs und Gare nach Temperatur.
    static func zeitplan(_ temp: Int, _ art: SauerteigArt = .roggen, _ v: Verhaeltnis = .normal) -> Zeitplan {
        let stufe = temp <= 20 ? 0 : temp <= 24 ? 1 : temp <= 28 ? 2 : 3
        return Zeitplan(sauerteigZeit: reife(art, v)[stufe], gareZeit: ["90-120 Min", "90-120 Min", "70-90 Min", "50-70 Min"][stufe])
    }

    // Alle Mengen zählen das Anstellgut mit: Es ist halb Mehl, halb Wasser. Hydration, Versäuerung und Salz beziehen
    // sich auf das ganze Mehl einschließlich des Anstellguts (wie in der Literatur).

    /// Salz bezogen aufs ganze Mehl (wie bisher 14 g bei 660 g Mehl).
    static let salz = 0.021

    /// Versäuerung: Anteil des ganzen Mehls, der im Sauerteig steckt (mit dem Mehl des Anstellguts). Reines
    /// Roggenbrot (ab 90 % Roggen) traditionell 50 %, Roggen- und Mischteige 45 % (wie bisher). Weizenteig braucht
    /// weniger (üblich 10-30 %), sonst wird er sauer und der Kleber weich. Wie versaeuerung (Web).
    static func versaeuerung(_ a: Anteile) -> Double { weizenTeig(a) ? 0.2 : a.roggen >= 90 ? 0.5 : 0.45 }

    /// Rezepte von vor dem einstellbaren Verhältnis: Anstellgut und „Brotgröße“ ergaben zusammen das Teiggewicht,
    /// und die Hydration zählte das Anstellgut nicht mit. Teiggewicht (auf 100 g) und Hydration mit Anstellgut, damit
    /// der Teig gleich bleibt; dazu gehört das Verhältnis 1 : 2 : 2. Wie alteWerte (Web).
    static func alteWerte(anstellgut a: Int, brotGroesse b: Int, hydration h: Int) -> (brotGroesse: Int, hydration: Int) {
        let sMehl = a * 2
        let skal = (Double(a * 5) / 600) * (Double(b) / 1200)
        let hauptMehl = jsRound(360 * skal)
        let hauptWasser = max(0, jsRound(Double((sMehl + hauptMehl) * h) / 100) - sMehl)
        let teig = a + 2 * sMehl + hauptMehl + hauptWasser + jsRound(14 * skal)
        let halb = Double(a) / 2
        return (min(2000, max(600, jsRound(Double(teig) / 100) * 100)),
                jsRound((halb + Double(sMehl + hauptWasser)) / (halb + Double(sMehl + hauptMehl)) * 100))
    }

    /// Geschmack nach dem Verhältnis beim Ansetzen. Wie mitSaeure (Web).
    static func saeure(_ v: Verhaeltnis) -> String { v == .mild ? ", milde Säure" : v == .kraeftig ? ", kräftigere Säure" : "" }

    static func eigenschaften(_ a: Anteile) -> (String, String, String) {
        var krume: String, geschmack: String, haltbarkeit: String
        if a.roggen >= 80 {
            (krume, geschmack, haltbarkeit) = ("Sehr kompakt, dichte Krume", "Kräftig-säuerlich, traditionell", "5-7 Tage")
        } else if a.roggen >= 60 {
            (krume, geschmack, haltbarkeit) = ("Kompakt, mitteldichte Krume", "Mittel-kräftig, ausgewogen", "4-5 Tage")
        } else if a.roggen >= 40 {
            (krume, geschmack, haltbarkeit) = ("Ausgewogen, mittel-locker", "Mild-kräftig, harmonisch", "3-4 Tage")
        } else {
            (krume, geschmack, haltbarkeit) = ("Locker, luftige Krume", "Mild, leicht säuerlich", "2-3 Tage")
        }
        if a.buchweizen > 10 {
            krume += ", erdige Note"
            geschmack += ", nussig-erdig"
        }
        if a.weizen > 25, let r = krume.range(of: "kompakt") { krume.replaceSubrange(r, with: "lockerer") }
        return (krume, geschmack, haltbarkeit)
    }

    /// „8-10h“ / „45-60 Min“ → Minuten [min, max].
    static func spanne(_ t: String) -> (Int, Int)? {
        // Wie spanne() in src/gemeinsam/rechner.ts: auch ein Einzelwert („10 Min“), dann min = max.
        let pattern = "([0-9]+)(?:-([0-9]+))?\\s*(h|Min)"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let a = Range(m.range(at: 1), in: t), let u = Range(m.range(at: 3), in: t),
              let x = Int(t[a]) else { return nil }
        let y = Range(m.range(at: 2), in: t).flatMap { Int(t[$0]) } ?? x
        let f = t[u] == "h" ? 60 : 1
        return (x * f, y * f)
    }

    private static func mitte(_ r: (Int, Int)) -> Int { jsRound(Double(r.0 + r.1) / 2) }

    /// Minuten → „h:mm“, auf 5 Minuten gerundet.
    static func hm(_ x: Int) -> String {
        let m = jsRound(Double(x) / 5) * 5
        return "\(m / 60):" + String(format: "%02d", m % 60)
    }

    /// Minuten → „3h 15m“ (bzw. „3h“ / „45m“), auf 5 Minuten gerundet.
    static func hmKurz(_ x: Int) -> String {
        let m = jsRound(Double(x) / 5) * 5
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r)m" }
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }

    /// Dauer-Text → Minuten (Mitte der Spanne, auf 5 gerundet).
    static func dauerMinuten(_ d: String) -> Int {
        if let s = spanne(d) { return jsRound(Double(s.0 + s.1) / 10) * 5 }
        if let re = try? NSRegularExpression(pattern: "([0-9]+)\\s*h"),
           let m = re.firstMatch(in: d, range: NSRange(d.startIndex..., in: d)),
           let r = Range(m.range(at: 1), in: d), let h = Int(d[r]) { return h * 60 }
        return 0
    }

    static func rezept(_ e: Eingabe) -> Berechnung {
        let a = e.anteile
        // Ganzes Mehl aus dem Teiggewicht: Teig = Mehl × (1 + Hydration + Salz). Im Sauerteig steckt der Anteil v
        // davon, als Anstellgut (halb Mehl) und Futter: Mehl im Sauerteig = Anstellgut × (Futter + ½) = v × Mehl.
        let v = versaeuerung(a)
        let futter = e.verhaeltnis.futter
        let mehlGanz = jsRound(Double(e.brotGroesse) / (1 + Double(e.hydration) / 100 + Self.salz))
        let asg = jsRound(v * Double(mehlGanz) / (Double(futter) + 0.5))
        let imAsg = jsRound(Double(asg) / 2) // Mehl bzw. Wasser im Anstellgut
        let sMehl = asg * futter
        let sWasser = sMehl
        let sGesamt = asg + sMehl + sWasser
        let gesamtMehl = max(0, mehlGanz - imAsg - sMehl)
        var mehl = Anteile()
        for k in Sorte.allCases { mehl[k] = jsRound(Double(gesamtMehl * a[k]) / 100) }
        // Rundungsrest der Mehle (±1 g) zum Mehl mit dem größten Anteil (nur bei Anteilen mit 100 %). Wie im Web.
        if a.summe == 100 {
            var groesste = Sorte.roggen
            for k in Sorte.allCases where a[k] > a[groesste] { groesste = k }
            mehl[groesste] += gesamtMehl - mehl.summe
        }
        let wasserZiel = jsRound(Double(mehlGanz * e.hydration) / 100)
        let salz = jsRound(Double(mehlGanz) * Self.salz)
        // Rundungsreste (meist ±1 g) gleicht das Wasser im Hauptteig aus: Der Teig wiegt genau das gewählte Gewicht.
        let ohneWasser = sGesamt + gesamtMehl + salz
        let wasserRoh = max(0, wasserZiel - imAsg - sWasser)
        let hauptWasser = abs(e.brotGroesse - ohneWasser - wasserRoh) <= 5 ? e.brotGroesse - ohneWasser : wasserRoh
        let teig = ohneWasser + hauptWasser
        let hyd = jsRound(Double(imAsg + sWasser + hauptWasser) / Double(mehlGanz) * 100)
        let art = e.sauerteigArt ?? sauerteigArt(a)
        let zp = zeitplan(e.sauerteigTemp, art, e.verhaeltnis)
        let artHinweis = art != .roggen && a.roggen >= 50
            ? "Viel Roggen im Teig: Für den Sauerteig besser Roggenmehl nehmen, sonst wird die Krume klebrig." : ""
        let weizen = weizenTeig(a)
        // Roggen- und Mischteige: feste erste Gare. Reines Roggenbrot nur eine kurze Teigruhe (das Mehl quillt, gehen
        // soll es in der Stückgare). Weizenteige brauchen länger (Kleber reift, Dehnen und Falten).
        let ersteGare = weizen ? stockgareWeizen(e.gareTemp) : a.roggen >= 90 ? "30-45 Min" : "90-120 Min"
        let einzel = e.teigTeilen ? Double(teig) / 2 : Double(teig)
        let ofen = e.ofenTemp
        let anback = Self.anbackTemp(ofen: ofen, gewaehlt: e.anbackTemp)
        let basis: (Double, Double) = einzel <= 900 ? (22, 26) : einzel <= 1500 ? (28, 32) : (33, 38)
        let faktor = 1 + Double(220 - ofen) * 0.007
        let backZeit = "\(jsRound(basis.0 * faktor))-\(jsRound(basis.1 * faktor)) Min"
        let dampf = Self.dampfMinuten(anback, teigTeilen: e.teigTeilen)
        // Stückgare nach Brotart und Temperatur (Basis bei 24-27 °C). Reines Roggenbrot bis zu Rissen in der
        // Oberfläche (bei 25 °C etwa 1-1½ h), Weizenteig mit 20 % Versäuerung 1¼-1¾ h.
        let sgBase: Double = weizen ? 75 : a.roggen >= 60 ? 60 : 90
        let sgF: Double = e.gareTemp >= 28 ? 0.75 : e.gareTemp >= 24 ? 1.0 : 1.15
        let sgMin = jsRound(sgBase * sgF)
        let sgMax = jsRound((sgBase + 30) * sgF)
        let stueckgare = "\(sgMin)-\(sgMax) Min"
        let hinweis = e.sauerteigTemp < 20 ? "Kühl: längere Reifezeit" : e.sauerteigTemp > 28 ? "Warm: Vorsicht vor Überreife" : ""
        // Dinkel verträgt keine lange Autolyse (der Kleber wird weich), Weizen braucht länger.
        let autolyse = a.roggen >= 80 ? "— (entfällt bei Roggen)" : a.dinkel >= 70 ? "30-45 Min" : a.weizen >= 30 ? "60-90 Min" : "45-60 Min"
        let mitAutolyse = a.roggen < 80

        let bz = spanne(backZeit) ?? (0, 0)
        let tMischen = mitte(spanne(zp.sauerteigZeit) ?? (0, 0))
        let tGare = tMischen + mitte(spanne(Self.hauptteigDauer) ?? (0, 0))
        let tFormen = tGare + mitte(spanne(ersteGare) ?? (0, 0))
        // Der Ofen heizt während der Stückgare vor. Ist die kürzer als das Vorheizen, wartet das Backen auf den Ofen.
        let vorheizen = vorheizDauer(anback)
        let vh = mitte(spanne(vorheizen) ?? (0, 0))
        let tStueckEnde = tFormen + (weizen ? Self.vorformenMin : 0) + mitte((sgMin, sgMax))
        let tOfen = max(tFormen, tStueckEnde - vh)
        let tBacken = max(tStueckEnde, tOfen + vh)
        let tAus = tBacken + dampf + mitte(bz)
        var s = [Schritt(t: 0, titel: "Sauerteig ansetzen", dauer: zp.sauerteigZeit, art: .ansetzen)]
        if mitAutolyse {
            s.append(Schritt(t: tMischen - mitte(spanne(autolyse) ?? (0, 0)), titel: "Autolyse ansetzen (vor Sauerteig-Reife)", dauer: autolyse, art: .autolyse))
        }
        // Was genau dazukommt (Roggen erst nach der Autolyse), steht in der Anleitung des Schritts.
        s.append(Schritt(t: tMischen, titel: "Hauptteig", dauer: Self.hauptteigDauer, art: .mischen))
        s.append(Schritt(t: tGare, titel: weizen ? Self.gareFalten : "Erste Gare", dauer: ersteGare, art: .gare))
        s.append(Schritt(t: tFormen, titel: "Formen, Stückgare", dauer: stueckgare, art: .formen))
        // auf die volle Hitze der Dampfphase vorheizen
        s.append(Schritt(t: tOfen, titel: "Ofen auf \(anback) °C vorheizen", dauer: vorheizen, art: .ofen))
        s.append(Schritt(t: tBacken, titel: "Backen", dauer: "\(bz.0 + dampf)-\(bz.1 + dampf) Min", art: .backen))
        s.append(Schritt(t: tAus, titel: "Auskühlen", dauer: "min. 2h", art: .auskuehlen))
        let (krume, geschmack, haltbarkeit) = eigenschaften(a)
        return Berechnung(anstellgut: asg, sauerteigMehl: sMehl, sauerteigWasser: sWasser, sauerteigGesamt: sGesamt,
                          gesamtMehl: gesamtMehl, mehl: mehl, hauptteigWasser: hauptWasser, salz: salz,
                          teiggewicht: teig, einzelGewicht: einzel, hydration: hyd, zeitplan: zp,
                          verhaeltnis: e.verhaeltnis, versaeuerung: jsRound(v * 100), sauerteigArt: art, sauerteigHinweis: artHinweis, ersteGare: ersteGare,
                          stueckgare: stueckgare, backZeit: backZeit, faltZeiten: weizen ? faltZeiten(ersteGare) : [], vorheizen: vorheizen, dampfMin: dampf, ofenTemp: ofen, anbackTemp: anback,
                          autolyseZeit: autolyse, mitAutolyse: mitAutolyse, weizenTeig: weizen, tempHinweis: hinweis,
                          krume: krume, geschmack: geschmack + Self.saeure(e.verhaeltnis), haltbarkeit: haltbarkeit, schritte: s, gesamtDauer: tAus)
    }
}

/// Einstellungen am Rechner. Als Rezept gespeichert im Format der Web-App (`einstellungen`).
struct SauerteigWerte: Codable, Hashable, Sendable {
    /// Nur noch für alte Werte (vor dem einstellbaren Verhältnis): Damals ergab das Anstellgut mit `brotGroesse`
    /// das Teiggewicht (`migriert`). Heute rechnet der Rechner das Anstellgut aus.
    var anstellgut = 120
    var sauerteigTemp = 22
    var gareTemp = 30
    var brotGroesse = 1200
    var hydration = Rechner.optimaleHydration(Anteile(roggen: 70, dinkel: 20, weizen: 10))
    var mischung = "roggen-optimal"
    var custom = Anteile(roggen: 70, dinkel: 20, weizen: 10)
    var teigTeilen = false
    var ofenTemp = 220
    /// Gewählte Anbacktemperatur (Dampfphase); nil = automatisch (`Rechner.anbackTemp`). Optional, damit ältere
    /// gespeicherte Werte ohne dieses Feld lesbar bleiben.
    var anbackTempWahl: Int? = nil
    /// Gewähltes Mehl des Sauerteigs; nil = passend zum Brot. Optional wie `anbackTempWahl`.
    var sauerteigArtWahl: SauerteigArt? = nil
    /// Verhältnis beim Ansetzen. Optional, damit alte gespeicherte Werte lesbar bleiben; nil heißt alt (`migriert`).
    var verhaeltnisWahl: Verhaeltnis? = .normal

    var verhaeltnis: Verhaeltnis {
        get { verhaeltnisWahl ?? .normal }
        set { verhaeltnisWahl = newValue }
    }

    /// Alte Werte (ohne Verhältnis) umgerechnet: Teiggewicht und Hydration wie damals, Verhältnis 1 : 2 : 2.
    func migriert() -> SauerteigWerte {
        guard verhaeltnisWahl == nil else { return self }
        var w = self
        let alt = Rechner.alteWerte(anstellgut: anstellgut, brotGroesse: brotGroesse, hydration: hydration)
        w.brotGroesse = alt.brotGroesse
        w.hydration = alt.hydration
        w.anstellgut = SauerteigWerte().anstellgut
        w.verhaeltnisWahl = .normal
        return w
    }

    /// Mehl des Sauerteigs, zum Einstellen (setzt die Wahl).
    var sauerteigArt: SauerteigArt {
        get { sauerteigArtWahl ?? Rechner.sauerteigArt(anteile) }
        set { sauerteigArtWahl = newValue }
    }

    /// Anbacktemperatur, zum Einstellen (setzt die Wahl).
    var anbackTemp: Int {
        get { Rechner.anbackTemp(ofen: ofenTemp, gewaehlt: anbackTempWahl) }
        set { anbackTempWahl = newValue }
    }

    /// Stellung des Anbacken-Reglers: die Wahl selbst, nicht auf die Ofentemperatur angehoben. So bleibt der Regler
    /// stehen, wenn sich die Ofentemperatur ändert; nur die Anzeige (`anbackTemp`) zieht mit.
    var anbackRegler: Int {
        get { anbackTempWahl ?? Rechner.anbackStandard }
        set { anbackTempWahl = newValue }
    }

    var anteile: Anteile {
        mischung == "custom" ? custom : (SauerteigDaten.mischung(mischung)?.anteile ?? Anteile(roggen: 70, dinkel: 20, weizen: 10))
    }

    var eingabe: Eingabe {
        Eingabe(sauerteigTemp: sauerteigTemp, gareTemp: gareTemp, brotGroesse: brotGroesse, verhaeltnis: verhaeltnis,
                hydration: hydration, anteile: anteile, teigTeilen: teigTeilen, ofenTemp: ofenTemp, anbackTemp: anbackTempWahl,
                sauerteigArt: sauerteigArtWahl)
    }

    /// `alsEinstellungen` der Web-App: Zahlen als Text, damit gespeicherte Rezepte zwischen Web und App gleich sind.
    var einstellungen: [String: Wert] {
        var e: [String: Wert] = [
            "verhaeltnis": .text(verhaeltnis.rawValue), "sauerteigTemp": .text(String(sauerteigTemp)),
            "gareTemp": .text(String(gareTemp)), "brotGroesse": .text(String(brotGroesse)),
            "hydration": .text(String(hydration)), "mehlMischung": .text(mischung),
            "customRoggen": .text(String(custom.roggen)), "customDinkel": .text(String(custom.dinkel)),
            "customWeizen": .text(String(custom.weizen)), "customBuchweizen": .text(String(custom.buchweizen)),
            "teigTeilen": .bool(teigTeilen), "ofenTemp": .text(String(ofenTemp)),
        ]
        if let a = anbackTempWahl { e["anbackTemp"] = .text(String(a)) }
        if let s = sauerteigArtWahl { e["sauerteigArt"] = .text(s.rawValue) }
        return e
    }

    init() {}

    /// `ausEinstellungen` der Web-App, nachsichtig: fehlende oder falsche Werte → Standard.
    init(einstellungen e: [String: Wert]) {
        let d = SauerteigWerte()
        func n(_ k: String, _ def: Int) -> Int { e[k]?.int ?? def }
        anstellgut = n("anstellgut", d.anstellgut)
        sauerteigTemp = n("sauerteigTemp", d.sauerteigTemp)
        gareTemp = n("gareTemp", d.gareTemp)
        brotGroesse = n("brotGroesse", d.brotGroesse)
        hydration = n("hydration", d.hydration)
        let m = e["mehlMischung"]?.text ?? ""
        mischung = m == "custom" || SauerteigDaten.mischung(m) != nil ? m : d.mischung
        custom = Anteile(roggen: n("customRoggen", d.custom.roggen), dinkel: n("customDinkel", d.custom.dinkel),
                         weizen: n("customWeizen", d.custom.weizen), buchweizen: n("customBuchweizen", d.custom.buchweizen))
        teigTeilen = e["teigTeilen"]?.bool ?? false
        ofenTemp = n("ofenTemp", d.ofenTemp)
        anbackTempWahl = e["anbackTemp"]?.int
        sauerteigArtWahl = e["sauerteigArt"]?.text.flatMap(SauerteigArt.init(rawValue:))
        // Ohne Verhältnis: altes Rezept, Teiggewicht und Hydration umrechnen
        verhaeltnisWahl = e["verhaeltnis"]?.text.flatMap(Verhaeltnis.init(rawValue:))
        self = migriert()
    }
}

#if DEBUG && canImport(UIKit)
import SwiftUI

#Preview("Rechner") { HauptAnsicht().vorschau() }
#Preview("Anleitungen") {
    let r = Vorschau.rezept
    List(Array(r.schritte.enumerated()), id: \.offset) { _, s in
        VStack(alignment: .leading, spacing: 6) {
            Text(s.titel).font(.headline)
            Text("\(Rechner.hmKurz(s.t)) · \(s.dauer)").font(.caption).foregroundStyle(.secondary)
            Anleitung(art: s.art, r: r, w: Vorschau.werte)
        }
    }
}
#endif
