import SwiftUI

/// Sauerteig füttern: zuletzt, wieder fällig, Knopf „Gefüttert“, Rhythmus ändern. Erinnerung als lokale Mitteilung
/// am Fälligkeitstag morgens (Mitteilungen.planeFuettern).
struct FuetternKarte: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var db: Datenbank
    @State private var bearbeiten = false

    private static let wochentag = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    private func kurz(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.weekday, .day, .month], from: d)
        func zwei(_ x: Int) -> String { x < 10 ? "0\(x)" : "\(x)" }
        return "\(Self.wochentag[(c.weekday ?? 1) - 1]), \(zwei(c.day ?? 1)).\(zwei(c.month ?? 1))."
    }

    private func tage(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }

    var body: some View {
        let f = db.fuetterung
        let heute = Date()
        let rest = f.faellig.map { tage(heute, $0) }
        let rhythmus = f.intervall == 7 ? "jede Woche" : f.intervall == 1 ? "jeden Tag" : "alle \(f.intervall) Tage"
        Card {
            HStack {
                Text("Sauerteig füttern").font(.headline)
                Spacer()
                Button("Ändern") { bearbeiten = true }.buttonStyle(SecondaryButtonStyle(small: true))
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zuletzt gefüttert").font(.footnote).foregroundStyle(Color.hhMuted)
                    Text(f.zuletzt.map(kurz) ?? "–").fontWeight(.bold)
                    Text(f.zuletzt.map { let t = tage($0, heute); return t <= 0 ? "heute" : t == 1 ? "gestern" : "vor \(t) Tagen" } ?? "noch nicht eingetragen")
                        .font(.footnote).foregroundStyle(Color.hhMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wieder fällig").font(.footnote).foregroundStyle(Color.hhMuted)
                    Text(f.faellig.map(kurz) ?? "–").fontWeight(.bold)
                    if let rest {
                        if rest < 0 { Pill(rest == -1 ? "1 Tag überfällig" : "\(-rest) Tage überfällig", .overdue) }
                        else if rest == 0 { Pill("heute fällig", .today) }
                        else if rest == 1 { Pill("morgen", .soon) }
                        else { Pill("in \(rest) Tagen", .ok) }
                    } else {
                        Text(rhythmus).font(.footnote).foregroundStyle(Color.hhMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Gefüttert") { setze(zuletzt: Date(), intervall: f.intervall, text: "Gefüttert") }
                .buttonStyle(PrimaryButtonStyle())
            Note("Rhythmus \(rhythmus). Ist er fällig, erinnert dich die App um \(Mitteilungen.fuetternStunde) Uhr per Mitteilung.")
        }
        .sheet(isPresented: $bearbeiten) {
            FuetternBlatt(f: f) { zuletzt, intervall in setze(zuletzt: zuletzt, intervall: intervall, text: "Gesichert") }
        }
    }

    private func setze(zuletzt: Date?, intervall: Int, text: String) {
        db.setzeFuetterung(zuletzt: zuletzt, intervall: intervall)
        app.zeige(text)
        let f = db.fuetterung
        Task {
            _ = await Mitteilungen.erlaubnis()
            await Mitteilungen.planeFuettern(f)
        }
    }
}

private struct FuetternBlatt: View {
    let f: Fuetterung
    var sichern: (Date?, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var intervall = 7
    @State private var datum = Date()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                IntStepper(label: "Rhythmus in Tagen", value: $intervall, range: 1...60)
                LabeledField(label: "Zuletzt gefüttert am", hint: "Zum Nachtragen, wenn du vergessen hast, auf „Gefüttert“ zu tippen.") {
                    DatePicker("", selection: $datum, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "de_DE"))
                }
                Spacer()
            }
            .padding(Metrics.gutter)
            .background(Color.hhBg)
            .navigationTitle("Füttern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetClose { dismiss() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        sichern(datum, intervall)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            intervall = f.intervall
            datum = f.zuletzt ?? Date()
        }
    }
}
