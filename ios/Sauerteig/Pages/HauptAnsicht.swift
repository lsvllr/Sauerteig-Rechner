import SwiftUI

/// Tab „Backen“: Timer, Füttern, Rechner, Ablauf. Alles lokal gerechnet und gespeichert, ohne Ladeanzeige.
/// Gesicherte Rezepte und gebackene Brote liegen im Tab „Tagebuch“ (Pages/TagebuchAnsicht.swift).
struct HauptAnsicht: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var db: Datenbank
    @EnvironmentObject private var timer: BackTimer
    @AppStorage("sauerteig-werte") private var gespeichert: Data = Data()
    @State private var w = SauerteigWerte()
    @State private var geladen = false
    @State private var sichernOffen = false
    @State private var ersetzenSicher = false
    @State private var einstellungenOffen = false
    @State private var fuetternOffen = false
    @State private var offen: Int = 0
    @State private var abhakenUm: Int?
    @AppStorage("tipps-offen") private var tippsOffen = false

    private var r: Berechnung { Rechner.rezept(w.eingabe) }

    var body: some View {
        let r = self.r
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        TimerKarte(r: r).id(AppState.Ziel.timer.rawValue)
                        uebersicht(r)
                        mischungKarte
                        teigKarte
                        tempKarte
                        ablaufKarte(r).id("ablauf")
                        Card {
                            Text("Erwartetes Ergebnis").font(.headline)
                            FactRow("Krume", r.krume)
                            FactRow("Geschmack", r.geschmack)
                            FactRow("Haltbarkeit", r.haltbarkeit)
                        }
                        Card {
                            AblaufAbschnitt(offen: tippsOffen, umschalten: { withAnimation(Metrics.move) { tippsOffen.toggle() } }) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(SauerteigDaten.tipps, id: \.self) { t in
                                        Label(t, systemImage: "checkmark").font(.subheadline)
                                    }
                                }
                                .padding(.top, 10)
                            } label: {
                                Text("Tipps").font(.headline)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .pageContainer()
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .hhBackground()
                // Füttern-Popup: hier am Inhalt statt an der ganzen Seite, damit es unter der Navigationsleiste
                // hängt und Glas und Zahnrad frei bleiben. Es wächst von der Stelle unter dem Glas auf.
                // Hintergrund und Karte als eigene Einträge, damit jede ihre eigene Einblendung bekommt
                // (verschachtelt gilt nur die äußere).
                .overlay(alignment: .top) {
                    ZStack(alignment: .topLeading) {
                        if fuetternOffen {
                            Color.black.opacity(0.35)
                                .ignoresSafeArea()
                                .onTapGesture { zeigeFuettern(false) }
                                .accessibilityLabel("Schließen")
                                .accessibilityAddTraits(.isButton)
                                .transition(.opacity)
                        }
                        if fuetternOffen {
                            FuetternKarte(schliessen: { zeigeFuettern(false) })
                            .frame(maxWidth: 520)
                            .transition(.scale(scale: 0.08, anchor: Self.glasAnker).combined(with: .opacity))
                            .padding(.horizontal, Metrics.gutter)
                            .padding(.top, 2)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .zIndex(1)
                            .accessibilityAddTraits(.isModal)
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        // Tageswechsel ohne Datenbankänderung (gelb → rot) auch bei offener App mitnehmen.
                        TimelineView(.everyMinute) { ctx in
                            let f = db.fuetterung
                            Button { zeigeFuettern(!fuetternOffen) } label: { FuetternGlas(stand: f.stand(heute: ctx.date)) }
                                .accessibilityLabel("Sauerteig füttern")
                                .accessibilityValue(f.beschreibung(heute: ctx.date))
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { einstellungenOffen = true } label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Einstellungen")
                    }
                }
                .onChange(of: app.ziel) { _, z in
                    guard let z else { return }
                    if z == .fuettern {
                        zeigeFuettern(true)
                        app.ziel = nil
                        return
                    }
                    let id = z == .timer && timer.lauf == nil ? "ablauf" : z.rawValue
                    withAnimation(Metrics.move) { proxy.scrollTo(id, anchor: .top) }
                    app.ziel = nil
                }
            }
        }
        .toastUnten()
        .onAppear {
            guard !geladen else { return }
            geladen = true
            if let v = try? JSONDecoder().decode(SauerteigWerte.self, from: gespeichert) { w = v.migriert() }
            uebernimmGeladene()
        }
        .onChange(of: w) { _, v in gespeichert = (try? JSONEncoder().encode(v)) ?? Data() }
        .onChange(of: app.laden) { _, _ in uebernimmGeladene() }
        .sheet(isPresented: $sichernOffen) { RezeptSichernBlatt(w: w) }
        .sheet(isPresented: $einstellungenOffen) { EinstellungenBlatt() }
        .sheet(item: Binding(get: { abhakenUm.map { AbhakenZiel(i: $0) } }, set: { abhakenUm = $0?.i })) { z in
            if z.i == 0 {
                AbhakenUmBlatt(i: 0, titel: r.schritte.first?.titel ?? "", art: .angesetzt) { am in
                    timer.setzeStart(am: am)
                    oeffne(BackLauf.beginn)
                }
            } else if timer.lauf.map({ $0.startbar(z.i) && $0.laufend == z.i - 1 }) == true {
                // Autolyse oder Ofen vor dem Start: Startzeit
                AbhakenUmBlatt(i: z.i, titel: r.schritte.indices.contains(z.i) ? r.schritte[z.i].titel : "", art: .gestartet) { am in
                    timer.starte(z.i, am: am)
                }
            } else if timer.lauf?.phase == .reifen {
                AbhakenUmBlatt(i: z.i, titel: r.schritte.indices.contains(z.i) ? r.schritte[z.i].titel : "", art: .begonnen) { am in
                    timer.beginneBacken(am: am)
                    oeffne(z.i)
                }
            } else {
                AbhakenUmBlatt(i: z.i, titel: r.schritte.indices.contains(z.i) ? r.schritte[z.i].titel : "") { am in
                    timer.erledige(z.i, am: am)
                    if let n = timer.lauf?.folgt(auf: z.i) { oeffne(n) }
                }
            }
        }
    }

    /// Aus dem Tagebuch geladen: in den Rechner übernehmen.
    private func uebernimmGeladene() {
        guard geladen, let v = app.laden else { return }
        w = v
        app.laden = nil
    }

    /// Oberkante der Karte unter der Mitte des Glases (rund 24 pt von links bei einer iPhone-Kartenbreite um
    /// 370 pt): von hier wächst das Popup auf und schrumpft dorthin zurück.
    private static let glasAnker = UnitPoint(x: 0.065, y: 0)

    /// Füttern-Popup öffnen/schließen (Glas oben links, Mitteilung `/fuettern`). Auf mit leichtem Nachfedern,
    /// zu ohne, damit es zügig verschwindet.
    private func zeigeFuettern(_ an: Bool) {
        guard fuetternOffen != an else { return }
        if an { Haptics.tap() }
        withAnimation(an ? .spring(response: 0.38, dampingFraction: 0.74) : .spring(response: 0.26, dampingFraction: 1)) {
            fuetternOffen = an
        }
    }

    private func uebersicht(_ r: Berechnung) -> some View {
        Card {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                stat("Teig", "\(r.teiggewicht) g", w.teigTeilen ? "2 × \(Int(r.einzelGewicht.rounded())) g" : "1 Brot")
                stat("Hydration", "\(r.hydration) %", "\(r.gesamtMehl) g Mehl im Hauptteig")
                stat("Gesamtdauer", "\(Rechner.hm(r.gesamtDauer)) h", "bis aus dem Ofen")
                stat("Backen", "\(r.anbackTemp) → \(r.ofenTemp) °C", "\(r.dampfMin) Min Dampf, dann \(r.backZeit)")
            }
        }
    }

    private func stat(_ l: String, _ v: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l).font(.footnote).foregroundStyle(Color.hhMuted)
            Text(v).font(.title3.weight(.heavy)).contentTransition(.numericText())
            Text(s).font(.caption).foregroundStyle(Color.hhMuted)
        }
    }

    // MARK: Brotauswahl

    static let farben: [Sorte: Color] = [
        .roggen: Color(hex: "#8b5a2b"), .dinkel: Color(hex: "#d4a24c"), .weizen: Color(hex: "#e8c77a"), .buchweizen: Color(hex: "#5b4636"),
    ]

    private var mischungKarte: some View {
        let a = w.anteile
        let mix = SauerteigDaten.mischung(w.mischung)
        let summe = Sorte.allCases.reduce(0) { $0 + w.custom[$1] }
        return Card {
            Text("Brotauswahl").font(.headline)
            LabeledField(label: "Mischung") {
                MenuPicker(options: SauerteigDaten.mischungen.map { Choice($0.key, $0.name) } + [Choice("custom", "Eigene Mischung")],
                           selection: Binding(get: { w.mischung }, set: { setMischung($0) }))
            }
            Text(mix?.name ?? "Eigene Mischung").fontWeight(.bold)
            Text(mix?.beschreibung ?? "Anteile frei wählbar").font(.footnote).foregroundStyle(Color.hhMuted)
            if let mix { Text("Eigenschaften: \(mix.eigenschaften)").font(.footnote).foregroundStyle(Color.hhMuted) }
            GeometryReader { g in
                HStack(spacing: 0) {
                    ForEach(Sorte.allCases.filter { a[$0] > 0 }, id: \.self) { k in
                        Rectangle().fill(Self.farben[k]!).frame(width: g.size.width * CGFloat(a[k]) / CGFloat(max(a.summe, 1)))
                    }
                }
                .clipShape(Capsule())
                .animation(Metrics.move, value: a)
            }
            .frame(height: 12)
            FlowLayout(spacing: 12) {
                ForEach(Sorte.allCases, id: \.self) { k in
                    HStack(spacing: 4) {
                        Circle().fill(Self.farben[k]!).frame(width: 8, height: 8)
                        Text(k.name).font(.footnote)
                        Text("\(a[k]) %").font(.footnote.weight(.bold))
                    }
                    .opacity(a[k] > 0 ? 1 : 0.45)
                }
            }
            if w.mischung == "custom" {
                ForEach(Sorte.allCases, id: \.self) { k in
                    Regler(label: k.name, wert: "\(w.custom[k]) %", value: Binding(get: { w.custom[k] }, set: { v in
                        var c = w.custom
                        c[k] = v
                        setCustom(c)
                    }), range: 0...100, step: 5, dot: Self.farben[k])
                }
                HStack {
                    Text("Summe: \(summe) %").font(.footnote).foregroundStyle(summe == 100 ? Color.hhMuted : Color.hhNegFg)
                    Spacer()
                    if summe != 100 {
                        Button("Auf 100 % anpassen") {
                            guard let n = Rechner.normalisiere(w.custom) else {
                                app.zeige("Mindestens ein Mehl muss über 0 % liegen", .fehler)
                                return
                            }
                            setCustom(n)
                        }
                        .buttonStyle(SecondaryButtonStyle(small: true))
                    }
                }
            }
            HStack(spacing: 8) {
                Button { sichernOffen = true } label: { Label("Im Tagebuch sichern", systemImage: "book") }
                    .buttonStyle(SecondaryButtonStyle())
                Button { app.tab = .tagebuch } label: { Text("Rezept laden") }
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 6)
        }
    }

    /// Mischung/Anteile ändern und die empfohlene Hydration setzen (wie neueAnteile).
    private func setMischung(_ m: String) {
        var n = w
        n.mischung = m
        n.hydration = Rechner.optimaleHydration(n.anteile)
        n.sauerteigArtWahl = nil // Sauerteig wieder passend zum neuen Brot
        w = n
    }

    private func setCustom(_ c: Anteile) {
        var n = w
        n.custom = c
        n.hydration = Rechner.optimaleHydration(n.anteile)
        n.sauerteigArtWahl = nil
        w = n
    }

    private var teigKarte: some View {
        let optimal = Rechner.optimaleHydration(w.anteile)
        return Card {
            Text("Teig").font(.headline)
            Regler(label: "Teiggewicht", wert: "\(r.teiggewicht) g", value: $w.brotGroesse, range: 600...2000, step: 100)
            Regler(label: "Hydration", wert: "\(w.hydration) %", value: $w.hydration, range: 50...85, step: 1,
                   badge: abs(w.hydration - optimal) <= 2 ? Pill("Empfohlen", .effort) : Pill("Angepasst", .today),
                   hint: "Höhere Hydration ergibt weicheren Teig. Bei Mischungswechsel wird der empfohlene Wert gesetzt.")
            Toggle("Auf 2 Brote teilen", isOn: $w.teigTeilen).tint(Brand().primary)
        }
    }

    /// Ab so viel Anstellgut (g) der Hinweis, es vorher zu vermehren (wie ANSTELLGUT_VIEL im Web).
    private static let anstellgutViel = 150

    private var tempKarte: some View {
        Card {
            Text("Sauerteig und Temperaturen").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Verhältnis").font(.subheadline.weight(.semibold))
                Picker("Verhältnis", selection: $w.verhaeltnis) {
                    ForEach(Verhaeltnis.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: w.verhaeltnis)
                FactRow("Anstellgut", "\(r.anstellgut) g · \(r.verhaeltnis.text)")
                Note("Aus Teiggewicht und Verhältnis; \(r.versaeuerung) % des Mehls stecken im Sauerteig. Mehr Futter (1 : 5 : 5) reift länger und schmeckt milder, weniger (1 : 1 : 1) geht schneller und wird kräftiger.")
                if r.anstellgut > Self.anstellgutViel {
                    Pill("So viel Anstellgut hast du vielleicht nicht im Glas: am Vortag auffrischen und vermehren.", .today)
                }
            }
            .padding(.bottom, 4)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Sauerteig aus").font(.subheadline.weight(.semibold))
                    w.sauerteigArt == Rechner.sauerteigArt(w.anteile)
                        ? Pill("Passend zum Brot", .effort) : Pill("Angepasst", .today)
                }
                Picker("Sauerteig aus", selection: $w.sauerteigArt) {
                    ForEach(SauerteigArt.allCases, id: \.self) { Text($0.sorte.name).tag($0) }
                }
                .pickerStyle(.segmented)
                .sensoryFeedback(.selection, trigger: w.sauerteigArt)
                if !r.sauerteigHinweis.isEmpty { Note(r.sauerteigHinweis) }
            }
            .padding(.bottom, 4)
            Regler(label: "Sauerteig-Temperatur", wert: "\(w.sauerteigTemp) °C", value: $w.sauerteigTemp, range: 18...32, step: 1)
            Regler(label: "Gare-Temperatur", wert: "\(w.gareTemp) °C", value: $w.gareTemp, range: 20...32, step: 1)
            Text("Ofen").font(.headline).padding(.top, 10)
            Regler(label: "Anbacken mit Dampf", wert: "\(w.anbackTemp) °C", value: $w.anbackRegler, range: 200...350, step: 5,
                   hint: "Dampfphase: \(r.dampfMin) Min. Je heißer, desto kürzer (wie bei Pizza); auf diese Temperatur wird vorgeheizt.")
            Regler(label: "Ofentemperatur", wert: "\(w.ofenTemp) °C", value: $w.ofenTemp, range: 200...250, step: 5,
                   hint: "Nach der Dampfphase heruntergeschaltet, ohne Dampf: \(r.backZeit).")
        }
    }

    // MARK: Ablauf

    private func ablaufKarte(_ r: Berechnung) -> some View {
        let lauf = timer.lauf
        // Zahlen im Titel zählen nicht („Ofen auf 250 °C vorheizen“ ändert sich mit der Ofentemperatur).
        func ohneZahlen(_ t: String) -> String { t.replacingOccurrences(of: "[0-9]+", with: "#", options: .regularExpression) }
        let passt = lauf.map { l in
            l.schritte.count == r.schritte.count && zip(l.schritte, r.schritte).allSatisfy { ohneZahlen($0.titel) == ohneZahlen($1.titel) }
        } ?? false
        let l = passt ? lauf : nil
        let backen = l?.phase == .backen
        // laufender Schritt; beim Reifen der, mit dem das Backen beginnt
        let c = l.map { backen ? $0.laufend : BackLauf.beginn }
        let aktiv: Int? = l?.fertig == true ? nil : c
        return Card {
            CardTitle("Ablauf", hint: lauf == nil ? "T = Zeitpunkt, an dem der Sauerteig angesetzt wird. Mittelwerte der Zeitspannen." : "")
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let jetzt = ctx.date.timeIntervalSince1970 * 1000
                // Schritt mit eigenem Start (Ofen), der jetzt fällig ist: klappt auf.
                let faellig: Int? = l.flatMap { l in
                    let n = l.laufend + 1
                    return l.startbar(n) && l.schritte[n].at <= jetzt ? n : nil
                }
                VStack(spacing: 0) {
                    ForEach(Array(r.schritte.enumerated()), id: \.offset) { i, s in
                        let erledigt = l.map { backen && i < $0.laufend } ?? false
                        AblaufAbschnitt(offen: offen == i, umschalten: { oeffne(offen == i ? -1 : i) }) {
                            VStack(alignment: .leading, spacing: 8) {
                                Anleitung(art: s.art, r: r, w: w)
                                if let l, let c, backen ? (l.abhakbar(i) && i <= c) : (i == BackLauf.beginn && !l.mitStart(i)) {
                                    let n = i + 1
                                    HStack(spacing: 8) {
                                        Button {
                                            if backen { timer.erledige(i) } else { timer.beginneBacken() }
                                            oeffne(backen ? n : i)
                                        } label: { Label(!backen ? "Backen beginnen" : (erledigt ? "Aktualisieren" : "Erledigt"), systemImage: "checkmark") }
                                            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                                        Button { abhakenUm = i } label: { Image(systemName: "clock") }
                                            .buttonStyle(SecondaryButtonStyle())
                                            .accessibilityLabel("Andere Uhrzeit")
                                        InfoButton(text: !backen
                                                   ? "Sobald der Sauerteig reif ist: Der Schritt beginnt jetzt, die folgenden rücken mit. Mit der Uhr eine andere Uhrzeit wählen."
                                                   : erledigt
                                                   ? "Aktualisieren: Der Schritt war jetzt fertig, „\(l.schritte[n].titel)“ beginnt jetzt, die folgenden rücken mit. Mit der Uhr eine andere Uhrzeit wählen."
                                                   : "Erledigt, sobald der Schritt fertig ist: „\(l.schritte[n].titel)“ beginnt dann, die folgenden rücken mit. Bis dahin wartet der Timer. Mit der Uhr eine andere Uhrzeit wählen.")
                                    }
                                    if erledigt {
                                        Note("Fertig um \(BackLauf.uhrzeit(l.schritte[n].at, jetzt: jetzt)).")
                                    }
                                }
                                // Eigener Start (Autolyse, Ofen): „Starten“, solange der Schritt davor läuft; danach
                                // wie jeder laufende Schritt „Erledigt“ (oben).
                                if let l, l.startbar(i), l.laufend == i - 1 {
                                    HStack(spacing: 8) {
                                        Button { timer.starte(i) } label: { Label("Starten", systemImage: "play.fill") }
                                            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                                        Button { abhakenUm = i } label: { Image(systemName: "clock") }
                                            .buttonStyle(SecondaryButtonStyle())
                                            .accessibilityLabel("Andere Uhrzeit")
                                        InfoButton(text: s.art == .ofen
                                                   ? "Starten, sobald der Ofen eingeschaltet ist. Die Stückgare läuft dabei weiter, ihre Zeit enthält das Vorheizen. „Erledigt“ beim Vorheizen beendet beides, dann wird gebacken."
                                                   : "Starten, sobald die Autolyse angesetzt ist; damit beginnt das Backen. Der Sauerteig reift dabei weiter, seine Zeit enthält die Autolyse. „Erledigt“ bei der Autolyse beendet beides, dann kommt der Hauptteig.")
                                    }
                                    Note(l.schritte[i].at > jetzt
                                         ? "Fällig um \(BackLauf.uhrzeit(l.schritte[i].at, jetzt: jetzt))."
                                         : "Jetzt fällig.")
                                }
                                // Laufender Schritt: aktive Zeit
                                if let l, let c, backen, i == c, !l.fertig {
                                    let start = Date(timeIntervalSince1970: l.schritte[i].at / 1000)
                                    (Text("Aktiv seit \(BackLauf.uhrzeit(l.schritte[i].at, jetzt: jetzt)) · ")
                                     + Text(start, style: .timer).monospacedDigit())
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(Brand().accent)
                                    if let n = l.folgt(auf: i) {
                                        Note(l.abhakbar(i)
                                             ? (l.schritte[n].at > jetzt
                                                ? "Geplant bis \(BackLauf.uhrzeit(l.schritte[n].at, jetzt: jetzt))."
                                                : "Geplante Zeit um. „Erledigt“ tippen, sobald der Schritt fertig ist.")
                                             : "Endet mit dem Start von „\(l.schritte[n].titel)“ um ca. \(BackLauf.uhrzeit(l.schritte[n].at, jetzt: jetzt)).")
                                    }
                                    // Backen in zwei Stufen
                                    if let e = l.dampfEnde, let d = l.dampf {
                                        Note(e > jetzt
                                             ? "Stufe 1: mit Dampf bei \(d.heiss) °C bis \(BackLauf.uhrzeit(e, jetzt: jetzt)), dann Dampf raus" + (d.heiss > d.temp ? " und auf \(d.temp) °C herunterschalten." : ".")
                                             : "Stufe 2: ohne Dampf bei \(d.temp) °C (seit \(BackLauf.uhrzeit(e, jetzt: jetzt))).")
                                    }
                                }
                                if s.art == .ansetzen {
                                    if let l {
                                        // Schon angesetzt (laufender Timer zu diesem Rezept): Zeitpunkt ändern statt neu starten.
                                        HStack(spacing: 8) {
                                            Button {
                                                timer.setzeStart()
                                                oeffne(BackLauf.beginn)
                                            } label: { Label("Aktualisieren", systemImage: "checkmark") }
                                                .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                                            Button { abhakenUm = i } label: { Image(systemName: "clock") }
                                                .buttonStyle(SecondaryButtonStyle())
                                                .accessibilityLabel("Andere Uhrzeit")
                                            InfoButton(text: "Aktualisieren setzt das Ansetzen auf jetzt, Reife und die folgenden Schritte rücken mit. Mit der Uhr eine andere Uhrzeit wählen.")
                                        }
                                        Note("Angesetzt um \(BackLauf.uhrzeit(l.start, jetzt: jetzt)).")
                                    } else {
                                        Button(ersetzenSicher ? "Laufenden Timer ersetzen?" : "Sauerteig angesetzt") { setzeAn(r) }
                                            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    if let ts = l?.schritte[i] {
                                        Text((l?.phase == .reifen && i >= BackLauf.beginn ? "ca. " : "") + BackLauf.uhrzeit(ts.at, jetzt: jetzt))
                                        Text("bis \(BackLauf.uhrzeit(ts.at + Double(Rechner.dauerMinuten(s.dauer)) * 60_000, jetzt: jetzt))")
                                            .font(.caption).foregroundStyle(Color.hhMuted)
                                    } else {
                                        Text(Rechner.hmKurz(s.t))
                                    }
                                }
                                .font(.footnote.weight(.semibold).monospacedDigit())
                                .frame(width: 74, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(s.titel).fontWeight(.semibold).foregroundStyle(i == aktiv ? Brand().accent : Color.hhInk)
                                        if erledigt { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.hhPos) }
                                    }
                                    Text(s.dauer).font(.footnote).foregroundStyle(Color.hhMuted)
                                }
                            }
                            .opacity(erledigt ? 0.6 : 1)
                        }
                        .padding(.vertical, 6)
                        if i < r.schritte.count - 1 { RowDivider() }
                    }
                }
                .onChange(of: faellig, initial: true) { _, f in if let f { oeffne(f) } }
            }
            if lauf != nil && !passt {
                Note("Der laufende Timer gehört zu anderen Einstellungen, daher hier ohne Uhrzeiten.")
            }
        }
        .onChange(of: aktiv) { _, a in if let a { oeffne(a) } }
    }

    /// „Sauerteig angesetzt“: Timer sofort mit jetzt starten (Zeitpunkt danach im Schritt änderbar). Läuft schon ein
    /// Timer zu anderen Einstellungen, erst nach zweitem Tippen ersetzen.
    private func setzeAn(_ r: Berechnung) {
        if timer.lauf != nil && !ersetzenSicher {
            ersetzenSicher = true
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                ersetzenSicher = false
            }
            return
        }
        ersetzenSicher = false
        let l = BackLauf.neu(r.schritte, start: (Date().timeIntervalSince1970 * 1000).rounded(), vorlauf: Einstellungen.vorlauf,
                             reife: Rechner.spanne(r.zeitplan.sauerteigZeit) ?? (0, 0), dampf: BackLauf.dampf(r))
        Task {
            let ok = await timer.starte(l, werte: w)
            app.zeige(ok ? "Sauerteig angesetzt" : "Sauerteig angesetzt, ohne Mitteilungen", ok ? .erfolg : .fehler)
        }
    }

    /// Schritt `i` im Ablauf aufklappen (-1 = alle zu). Ein anderer offener klappt in derselben Animation zu.
    private func oeffne(_ i: Int) {
        guard offen != i else { return }
        withAnimation(Metrics.move) { offen = i }
    }
}

/// Aufklappbarer Schritt im Ablauf. Statt DisclosureGroup: Die klappt den Inhalt mit eigener Einblendung auf, dabei
/// springt der Text kurz hoch und wieder runter. Hier ändert sich nur die Höhe (von oben abgeschnitten), der Inhalt
/// bleibt oben stehen; zu- und aufklappen laufen so sauber in einer Animation.
private struct AblaufAbschnitt<Inhalt: View, Kopf: View>: View {
    let offen: Bool
    let umschalten: () -> Void
    @ViewBuilder let inhalt: () -> Inhalt
    @ViewBuilder let label: () -> Kopf

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tippgeste statt Button: Ein Button dunkelt den Titel beim Tippen ab und blendet ihn erst nach dem
            // Loslassen wieder ein, dann hängt der Titel der Klapp-Animation sichtbar hinterher.
            HStack(alignment: .top, spacing: 8) {
                label().frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Brand().accent)
                    .rotationEffect(.degrees(offen ? 90 : 0))
                    .padding(.top, 3)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: umschalten)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { umschalten() }
            .accessibilityValue(offen ? "geöffnet" : "geschlossen")
            .accessibilityHint(offen ? "Zum Zuklappen doppeltippen" : "Zum Aufklappen doppeltippen")
            inhalt()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: offen ? nil : 0, alignment: .top)
                .clipped()
                .opacity(offen ? 1 : 0)
                .allowsHitTesting(offen)
                .accessibilityHidden(!offen)
        }
    }
}

private struct AbhakenZiel: Identifiable {
    var i: Int
    var id: Int { i }
}

/// Im Tagebuch sichern: Name aus der Mehlmischung, auf Wunsch eigener.
private struct RezeptSichernBlatt: View {
    let w: SauerteigWerte
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var db: Datenbank
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        let auto = Backeintrag.automatischerName(w)
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                LabeledField(label: "Name", hint: "Leer lassen: Name aus der Mehlmischung. Laden im Tab „Tagebuch“.") {
                    TextField(auto, text: $name).textFieldStyle(.hh)
                }
                Note("Gesichert mit allen Einstellungen und Mengen. Wird ein Back-Timer fertig, legt die App das Backen von selbst im Tagebuch ab.")
                Spacer()
            }
            .padding(Metrics.gutter)
            .background(Color.hhBg)
            .navigationTitle("Im Tagebuch sichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetClose { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        db.legeEintragAn(w, name: name)
                        dismiss()
                        app.zeige("Im Tagebuch gesichert")
                    }
                }
            }
        }
        .presentationDetents([.height(300)])
    }
}

#if DEBUG
#Preview("Blatt · Rezept sichern") {
    Color.clear.sheet(isPresented: .constant(true)) { RezeptSichernBlatt(w: Vorschau.werte) }.vorschau()
}

// MARK: - Ganze Seite

#Preview("Seite · ohne Timer") { HauptAnsicht().vorschau(rezepte: true) }
#Preview("Seite · Sauerteig reift") { HauptAnsicht().vorschau(timer: .reift) }
#Preview("Seite · Backen läuft") { HauptAnsicht().vorschau(timer: .backen) }
#Preview("Seite · Fertig gebacken") { HauptAnsicht().vorschau(timer: .fertig) }
#Preview("Seite · Hinweis") {
    HauptAnsicht().vorschau(toast: AppState.Toast(text: "Im Tagebuch gesichert", art: .erfolg))
}
#Preview("Seite · Rückgängig") {
    HauptAnsicht().vorschau(toast: AppState.Toast(text: "Rezept gelöscht", art: .info, rueckgaengig: {}))
}
#Preview("Seite · Füttern überfällig") { HauptAnsicht().vorschau(fuettern: .ueberfaellig) }
#Preview("Seite · dunkel") { HauptAnsicht().vorschau(timer: .backen).preferredColorScheme(.dark) }
#endif
