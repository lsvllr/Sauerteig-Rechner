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

    // Anbacken: Dampfphase je nach Temperatur
    pruefe(Rechner.dampfMinuten(250, teigTeilen: false) == 15 && Rechner.dampfMinuten(250, teigTeilen: true) == 10
           && Rechner.dampfMinuten(350, teigTeilen: false) == 7 && Rechner.dampfMinuten(230, teigTeilen: false) == 19, "Dampfminuten")
    var wa = SauerteigWerte(); wa.ofenTemp = 230
    pruefe(wa.anbackTemp == 250 && SauerteigWerte(einstellungen: wa.einstellungen).anbackTempWahl == nil, "Anbacken automatisch")
    wa.anbackTemp = 320
    let ra = Rechner.rezept(wa.eingabe)
    pruefe(ra.anbackTemp == 320 && ra.dampfMin == 8 && SauerteigWerte(einstellungen: wa.einstellungen).anbackTemp == 320
           && ra.schritte.contains { $0.titel == "Ofen auf 320 °C vorheizen" }, "Anbacken gewählt: \(ra.dampfMin) Min")
    let altWerte = try? JSONDecoder().decode(SauerteigWerte.self, from: JSONEncoder().encode(SauerteigWerte()))
    pruefe(altWerte != nil, "gespeicherte Werte ohne Anbacktemperatur lesbar")
    // Weizenteig (Weizen + Dinkel ab 70 %): Stockgare nach Gare-Temperatur, Vorformen vor der Stückgare
    var ww = SauerteigWerte(); ww.mischung = "weizen-pur"
    let rw = Rechner.rezept(ww.eingabe)
    let r0 = Rechner.rezept(SauerteigWerte().eingabe)
    pruefe(rw.weizenTeig && rw.ersteGare == "2-3h" && rw.schritte[3].titel == "Erste Gare, dehnen und falten"
           && rw.stueckgare == "56-79 Min" && rw.schritte[6].t == 668 && rw.gesamtDauer == 713, "Weizenteig-Ablauf: \(rw.schritte)")
    // Sauerteig passend zum Brot, änderbar; Weizensauerteig reift schneller
    pruefe(rw.sauerteigArt == .weizen && rw.zeitplan.sauerteigZeit == "6-8h" && rw.sauerteigHinweis.isEmpty, "Weizensauerteig zum Weizenbrot")
    var wr = SauerteigWerte()
    pruefe(wr.sauerteigArt == .roggen && Rechner.rezept(wr.eingabe).zeitplan.sauerteigZeit == "8-10h", "Roggensauerteig zum Roggenbrot")
    wr.sauerteigArt = .weizen
    let rr = Rechner.rezept(wr.eingabe)
    pruefe(rr.sauerteigArt == .weizen && !rr.sauerteigHinweis.isEmpty
           && SauerteigWerte(einstellungen: wr.einstellungen).sauerteigArtWahl == .weizen
           && SauerteigWerte(einstellungen: SauerteigWerte().einstellungen).sauerteigArtWahl == nil, "Sauerteig gewählt, Rundreise")
    // Dehnen und Falten: Zeiten aus der Stockgare, Erinnerungen in der laufenden Gare
    pruefe(rw.faltZeiten == [30, 60, 90] && Rechner.faltZeiten("4-5h") == [30, 60, 90, 120] && r0.faltZeiten.isEmpty, "Faltzeiten")
    let s0 = 1_763_371_200_000.0, m = BackLauf.min
    let lw = BackLauf.neu(rw.schritte, start: s0, vorlauf: 0, reife: Rechner.spanne(rw.zeitplan.sauerteigZeit)!)
    let tg = s0 + 430 * m
    let lw3 = lw.hakeAb(1, am: s0 + 345 * m).erledige(1, am: s0 + 420 * m).erledige(2, am: tg)
    let falten = lw3.meldungen(jetzt: tg).filter { $0.id.hasPrefix("3:falten") }
    pruefe(lw3.laufend == 3 && falten.map(\.at) == [tg + 30 * m, tg + 60 * m, tg + 90 * m]
           && falten.last?.titel == "Dehnen und falten (3 von 3)", "Falten-Mitteilungen: \(falten)")
    // Vorheizen: heißer länger; ist die Stückgare kürzer, wartet das Backen auf den Ofen
    var wh = SauerteigWerte(); wh.mischung = "roggen-pur"; wh.gareTemp = 32; wh.anbackTemp = 350
    let rh = Rechner.rezept(wh.eingabe)
    pruefe(rh.vorheizen == "50-60 Min" && rh.schritte[3].t == 588 && rh.schritte[4].t == 590 && rh.schritte[5].t == 645
           && rh.ersteGare == "30-45 Min"
           && r0.vorheizen == "30-40 Min", "Vorheizen: \(rh.schritte)")
    pruefe(Rechner.sauerteigArt(Anteile(roggen: 30, weizen: 70)) == .weizen && Rechner.sauerteigArt(Anteile(dinkel: 100)) == .dinkel
           && Rechner.sauerteigArt(Anteile(roggen: 40, dinkel: 30, weizen: 30)) == .roggen, "Sauerteig nach Hauptmehl")
    ww.gareTemp = 22
    pruefe(Rechner.rezept(ww.eingabe).ersteGare == "4-6h", "Stockgare kühl länger")
    // Teiggewicht → Anstellgut je Verhältnis (Versäuerung 45 %, mit Anstellgut gerechnet); Reife nach Verhältnis
    var wt = SauerteigWerte(); wt.brotGroesse = 1500
    let mengen = Verhaeltnis.allCases.map { v -> [Int] in
        wt.verhaeltnis = v
        let x = Rechner.rezept(wt.eingabe)
        return [x.anstellgut, x.sauerteigMehl, x.teiggewicht, x.hydration]
    }
    pruefe(mengen == [[253, 253, 1499, 76], [152, 304, 1500, 76], [69, 345, 1499, 76]], "Mengen je Verhältnis: \(mengen)")
    wt.verhaeltnis = .mild
    pruefe(Rechner.rezept(wt.eingabe).zeitplan.sauerteigZeit == "11-14h" && Rechner.rezept(wt.eingabe).geschmack.hasSuffix("milde Säure"), "mild reift länger")
    // Alte Rezepte (ohne Verhältnis): Teiggewicht und Hydration wie damals
    var altE = SauerteigWerte().einstellungen
    altE["verhaeltnis"] = nil; altE["anstellgut"] = .text("60"); altE["brotGroesse"] = .text("1200"); altE["hydration"] = .text("75")
    let altW = SauerteigWerte(einstellungen: altE)
    pruefe(altW.brotGroesse == 600 && altW.hydration == 77 && altW.verhaeltnisWahl == .normal
           && Rechner.alteWerte(anstellgut: 120, brotGroesse: 1200, hydration: 75).brotGroesse == 1200
           && Rechner.alteWerte(anstellgut: 120, brotGroesse: 1200, hydration: 75).hydration == 77, "altes Rezept umgerechnet")
    var altJ = SauerteigWerte(); altJ.verhaeltnisWahl = nil; altJ.anstellgut = 120; altJ.hydration = 75
    let altD = try? JSONDecoder().decode(SauerteigWerte.self, from: JSONEncoder().encode(altJ))
    pruefe(altD?.verhaeltnisWahl == nil && altD?.migriert().brotGroesse == 1200 && altD?.migriert().hydration == 77, "alte gespeicherte Werte umgerechnet")
    ww.mischung = "dinkel-pur"
    pruefe(Rechner.rezept(ww.eingabe).autolyseZeit == "30-45 Min", "Dinkel: kurze Autolyse")
    pruefe(!Rechner.weizenTeig(Anteile(roggen: 40, dinkel: 30, weizen: 30)) && Rechner.weizenTeig(Anteile(roggen: 30, weizen: 70))
           && !r0.weizenTeig && r0.schritte[3].titel == "Erste Gare", "Roggen- und Mischteige wie bisher")
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
    // Standard-Rezept: 0 ansetzen, 1 Autolyse, 2 Hauptteig, 3 Erste Gare, 4 Formen, 5 Ofen, 6 Backen, 7 Auskühlen
    pruefe(l.startbar(1) && l.starte(1, am: jetzt) == b1 && b1.mitStart(1), "Autolyse starten = Backen beginnen")
    pruefe(l.meldungen(jetzt: start).first?.titel.hasPrefix("Jetzt: Autolyse") == true, "Meldung: Autolyse starten")
    pruefe(b1.laufend == 1 && b1.mitStart(5) && !b1.abhakbar(4) && b1.abhakbar(5) && !b1.abhakbar(7), "laufend, mitStart, abhakbar")
    pruefe(b1.erledige(2, am: jetzt) == b1, "noch nicht begonnener Schritt lässt sich nicht erledigen")
    let t2 = jetzt + 3_000_000, t3 = t2 + 900_000, t4 = t3 + 6_000_000, tOfen = t4 + 1_200_000, t5 = tOfen + 2_100_000
    let b2 = b1.erledige(1, am: t2)
    let b3 = b2.erledige(2, am: t3)
    pruefe(b3.laufend == 3 && b3.schritte[3].at == t3 && b3.schritte[2].at == t2, "Hauptteig erledigt: Gare beginnt sofort")
    pruefe(b3.naechster(t3 + 60_000 * 600) == -1 && b3.laufend == 3, "Zeit um: kein Weiterschalten ohne Abhaken")
    pruefe(b3.starte(5, am: t3) == b3, "Ofen erst während der Stückgare startbar")
    let b4 = b3.erledige(3, am: t4)
    pruefe(b4.laufend == 4 && b4.weiter == 5 && b4.erledige(4, am: t5) == b4, "Stückgare hat kein Erledigt")
    pruefe(b4.meldungen(jetzt: t4, vorlauf: 0).map(\.id) == ["5:jetzt"], "Meldung: Ofen starten")
    let b4o = b4.starte(5, am: tOfen)
    pruefe(b4o.laufend == 5 && b4o.schritte[5].at == tOfen && b4o.schritte[6].at - tOfen == b4.schritte[6].at - b4.schritte[5].at,
           "Ofen gestartet: Stückgare endet, Backen rückt mit")
    pruefe(b4o.meldungen(jetzt: tOfen, vorlauf: 0).map(\.id) == ["6:jetzt"], "nach dem Ofenstart nur noch Backen")
    let b5 = b4o.erledige(5, am: t5)
    pruefe(b5.laufend == 6 && b5.schritte[6].at == t5 && !b5.fertig, "Vorheizen erledigt: Backen beginnt")
    pruefe(b5.erledige(6, am: t5 + 2_700_000).fertig, "Backen erledigt: fertig")
    // Backen in zwei Stufen (mit Dampf, dann ohne)
    var b5d = b5; b5d.dampf = BackAktivitaet.Dampf(min: 15, heiss: 250, temp: 220)
    var b4d = b4o; b4d.dampf = b5d.dampf
    pruefe(b5d.dampfEnde == t5 + 15 * 60_000 && b4d.dampfEnde == nil, "Dampf-Stufe nur beim Backen")
    pruefe(b5d.meldungen(jetzt: t5, vorlauf: 0).map(\.id) == ["7:jetzt", "6:dampf"], "Meldung: Dampf raus")
    let sd = BackLive.stand(b5d)
    pruefe(sd.dampf == b5d.dampf && sd.ziel(Date(timeIntervalSince1970: t5 / 1000)) == sd.dampfEnde
           && sd.ziel(Date(timeIntervalSince1970: (t5 + 20 * 60_000) / 1000)) == sd.datum(sd.laufend + 1), "ContentState: Countdown bis zum Wechsel, dann bis zum Ende")
    pruefe(BackLive.stand(b4d).dampf == nil, "ContentState ohne Dampf vor dem Backen")
    let s = BackLive.stand(b4)
    pruefe(s.zeiten.count == b4.schritte.count - 1 && s.aktuell == 3 && s.weiter == 4 && s.naechster(nach: 3) == 4 && s.naechster(nach: 6) == nil, "ContentState \(s)")
    let json = String(data: try! JSONEncoder().encode(BackAktivitaet.ContentState(zeiten: [1, 2], aktuell: 0)), encoding: .utf8)!
    let alt = try? JSONDecoder().decode(BackAktivitaet.ContentState.self, from: Data(#"{"zeiten":[1763371200000,1763371800000],"aktuell":1,"neben":[4]}"#.utf8))
    pruefe(alt?.aktuell == 1 && alt?.weiter == nil, "älterer Stand lesbar (\(json))")
    db.beendeBacklauf()
    pruefe(db.backlauf == nil, "beendet")
    db.starteBacklauf(l)
    pruefe(db.backlauf?.lauf == l, "neuer Lauf nach Beenden")

    // Abgleich: Schnappschuss behält Feldzeiten und Löschmarken; ein zweites Gerät kommt auf denselben Stand
    let snap = db.schnappschuss()
    pruefe(snap.contains { $0.geloescht } && snap == snap.sorted { $0.zeit < $1.zeit }, "Schnappschuss mit Löschmarken, sortiert")
    let db2 = Datenbank(url: nil, geraet: "iostest0002")
    db2.wende(snap)
    let sichtbar = { (d: Datenbank) in d.tabellen.mapValues { $0.filter { !$0.value.geloescht } } }
    let geloescht = { (d: Datenbank) in d.tabellen.flatMap { t, z in z.filter { $0.value.geloescht }.map { "\(t)/\($0.key)" } }.sorted() }
    pruefe(sichtbar(db2) == sichtbar(db) && geloescht(db2) == geloescht(db) && db2.aus.isEmpty, "zweites Gerät gleich, nichts ausstehend")
    var gemeldet: [Bool] = []
    db2.beiAenderung = { gemeldet.append($0) }
    db2.wende(snap)
    pruefe(gemeldet.isEmpty, "gleicher Stand meldet keine Änderung")
    db2.schreibe("rezept", "r9", ["name": .text("Neu")])
    pruefe(gemeldet == [false] && db2.aus.count == 1, "eigene Änderung gemeldet")
    db2.quittiere(Set(db2.aus.map(\.zeit)))
    pruefe(db2.aus.isEmpty && gemeldet == [false], "quittiert, ohne Meldung")

    // Sicherung: Rundreise und Zusammenführen mit neuerem lokalen Stand
    let frisch = Datenbank(url: nil, geraet: "iostest0003")
    frisch.uebernimmSicherung(db2.sicherung()!)
    pruefe(frisch.tabellen == db2.tabellen, "Sicherung eingespielt")
    frisch.schreibe("rezept", "r9", ["name": .text("Später")])
    frisch.uebernimmSicherung(db2.sicherung()!)
    pruefe(frisch.zeile("rezept", "r9")?["name"] == .text("Später"), "neuere lokale Änderung bleibt")

    // Verschlüsselung: Vektoren aus der Web-App (src/schluessel.ts), Schlüssel = Bytes 0…31
    let k = Data((0..<32).map { UInt8($0) })
    pruefe(Verschluesselung.kennung(k) == "630dcd2966c43366", "Kennung wie im Web")
    let webA = Aenderung(tabelle: "rezept", uid: "u1", daten: ["x": .text("rNW/JhdQNydIRLDWwZrknSz1kCig1XNxbi2fGm3c6CSJodLhwYV2Ls4+jT9UG6ftzvU8kj7Pwj4UmsZUUSKgzHj4v96rEA==")], geloescht: false, zeit: "1763371234567-0000-webaaaaaaaa")
    let klar = Verschluesselung.entschluessele(k, webA)
    pruefe(klar?.daten == ["name": .text("Brot ä"), "n": .zahl(2), "b": .bool(true), "z": .null], "Web-Änderung lesbar: \(String(describing: klar))")
    var umgehaengt = webA; umgehaengt.uid = "u2"
    pruefe(Verschluesselung.entschluessele(k, umgehaengt) == nil, "uid an den Inhalt gebunden")
    pruefe(Verschluesselung.entpacke("MyHNhqd/9iOmWycb3fnZjOU+lE4qxtQkhvCENgM6UnRAq24UFvuQs3pzkWuNeyiTT4ae0MRC1cUZEdosHEMpJPIzy185CIcIgo3NbQ==", geheim: "JKMNPQRS") == k, "Web-Gerätecode entpackt")
    let eigen = try! Verschluesselung.verschluessele(k, Aenderung(tabelle: "profil", uid: "p", daten: ["a": .zahl(1.5)], geloescht: false, zeit: "1763371234567-0001-iosaaaaaaaa"))
    pruefe(Verschluesselung.entschluessele(k, eigen)?.daten == ["a": .zahl(1.5)], "Rundreise iOS")
    pruefe(Verschluesselung.entschluessele(Verschluesselung.neuerSchluessel(), eigen) == nil, "falscher Schlüssel")
    let blob = try! Verschluesselung.verpacke(k, geheim: "ABCDEFGH")
    pruefe(Verschluesselung.entpacke(blob, geheim: "ABCDEFGH") == k && Verschluesselung.entpacke(blob, geheim: "ABCDEFGJ") == nil, "Gerätecode iOS")
    let teile = Verschluesselung.zerlegeCode("abcd-efgh jkmn-pqrs")
    pruefe(teile.server == "ABCDEFGH" && teile.geheim == "JKMNPQRS" && Verschluesselung.zeigeCode("ABCD-EFGH", "JKMNPQRS") == "ABCD-EFGH-JKMN-PQRS", "Code zerlegen")
    pruefe(Verschluesselung.zerlegeCode("ABCD-EFGH").geheim == nil, "Admin-Code ohne Geheimnis")

    // Tagebuch: Name aus der Mischung, Rezepte übernehmen, fertiger Lauf → Eintrag, Vorschläge der KI
    var wc = SauerteigWerte(); wc.mischung = "custom"; wc.custom = Anteile(roggen: 40, dinkel: 60)
    pruefe(Backeintrag.automatischerName(SauerteigWerte()) == "Roggen Optimal", "Name aus Mischung")
    pruefe(Backeintrag.automatischerName(wc) == "Dinkel 60 % · Roggen 40 %", "Name eigene Mischung: \(Backeintrag.automatischerName(wc))")
    let tb = Datenbank(url: nil, geraet: "iostest0003")
    tb.speichereRezept("Altes Brot", wc)
    tb.uebernimmRezepte()
    tb.uebernimmRezepte()
    pruefe(tb.backeintraege.count == 1 && tb.backeintraege.first?.name == "Altes Brot" && tb.backeintraege.first?.werte == wc, "Rezept übernommen, einmal")
    tb.loescheEintrag(tb.backeintraege[0].id)
    tb.uebernimmRezepte()
    pruefe(tb.backeintraege.isEmpty && tb.rezepte.isEmpty, "gelöschter Eintrag kommt nicht zurück")
    let uid = tb.legeEintragAn(wc, name: "Dinkel 60 % · Roggen 40 %")
    pruefe(tb.backeintrag(uid)?.eigenerName == "", "automatischer Name wird nicht gespeichert")
    tb.benenneEintrag(uid, "  Sonntagsbrot ")
    pruefe(tb.backeintrag(uid)?.name == "Sonntagsbrot", "umbenennen")
    // mit Autolyse: Reife zählt bis zum Ende der Autolyse (Beginn des Hauptteigs)
    let lt = BackLauf.neu(r.schritte, start: 1_000_000, vorlauf: 10, reife: (480, 600))
        .starte(BackLauf.beginn, am: 1_000_000 + 480 * 60_000).erledige(BackLauf.beginn, am: 1_000_000 + 540 * 60_000)
    tb.starteBacklauf(lt, einstellungen: wc)
    let lu = tb.backlauf!.uid
    pruefe(tb.eintragAusLauf(lu, lt, jetzt: lt.schritte[3].at) == nil, "nicht fertig: kein Eintrag")
    let ende = (lt.schritte.last?.at ?? 0) + 1
    pruefe(tb.eintragAusLauf(lu, lt, jetzt: ende) == lu && tb.eintragAusLauf(lu, lt, jetzt: ende) == lu, "fertig: Eintrag mit uid des Laufs, einmal")
    let eb = tb.backeintrag(lu)
    pruefe(eb?.werte == wc && eb?.verlauf == lt && eb?.reife.tatsaechlich == 540 && eb?.reife.geplant != nil, "Eintrag aus Lauf: \(String(describing: eb?.reife))")
    pruefe(KIKontext(eb!, alle: tb.backeintraege).aktuell.schritte?[BackLauf.beginn + 1].tatsaechlichMin == 540, "Kontext: tatsächliche Zeit")
    // Alter Eintrag (abgehakt = Ende des Schritts): Zeiten wandern einen Schritt weiter
    let m = 60_000.0, tAlt = 1_000_000 + 480 * m
    let altLauf = BackLauf.neu(r.schritte, start: 1_000_000, vorlauf: 10, reife: (480, 600))
        .hakeAb(1, am: tAlt).hakeAb(2, am: tAlt + 60 * m).hakeAb(3, am: tAlt + 180 * m)
    let neuLauf = altLauf.ausAltemModell()
    pruefe(neuLauf.schritte[1].at == tAlt && neuLauf.schritte[2].at == tAlt + 50 * m && neuLauf.schritte[3].at == tAlt + 60 * m
           && neuLauf.schritte[4].at == tAlt + 180 * m && neuLauf.offenAb == 5, "alter Verlauf umgerechnet")
    tb.schreibe(Datenbank.eintragTabelle, "alt1", ["einstellungen": .json(wc.einstellungen), "verlauf": .json(altLauf)])
    pruefe(tb.backeintrag("alt1")?.verlauf == neuLauf, "alter Eintrag wird beim Lesen umgerechnet")
    pruefe(tb.backeintrag(lu)?.verlauf == lt, "neuer Eintrag bleibt")
    tb.loescheEintrag("alt1")
    let vs = [KrumenAnalyse.Vorschlag(parameter: "gareTemp", aenderung: 2.4, text: "", grund: ""),
              KrumenAnalyse.Vorschlag(parameter: "ofenTemp", aenderung: 7, text: "", grund: ""),
              KrumenAnalyse.Vorschlag(parameter: "hydration", aenderung: 40, text: "", grund: ""),
              KrumenAnalyse.Vorschlag(parameter: "", aenderung: 0, text: "Fingerprobe", grund: "")]
    let wv = SauerteigWerte().mitVorschlaegen(vs)
    pruefe(wv.gareTemp == 32 && wv.ofenTemp == 225 && wv.hydration == 85 && wv.brotGroesse == SauerteigWerte().brotGroesse, "Vorschläge: gerundet und begrenzt")

    // Füttern: Stand des Glases (ruhig → gelb am Fälligkeitstag → rot ab 2 Tagen drüber)
    let cal = Calendar.current
    let heute = cal.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
    func vor(_ t: Int) -> Fuetterung { Fuetterung(zuletzt: cal.date(byAdding: .day, value: -t, to: heute), intervall: 7) }
    pruefe(Fuetterung(zuletzt: nil, intervall: 7).stand(heute: heute) == .ruhig, "nie gefüttert: ruhig")
    pruefe(vor(6).stand(heute: heute) == .ruhig && vor(6).restTage(heute: heute) == 1, "morgen fällig: ruhig")
    pruefe(vor(7).stand(heute: heute) == .faellig && vor(7).restTage(heute: heute) == 0, "heute fällig: gelb")
    pruefe(vor(8).stand(heute: heute) == .faellig, "1 Tag drüber: gelb")
    pruefe(vor(9).stand(heute: heute) == .dringend && vor(30).stand(heute: heute) == .dringend, "2+ Tage drüber: rot")
}

MainActor.assumeIsolated { laufe() }
print(fehler == 0 ? "✓ Kern in Ordnung" : "\(fehler) Fehler")
exit(fehler == 0 ? 0 : 1)
