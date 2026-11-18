import Foundation

// Prüft den Kern ohne Simulator: Tools/pruefe_kern.sh
var fehler = 0
func pruefe(_ ok: Bool, _ was: String, line: Int = #line) {
    if !ok { fehler += 1; print("✗ Zeile \(line): \(was)") }
}

@MainActor func laufe() {
    // Uhr: sortierbar, monoton, zieht nach fremden Zeiten nach
    var u = Uhr(geraet: "iosaaaaaaaa")
    let t0 = Date(timeIntervalSince1970: 1_763_371_234.567)
    let a = u.naechste(t0), b = u.naechste(t0)
    pruefe(a == "1763371234567-0000-iosaaaaaaaa", "Format \(a)")
    pruefe(b > a && b.hasSuffix("-0001-iosaaaaaaaa"), "Zähler \(b)")
    u.sieh("1763371299999-0005-iosbbbbbbbb")
    pruefe(u.naechste(t0) == "1763371299999-0006-iosaaaaaaaa", "nach fremder Zeit")

    // Datenbank: nur geänderte Felder, je Feld spätere Zeit, gelöscht bleibt gelöscht
    let db = Datenbank(url: nil, geraet: "iostest0001")
    db.schreibe("rezept", "r1", ["name": .text("A"), "datum": .text("1")])
    pruefe(db.schreibe("rezept", "r1", ["name": .text("A")]) == nil, "gleicher Wert zählt nicht")
    db.schreibe("rezept", "r1", ["name": .text("B")])
    pruefe(db.aus.count == 2 && db.aus[0].daten.keys.sorted() == ["datum"], "ausstehend zusammengefasst: \(db.aus)")
    db.wende([Aenderung(tabelle: "rezept", uid: "r1", daten: ["name": .text("alt")], geloescht: false, zeit: "0000000000001-0000-iosx0000")])
    pruefe(db.zeile("rezept", "r1")?["name"] == .text("B"), "ältere fremde Änderung verliert")
    db.wende([Aenderung(tabelle: "rezept", uid: "r1", daten: ["name": .text("neu")], geloescht: false, zeit: "9999999999999-0000-iosx0000")])
    pruefe(db.zeile("rezept", "r1")?["name"] == .text("neu"), "spätere fremde Änderung gewinnt")
    db.loesche("rezept", "r1")
    pruefe(db.zeile("rezept", "r1") == nil && db.aus.last?.geloescht == true && db.aus.count == 1, "löschen")
    pruefe(db.schreibe("rezept", "r1", ["name": .text("X")]) == nil, "gelöscht bleibt gelöscht")

    // Rezept-Rundreise im Format der Web-App
    var w = SauerteigWerte(); w.mischung = "custom"; w.custom = Anteile(roggen: 50, dinkel: 50); w.teigTeilen = true; w.ofenTemp = 230
    db.speichereRezept("  Test  ", w)
    pruefe(db.rezepte.first?.name == "Test" && db.rezepte.first?.werte == w, "Rezept-Rundreise")

    // Back-Lauf: anlegen, abhaken, Tabelle, beenden
    let r = Rechner.rezept(SauerteigWerte().eingabe)
    let start = 1_763_371_200_000.0
    let l = BackLauf.neu(r.schritte, start: start, vorlauf: 10, reife: Rechner.spanne(r.zeitplan.sauerteigZeit)!)
    db.starteBacklauf(l)
    pruefe(db.backlauf?.lauf == l, "Lauf aus der Tabelle")
    let jetzt = l.schritte[1].at + 600_000
    let b1 = l.hakeAb(1, am: jetzt)
    pruefe(b1.phase == .backen && b1.weiter == 2 && b1.schritte[1].at == jetzt && b1.schritte.last!.at == l.schritte.last!.at + 600_000, "Backen beginnen verschiebt")
    pruefe(b1.hakeAb(4, am: jetzt) == b1, "Überspringen nur aus der Aktivität")
    pruefe(b1.hakeAb(4, am: jetzt, ueberspringen: true).weiter == 5, "Überspringen aus der Aktivität")
    pruefe(b1.meldungen(jetzt: jetzt).allSatisfy { $0.at > jetzt }, "nur künftige Meldungen")
    db.aendereBacklauf(db.backlauf!.uid, b1)
    pruefe(db.backlauf?.lauf == b1, "geänderter Lauf")
    let s = BackLive.stand(b1, jetzt: Date(timeIntervalSince1970: (jetzt + 1) / 1000))
    pruefe(s.zeiten.count == b1.schritte.count - 1 && s.aktuell == 0 && s.weiter == 1 && s.abhakbar(1) && !s.abhakbar(0), "ContentState \(s)")
    pruefe(s.laufend(Date(timeIntervalSince1970: s.zeiten[2] / 1000 + 1)) == 2, "Uhr schiebt weiter")
    let json = String(data: try! JSONEncoder().encode(BackAktivitaet.ContentState(zeiten: [1, 2], aktuell: 0)), encoding: .utf8)!
    let push = try? JSONDecoder().decode(BackAktivitaet.ContentState.self, from: Data(#"{"zeiten":[1763371200000,1763371800000],"aktuell":1}"#.utf8))
    pruefe(push?.aktuell == 1 && push?.weiter == nil, "Push-JSON des Weckdienstes lesbar (\(json))")
    db.beendeBacklauf()
    pruefe(db.backlauf == nil, "beendet")
    db.starteBacklauf(l)
    pruefe(db.backlauf?.lauf == l, "neuer Lauf nach Beenden")
}

MainActor.assumeIsolated { laufe() }
print(fehler == 0 ? "✓ Kern in Ordnung" : "\(fehler) Fehler")
exit(fehler == 0 ? 0 : 1)
