import SwiftUI

/// Karte oben: „Sauerteig reift“ / „Backen läuft“ mit Countdown. Ohne laufenden Timer leer.
struct TimerKarte: View {
    let r: Berechnung
    @EnvironmentObject private var timer: BackTimer
    @State private var sicher = false

    var body: some View {
        if let l = timer.lauf {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let jetzt = ctx.date.timeIntervalSince1970 * 1000
                let reifen = l.phase == .reifen
                let i = l.naechster(jetzt)
                let n = i >= 0 ? l.schritte[i] : nil
                let fertig = !reifen && n == nil
                Card {
                    HStack {
                        CardTitle(reifen ? "Sauerteig reift" : (fertig ? "Fertig gebacken" : "Backen läuft"),
                                  hint: reifen ? "„Backen beginnen“ tippen, sobald der Sauerteig reif ist (Blasen, leicht gewölbt, säuerlicher Geruch). Ab dann laufen die Schritte mit Erinnerungen und auf dem Sperrbildschirm." : "")
                        Spacer()
                        Button(fertig ? "Schließen" : (sicher ? "Wirklich beenden?" : "Beenden")) {
                            if sicher || fertig { timer.beende(); sicher = false } else { sicher = true }
                        }
                        .buttonStyle(SecondaryButtonStyle(danger: sicher, small: true))
                    }
                    if reifen {
                        Text("Angesetzt um \(BackLauf.uhrzeit(l.start, jetzt: jetzt)) · reif ca. \(BackLauf.uhrzeit(l.reife[0], jetzt: jetzt))–\(BackLauf.uhrzeit(l.reife[1], jetzt: jetzt))")
                            .font(.footnote).foregroundStyle(Color.hhMuted)
                        if l.schritte.count > BackLauf.beginn {
                            let b = l.schritte[BackLauf.beginn]
                            Text("Backen beginnt ca. \(BackLauf.uhrzeit(b.at, jetzt: jetzt))").fontWeight(.bold)
                            Text(b.at > jetzt ? "≈ \(BackLauf.restzeit(b.at - jetzt))" : "Sauerteig prüfen")
                                .font(.system(size: 34, weight: .heavy).monospacedDigit())
                                .contentTransition(.numericText())
                        }
                        Button("Backen beginnen") { timer.beginneBacken() }.buttonStyle(PrimaryButtonStyle())
                    } else if let n {
                        Text("Nächster Schritt um \(BackLauf.uhrzeit(n.at, jetzt: jetzt))").font(.footnote).foregroundStyle(Color.hhMuted)
                        Text(n.titel).fontWeight(.bold)
                        Text(BackLauf.restzeit(n.at - jetzt))
                            .font(.system(size: 34, weight: .heavy).monospacedDigit())
                            .contentTransition(.numericText())
                    } else {
                        Text("Brot mindestens 2 Stunden auskühlen lassen, erst dann anschneiden.").foregroundStyle(Color.hhMuted)
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
    let i: Int
    let titel: String
    /// Ansetzzeit ändern statt Schritt abhaken
    var ansetzen = false
    var erledigt: (Date) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var am = Date()
    @State private var inhalt: CGFloat = 0
    @State private var bereich: CGFloat = 0
    @State private var blatt: CGFloat = 0

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                LabeledField(label: ansetzen ? "Angesetzt um" : "Erledigt um") {
                    DatePicker("", selection: $am, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "de_DE"))
                }
                Note(ansetzen ? "Reife und Schritte rücken mit." : "„\(titel)“ gilt ab dieser Uhrzeit, die folgenden Schritte rücken mit.")
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
                    Button(ansetzen ? "Übernehmen" : "Erledigt") {
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
    Color.clear.sheet(isPresented: .constant(true)) { AbhakenUmBlatt(i: 0, titel: "Sauerteig ansetzen", ansetzen: true) { _ in } }
}
#Preview("Blatt · Andere Uhrzeit") {
    Color.clear.sheet(isPresented: .constant(true)) { AbhakenUmBlatt(i: 2, titel: "Formen, Stückgare") { _ in } }
}
#endif
