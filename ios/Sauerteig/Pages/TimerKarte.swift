import SwiftUI

/// Karte oben: „Sauerteig reift“ / „Backen läuft“ mit Countdown. Ohne laufenden Timer leer.
struct TimerKarte: View {
    let r: Berechnung
    @EnvironmentObject private var timer: BackTimer
    @EnvironmentObject private var app: AppState
    @State private var sicher = false

    var body: some View {
        if let l = timer.lauf {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let jetzt = ctx.date.timeIntervalSince1970 * 1000
                let reifen = l.phase == .reifen
                // Laufender Schritt; er bleibt, bis er abgehakt ist. Danach beginnt `n`.
                let c = l.laufend
                let n = reifen ? nil : l.folgt(auf: c)
                let fertig = !reifen && n == nil
                // Mit Autolyse beginnt das Backen mit ihrem Start (während der Sauerteig noch reift).
                let autolyse = reifen && l.mitStart(BackLauf.beginn)
                Card {
                    HStack {
                        CardTitle(reifen ? "Sauerteig reift" : (fertig ? "Fertig gebacken" : "Backen läuft"),
                                  hint: autolyse
                                  ? "„Starten“ tippen, sobald die Autolyse angesetzt ist. Der Sauerteig reift dabei weiter, seine Zeit enthält die Autolyse. Ab dann laufen die Schritte mit Erinnerungen und auf dem Sperrbildschirm."
                                  : reifen ? "„Backen beginnen“ tippen, sobald der Sauerteig reif ist (Blasen, leicht gewölbt, säuerlicher Geruch). Ab dann laufen die Schritte mit Erinnerungen und auf dem Sperrbildschirm." : "")
                        Spacer()
                        Button(fertig ? "Schließen" : (sicher ? "Wirklich beenden?" : "Beenden")) {
                            if sicher || fertig {
                                sicher = false
                                // Fertig gebacken: gleich im Tagebuch bewerten
                                if let e = timer.beende(), fertig { app.oeffneEintrag(e, bewerten: true) }
                            } else { sicher = true }
                        }
                        .buttonStyle(SecondaryButtonStyle(danger: sicher, small: true))
                    }
                    if reifen {
                        Text("Angesetzt um \(BackLauf.uhrzeit(l.start, jetzt: jetzt)) · reif ca. \(BackLauf.uhrzeit(l.reife[0], jetzt: jetzt))–\(BackLauf.uhrzeit(l.reife[1], jetzt: jetzt))")
                            .font(.footnote).foregroundStyle(Color.hhMuted)
                        if l.schritte.count > BackLauf.beginn {
                            let b = l.schritte[BackLauf.beginn]
                            Text(autolyse ? "\(BackAktivitaet.kurz(b.titel)) um ca. \(BackLauf.uhrzeit(b.at, jetzt: jetzt))"
                                          : "Backen beginnt ca. \(BackLauf.uhrzeit(b.at, jetzt: jetzt))").fontWeight(.bold)
                            Text(b.at > jetzt ? "≈ \(BackLauf.restzeit(b.at - jetzt))" : (autolyse ? "Jetzt fällig" : "Sauerteig prüfen"))
                                .font(.system(size: 34, weight: .heavy).monospacedDigit())
                                .contentTransition(.numericText())
                            if autolyse {
                                Button("Starten: \(BackAktivitaet.kurz(b.titel))") { timer.starte(BackLauf.beginn) }
                                    .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                        if !autolyse {
                            Button("Backen beginnen") { timer.beginneBacken() }.buttonStyle(PrimaryButtonStyle())
                        }
                    } else if let n {
                        let ende = l.schritte[n].at
                        let um = ende <= jetzt
                        // Backen in zwei Stufen: erst mit Dampf (Countdown bis zum Wechsel), dann ohne.
                        let d = l.dampfEnde != nil ? l.dampf : nil
                        let wechsel = l.dampfEnde ?? 0
                        let mitDampf = d != nil && jetzt < wechsel
                        if let d, mitDampf {
                            Text("Mit Dampf bis \(BackLauf.uhrzeit(wechsel, jetzt: jetzt)) · danach ohne Dampf bei \(d.temp) °C bis \(BackLauf.uhrzeit(ende, jetzt: jetzt))")
                                .font(.footnote).foregroundStyle(Color.hhMuted)
                        } else {
                            Text("\(um ? "Geplant" : "Läuft") bis \(BackLauf.uhrzeit(ende, jetzt: jetzt)) · danach \(l.schritte[n].titel)")
                                .font(.footnote).foregroundStyle(Color.hhMuted)
                        }
                        Text(l.schritte[c].titel + (d.map { mitDampf ? " mit Dampf · \($0.heiss) °C" : " ohne Dampf · \($0.temp) °C" } ?? ""))
                            .fontWeight(.bold)
                        // Zeit um: zählt weiter hoch, bis abgehakt ist.
                        Text(mitDampf ? BackLauf.restzeit(wechsel - jetzt) : um ? "+" + BackLauf.restzeit(jetzt - ende) : BackLauf.restzeit(ende - jetzt))
                            .font(.system(size: 34, weight: .heavy).monospacedDigit())
                            .contentTransition(.numericText())
                        // Nächster Schritt mit eigenem Start (Ofen): Der laufende endet mit „Starten“.
                        let start = l.mitStart(n)
                        if um {
                            Text(start ? "„\(l.schritte[n].titel)“ ist fällig. „\(l.schritte[c].titel)“ läuft dabei weiter."
                                       : "Geplante Zeit um. „Erledigt“ tippen, sobald der Schritt fertig ist.")
                                .font(.footnote).foregroundStyle(Color.hhMuted)
                        }
                        if start {
                            Button("Starten: \(BackAktivitaet.kurz(l.schritte[n].titel))") { timer.starte(n) }
                                .buttonStyle(PrimaryButtonStyle())
                        } else {
                            Button("Erledigt") { timer.erledige(c) }.buttonStyle(PrimaryButtonStyle())
                        }
                    } else {
                        Text("Brot mindestens 2 Stunden auskühlen lassen, erst dann anschneiden.").foregroundStyle(Color.hhMuted)
                        Note("„Schließen“ legt das Backen im Tagebuch ab. Dort kannst du es bewerten, Fotos hinzufügen und die Krume analysieren lassen.")
                    }
                }
            }
            .task(id: sicher) {
                guard sicher else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                sicher = false
            }
        }
    }
}

/// Schritt mit anderer Uhrzeit abhaken (Weiterklicken vergessen): die folgenden rücken um denselben Betrag mit.
struct AbhakenUmBlatt: View {
    /// `gestartet`: Schritt mit eigenem Start (Ofen)
    enum Art { case angesetzt, begonnen, fertig, gestartet }

    let i: Int
    let titel: String
    var art = Art.fertig
    var erledigt: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var am = Date()
    @State private var inhalt: CGFloat = 0
    @State private var bereich: CGFloat = 0
    @State private var blatt: CGFloat = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                LabeledField(label: art == .angesetzt ? "Angesetzt um" : art == .begonnen ? "Begonnen um" : art == .gestartet ? "Gestartet um" : "Fertig um") {
                    DatePicker("", selection: $am, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "de_DE"))
                }
                Note(art == .angesetzt ? "Reife und Schritte rücken mit."
                     : art == .begonnen ? "„\(titel)“ hat zu dieser Uhrzeit begonnen, die folgenden Schritte rücken mit."
                     : art == .gestartet ? "„\(titel)“ wurde zu dieser Uhrzeit gestartet, die folgenden Schritte rücken mit."
                     : "„\(titel)“ war zu dieser Uhrzeit fertig. Der nächste Schritt beginnt dann, die folgenden rücken mit.")
            }
            .padding(Metrics.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { inhalt = $0 }
            .frame(maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bereich = $0 }
            .navigationTitle("Andere Uhrzeit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetClose { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button(art == .fertig ? "Erledigt" : art == .gestartet ? "Starten" : "Übernehmen") {
                        erledigt(am)
                        dismiss()
                    }
                }
            }
        }
        // Navigationsleiste und unterer Rand = Blatthöhe minus Inhaltsbereich; kommen zur Inhaltshöhe dazu.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { blatt = $0 }
        // Höhe passend zum Inhalt; ohne eigenen Hintergrund, damit das Blatt durchgehend grau bleibt.
        .presentationDetents([.height(inhalt > 0 && blatt > bereich ? inhalt + blatt - bereich : 280)])
    }
}

#if DEBUG
// MARK: - Timer-Karte

#Preview("Timer · reift") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .reift) }
#Preview("Timer · reif, Sauerteig prüfen") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .reifUeberfaellig) }
#Preview("Timer · Backen läuft") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .backen) }
#Preview("Timer · fertig") { TimerKarte(r: Vorschau.rezept).vorschauKarte().vorschau(timer: .fertig) }

#Preview("Blatt · Angesetzt um") {
    Color.clear.sheet(isPresented: .constant(true)) { AbhakenUmBlatt(i: 0, titel: "Sauerteig ansetzen", art: .angesetzt) { _ in } }
}
#Preview("Blatt · Andere Uhrzeit") {
    Color.clear.sheet(isPresented: .constant(true)) { AbhakenUmBlatt(i: 2, titel: "Formen, Stückgare") { _ in } }
}
#endif
