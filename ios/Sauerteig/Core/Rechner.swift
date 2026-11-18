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
    ]

    static func mischung(_ key: String) -> Mischung? { mischungen.first { $0.key == key } }

    static let tipps = [
        "Fingertest: Delle federt nur zur Hälfte zurück = fertig",
        "Bei viel Roggen: immer mit feuchten Händen arbeiten",
        "Lieber etwas früher als zu spät backen",
        "Klopftest: Fertiges Brot klingt hohl",
        "Nach dem Backen mindestens 2h auskühlen lassen",
        "Je höher der Roggen-Anteil, desto kompakter das Brot",
    ]
}

/// JavaScripts Math.round (halbe Werte zu +∞).
@inline(__always) func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

enum SchrittArt: String, Codable, Sendable { case ansetzen, autolyse, mischen, formen, ofen, backen, auskuehlen }

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
    var anstellgut: Int
    var sauerteigTemp: Int
    var gareTemp: Int
    var brotGroesse: Int
    var hydration: Int
    var anteile: Anteile
    var teigTeilen: Bool
    var ofenTemp: Int = 220
}

struct Berechnung: Sendable {
    var anstellgut, sauerteigMehl, sauerteigWasser, sauerteigGesamt: Int
    var gesamtMehl: Int
    var mehl: Anteile
    var hauptteigWasser, salz: Int
    var kuemmel: String
    var teiggewicht: Int
    var einzelGewicht: Double
    var hydration: Int
    var zeitplan: Zeitplan
    var ersteGare, stueckgare, backZeit: String
    var dampfMin, ofenTemp, anbackTemp: Int
    var autolyseZeit: String
    var mitAutolyse: Bool
    var tempHinweis: String
    var krume, geschmack, haltbarkeit: String
    var schritte: [Schritt]
    var gesamtDauer: Int
}

enum Rechner {
    static func optimaleHydration(_ a: Anteile) -> Int {
        jsRound(Double(a.roggen * 75 + a.dinkel * 78 + a.weizen * 72 + a.buchweizen * 85) / 100)
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

    static func zeitplan(_ temp: Int) -> Zeitplan {
        if temp <= 20 { return Zeitplan(sauerteigZeit: "10-12h", gareZeit: "90-120 Min") }
        if temp <= 24 { return Zeitplan(sauerteigZeit: "8-10h", gareZeit: "90-120 Min") }
        if temp <= 28 { return Zeitplan(sauerteigZeit: "6-8h", gareZeit: "70-90 Min") }
        return Zeitplan(sauerteigZeit: "4-6h", gareZeit: "50-70 Min")
    }

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
        let pattern = "([0-9]+)-([0-9]+)\\s*(h|Min)"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let a = Range(m.range(at: 1), in: t), let b = Range(m.range(at: 2), in: t), let u = Range(m.range(at: 3), in: t),
              let x = Int(t[a]), let y = Int(t[b]) else { return nil }
        let f = t[u] == "h" ? 60 : 1
        return (x * f, y * f)
    }

    private static func mitte(_ r: (Int, Int)) -> Int { jsRound(Double(r.0 + r.1) / 2) }

    /// Minuten → „h:mm“, auf 5 Minuten gerundet.
    static func hm(_ x: Int) -> String {
        let m = jsRound(Double(x) / 5) * 5
        return "\(m / 60):" + String(format: "%02d", m % 60)
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
        let sMehl = e.anstellgut * 2
        let sWasser = e.anstellgut * 2
        let sGesamt = e.anstellgut + sMehl + sWasser
        let skal = (Double(sGesamt) / 600) * (Double(e.brotGroesse) / 1200)
        let gesamtMehl = jsRound(360 * skal)
        var mehl = Anteile()
        for k in Sorte.allCases { mehl[k] = jsRound(Double(gesamtMehl * a[k]) / 100) }
        let mehlGesamt = sMehl + gesamtMehl
        let wasserZiel = jsRound(Double(mehlGesamt * e.hydration) / 100)
        let hauptWasser = max(0, wasserZiel - sWasser)
        let salz = jsRound(14 * skal)
        let kuemmel = String(format: "%.1f", 1.5 * skal)
        let teig = jsRound(Double(sGesamt + gesamtMehl + hauptWasser + salz))
        let hyd = jsRound(Double(sWasser + hauptWasser) / Double(mehlGesamt) * 100)
        let zp = zeitplan(e.sauerteigTemp)
        let ersteGare = zeitplan(22).gareZeit
        let einzel = e.teigTeilen ? Double(teig) / 2 : Double(teig)
        let ofen = e.ofenTemp
        let anback = min(250, ofen + 30)
        let basis: (Double, Double) = einzel <= 900 ? (22, 26) : einzel <= 1500 ? (28, 32) : (33, 38)
        let faktor = 1 + Double(220 - ofen) * 0.007
        let backZeit = "\(jsRound(basis.0 * faktor))-\(jsRound(basis.1 * faktor)) Min"
        let dampf = e.teigTeilen ? 10 : 15
        let sgBase: Double = a.roggen >= 80 ? 45 : a.roggen >= 60 ? 60 : 90
        let sgF: Double = e.gareTemp >= 28 ? 0.75 : e.gareTemp >= 24 ? 1.0 : 1.15
        let sgMin = jsRound(sgBase * sgF)
        let sgMax = jsRound((sgBase + 30) * sgF)
        let stueckgare = "\(sgMin)-\(sgMax) Min"
        let hinweis = e.sauerteigTemp < 20 ? "Kühl: längere Reifezeit" : e.sauerteigTemp > 28 ? "Warm: Vorsicht vor Überreife" : ""
        let autolyse = a.roggen >= 80 ? "— (entfällt bei Roggen)" : a.weizen >= 30 ? "60-90 Min" : "45-60 Min"
        let mitAutolyse = a.roggen < 80

        let bz = spanne(backZeit) ?? (0, 0)
        let tMischen = mitte(spanne(zp.sauerteigZeit) ?? (0, 0))
        let tFormen = tMischen + mitte(spanne(ersteGare) ?? (0, 0))
        let tBacken = tFormen + mitte((sgMin, sgMax))
        let tOfen = max(tFormen, tBacken - 35)
        let tAus = tBacken + dampf + mitte(bz)
        var s = [Schritt(t: 0, titel: "Sauerteig ansetzen", dauer: zp.sauerteigZeit, art: .ansetzen)]
        if mitAutolyse {
            s.append(Schritt(t: tMischen - mitte(spanne(autolyse) ?? (0, 0)), titel: "Autolyse ansetzen (vor Sauerteig-Reife)", dauer: autolyse, art: .autolyse))
        }
        let zugeben = (mehl.roggen > 0 ? "Roggenmehl, " : "") + "Sauerteig + Salz zugeben, erste Gare"
        s.append(Schritt(t: tMischen, titel: mitAutolyse ? zugeben : "Hauptteig mischen, erste Gare", dauer: ersteGare, art: .mischen))
        s.append(Schritt(t: tFormen, titel: "Formen, Stückgare", dauer: stueckgare, art: .formen))
        s.append(Schritt(t: tOfen, titel: "Ofen auf \(anback) °C vorheizen", dauer: "30-40 Min", art: .ofen))
        s.append(Schritt(t: tBacken, titel: "Backen", dauer: "\(bz.0 + dampf)-\(bz.1 + dampf) Min", art: .backen))
        s.append(Schritt(t: tAus, titel: "Auskühlen", dauer: "min. 2h", art: .auskuehlen))
        let (krume, geschmack, haltbarkeit) = eigenschaften(a)
        return Berechnung(anstellgut: e.anstellgut, sauerteigMehl: sMehl, sauerteigWasser: sWasser, sauerteigGesamt: sGesamt,
                          gesamtMehl: gesamtMehl, mehl: mehl, hauptteigWasser: hauptWasser, salz: salz, kuemmel: kuemmel,
                          teiggewicht: teig, einzelGewicht: einzel, hydration: hyd, zeitplan: zp, ersteGare: ersteGare,
                          stueckgare: stueckgare, backZeit: backZeit, dampfMin: dampf, ofenTemp: ofen, anbackTemp: anback,
                          autolyseZeit: autolyse, mitAutolyse: mitAutolyse, tempHinweis: hinweis,
                          krume: krume, geschmack: geschmack, haltbarkeit: haltbarkeit, schritte: s, gesamtDauer: tAus)
    }
}

/// Einstellungen am Rechner. Als Rezept gespeichert im Format der Web-App (`einstellungen`).
struct SauerteigWerte: Codable, Hashable, Sendable {
    var anstellgut = 120
    var sauerteigTemp = 22
    var gareTemp = 30
    var brotGroesse = 1200
    var hydration = Rechner.optimaleHydration(Anteile(roggen: 70, dinkel: 20, weizen: 10))
    var mischung = "roggen-optimal"
    var custom = Anteile(roggen: 70, dinkel: 20, weizen: 10)
    var teigTeilen = false
    var ofenTemp = 220

    var anteile: Anteile {
        mischung == "custom" ? custom : (SauerteigDaten.mischung(mischung)?.anteile ?? Anteile(roggen: 70, dinkel: 20, weizen: 10))
    }

    var eingabe: Eingabe {
        Eingabe(anstellgut: anstellgut, sauerteigTemp: sauerteigTemp, gareTemp: gareTemp, brotGroesse: brotGroesse,
                hydration: hydration, anteile: anteile, teigTeilen: teigTeilen, ofenTemp: ofenTemp)
    }

    /// `alsEinstellungen` der Web-App: Zahlen als Text, damit gespeicherte Rezepte zwischen Web und App gleich sind.
    var einstellungen: [String: Wert] {
        [
            "anstellgut": .text(String(anstellgut)), "sauerteigTemp": .text(String(sauerteigTemp)),
            "gareTemp": .text(String(gareTemp)), "brotGroesse": .text(String(brotGroesse)),
            "hydration": .text(String(hydration)), "mehlMischung": .text(mischung),
            "customRoggen": .text(String(custom.roggen)), "customDinkel": .text(String(custom.dinkel)),
            "customWeizen": .text(String(custom.weizen)), "customBuchweizen": .text(String(custom.buchweizen)),
            "teigTeilen": .bool(teigTeilen), "ofenTemp": .text(String(ofenTemp)),
        ]
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
    }
}
