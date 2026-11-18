import SwiftUI

/// Die eine Seite der App: Timer, Füttern, Rechner, gespeicherte Rezepte, Ablauf. Alles lokal gerechnet und
/// gespeichert, ohne Ladeanzeige.
struct HauptAnsicht: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var db: Datenbank
    @ObservedObject private var timer = BackTimer.shared
    @AppStorage("sauerteig-werte") private var gespeichert: Data = Data()
    @State private var w = SauerteigWerte()
    @State private var geladen = false
    @State private var sichernOffen = false
    @State private var timerOffen = false
    @State private var ausgeblendet: Set<String> = []
    @State private var offen: Int = 0
    @State private var abhakenUm: Int?

    private var r: Berechnung { Rechner.rezept(w.eingabe) }

    var body: some View {
        let r = self.r
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        TimerKarte(r: r).id(AppState.Ziel.timer.rawValue)
                        FuetternKarte().id(AppState.Ziel.fuettern.rawValue)
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
                            Text("Tipps").font(.headline)
                            ForEach(SauerteigDaten.tipps, id: \.self) { t in
                                Label(t, systemImage: "checkmark").font(.subheadline)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .pageContainer()
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .hhBackground()
                .navigationTitle("Sauerteig")
                .onChange(of: app.ziel) { _, z in
                    guard let z else { return }
                    let id = z == .timer && timer.lauf == nil ? "ablauf" : z.rawValue
                    withAnimation(Metrics.move) { proxy.scrollTo(id, anchor: .top) }
                    app.ziel = nil
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let t = app.toast {
                ToastView(toast: t) { withAnimation(Metrics.exit) { app.toast = nil } }
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            guard !geladen else { return }
            geladen = true
            if let v = try? JSONDecoder().decode(SauerteigWerte.self, from: gespeichert) { w = v }
        }
        .onChange(of: w) { _, v in gespeichert = (try? JSONEncoder().encode(v)) ?? Data() }
        .sheet(isPresented: $sichernOffen) { RezeptSichernBlatt(w: w) }
        .sheet(isPresented: $timerOffen) { TimerStartBlatt(r: r) }
        .sheet(item: Binding(get: { abhakenUm.map { AbhakenZiel(i: $0) } }, set: { abhakenUm = $0?.i })) { z in
            AbhakenUmBlatt(i: z.i, titel: r.schritte.indices.contains(z.i) ? r.schritte[z.i].titel : "") { am in
                timer.hakeAb(z.i, am: am)
                offen = z.i + 1
            }
        }
    }

    private func uebersicht(_ r: Berechnung) -> some View {
        Card {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
                stat("Teig", "\(r.teiggewicht) g", w.teigTeilen ? "2 × \(Int(r.einzelGewicht.rounded())) g" : "1 Brot")
                stat("Hydration", "\(r.hydration) %", "\(r.gesamtMehl) g Mehl im Hauptteig")
                stat("Gesamtdauer", "\(Rechner.hm(r.gesamtDauer)) h", "bis aus dem Ofen")
                stat("Backen", "\(w.ofenTemp) °C", "\(r.backZeit) nach Dampf")
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
        let rezepte = db.rezepte.filter { !ausgeblendet.contains($0.id) }
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
            if !rezepte.isEmpty {
                Text("Gespeicherte Rezepte").font(.subheadline.weight(.bold)).padding(.top, 8)
                ForEach(rezepte) { rez in
                    HStack {
                        Button {
                            w = rez.werte
                            app.zeige("„\(rez.name)“ geladen")
                        } label: {
                            VStack(alignment: .leading) {
                                Text(rez.name).fontWeight(.semibold).foregroundStyle(Color.hhInk)
                                Text(rez.datum).font(.footnote).foregroundStyle(Color.hhMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            app.loescheMitRueckgaengig("Rezept gelöscht",
                                                       ausblenden: { _ = withAnimation(Metrics.move) { ausgeblendet.insert(rez.id) } },
                                                       zurueck: { _ = withAnimation(Metrics.move) { ausgeblendet.remove(rez.id) } },
                                                       endgueltig: { db.loescheRezept(rez.id) })
                        } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                            .foregroundStyle(Color.hhMuted)
                            .accessibilityLabel("„\(rez.name)“ löschen")
                    }
                }
            }
            Button { sichernOffen = true } label: { Label("Rezept sichern", systemImage: "square.and.arrow.down") }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 6)
        }
    }

    /// Mischung/Anteile ändern und die empfohlene Hydration setzen (wie neueAnteile).
    private func setMischung(_ m: String) {
        var n = w
        n.mischung = m
        n.hydration = Rechner.optimaleHydration(n.anteile)
        w = n
    }

    private func setCustom(_ c: Anteile) {
        var n = w
        n.custom = c
        n.hydration = Rechner.optimaleHydration(n.anteile)
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

    private var tempKarte: some View {
        Card {
            Text("Temperaturen").font(.headline)
            Regler(label: "Anstellgut", wert: "\(w.anstellgut) g", value: $w.anstellgut, range: 30...200, step: 1)
            Regler(label: "Sauerteig-Temperatur", wert: "\(w.sauerteigTemp) °C", value: $w.sauerteigTemp, range: 18...32, step: 1)
            Regler(label: "Gare-Temperatur", wert: "\(w.gareTemp) °C", value: $w.gareTemp, range: 20...32, step: 1)
            Regler(label: "Ofentemperatur", wert: "\(w.ofenTemp) °C", value: $w.ofenTemp, range: 200...250, step: 5,
                   hint: "Backen ohne Dampf: \(r.backZeit). Vorheizen und Dampfphase bei \(r.anbackTemp) °C.")
        }
    }

    // MARK: Ablauf

    private func ablaufKarte(_ r: Berechnung) -> some View {
        let lauf = timer.lauf
        let passt = lauf.map { l in l.schritte.count == r.schritte.count && zip(l.schritte, r.schritte).allSatisfy { $0.titel == $1.titel } } ?? false
        let l = passt ? lauf : nil
        let weiter = l?.offenAb ?? 0
        let aktiv: Int? = (l != nil && weiter < (l?.schritte.count ?? 0)) ? weiter : nil
        return Card {
            CardTitle("Ablauf", hint: lauf == nil ? "T = Zeitpunkt, an dem der Sauerteig angesetzt wird. Mittelwerte der Zeitspannen." : "")
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                let jetzt = ctx.date.timeIntervalSince1970 * 1000
                VStack(spacing: 0) {
                    ForEach(Array(r.schritte.enumerated()), id: \.offset) { i, s in
                        let erledigt = l != nil && i < weiter
                        DisclosureGroup(isExpanded: Binding(get: { offen == i }, set: { offen = $0 ? i : -1 })) {
                            VStack(alignment: .leading, spacing: 8) {
                                Anleitung(art: s.art, r: r, w: w)
                                if let l, i >= BackLauf.beginn, i <= weiter {
                                    HStack(spacing: 8) {
                                        Button {
                                            timer.hakeAb(i)
                                            offen = i + 1
                                        } label: { Label(erledigt ? "Aktualisieren" : "Erledigt", systemImage: "checkmark") }
                                            .buttonStyle(PrimaryButtonStyle(fullWidth: false))
                                        Button { abhakenUm = i } label: { Image(systemName: "clock") }
                                            .buttonStyle(SecondaryButtonStyle())
                                            .accessibilityLabel("Andere Uhrzeit")
                                    }
                                    Note(erledigt
                                         ? "Erledigt um \(BackLauf.uhrzeit(l.schritte[i].at, jetzt: jetzt)). Aktualisieren setzt ihn auf jetzt, die folgenden Schritte rücken mit. Mit der Uhr eine andere Uhrzeit wählen."
                                         : "Die folgenden Schritte rücken mit. Mit der Uhr eine andere Uhrzeit wählen.")
                                }
                                if s.art == .ansetzen {
                                    Button("Sauerteig angesetzt") { timerOffen = true }
                                        .buttonStyle(PrimaryButtonStyle(fullWidth: false))
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
                                        Text("T+\(Rechner.hm(s.t))")
                                    }
                                }
                                .font(.footnote.weight(.semibold).monospacedDigit())
                                .frame(width: 74, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        if erledigt { Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(Color.hhPos) }
                                        Text(s.titel).fontWeight(.semibold).foregroundStyle(i == aktiv ? Brand().accent : Color.hhInk)
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
            }
            if lauf != nil && !passt {
                Note("Der laufende Timer gehört zu anderen Einstellungen, daher hier ohne Uhrzeiten.")
            }
        }
        .onChange(of: aktiv) { _, a in if let a { offen = a } }
    }
}

private struct AbhakenZiel: Identifiable {
    var i: Int
    var id: Int { i }
}

/// Rezept sichern: Name, gespeichert auf dem Gerät.
private struct RezeptSichernBlatt: View {
    let w: SauerteigWerte
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var db: Datenbank
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Mein Sauerteigbrot"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                LabeledField(label: "Name", hint: "Gesichert auf diesem Gerät. Laden unter „Brotauswahl“.") {
                    TextField("", text: $name).textFieldStyle(.hh)
                }
                Spacer()
            }
            .padding(Metrics.gutter)
            .background(Color.hhBg)
            .navigationTitle("Rezept sichern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetClose { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        db.speichereRezept(name, w)
                        dismiss()
                        app.zeige("Rezept gesichert")
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(260)])
    }
}
