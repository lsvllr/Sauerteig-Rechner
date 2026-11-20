import SwiftUI

/// Sauerteig füttern: zuletzt (per Stift direkt im Feld nachtragbar), wieder fällig, Knopf „Gefüttert“. Den Rhythmus
/// stellt man in den Einstellungen ein. Erinnerung als lokale Mitteilung am Fälligkeitstag zur eingestellten Uhrzeit,
/// ab 2 Tagen drüber täglich (Mitteilungen.planeFuettern, Einstellungen).
/// Geöffnet als Popup über das Glas oben links (HauptAnsicht); `schliessen` schließt es nach „Gefüttert“.
struct FuetternKarte: View {
    var schliessen: (() -> Void)? = nil
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var db: Datenbank
    /// Kalender am Datum „Zuletzt gefüttert“ offen (Stift oder Tipp aufs Datum).
    @State private var waehlen = false
    @Environment(\.dynamicTypeSize) private var typo
    @Environment(\.brand) private var brand
    @AppStorage(Einstellungen.fuetternMitteilungenKey) private var erinnern = true
    @AppStorage(Einstellungen.fuetternMinuteKey) private var minute = Einstellungen.fuetternMinuteStandard

    private static let wochentag = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

    private func kurz(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.weekday, .day, .month], from: d)
        func zwei(_ x: Int) -> String { x < 10 ? "0\(x)" : "\(x)" }
        return "\(Self.wochentag[(c.weekday ?? 1) - 1]), \(zwei(c.day ?? 1)).\(zwei(c.month ?? 1))."
    }

    var body: some View {
        let f = db.fuetterung
        let heute = Date()
        let rest = f.restTage(heute: heute)
        let rhythmus = f.intervall == 7 ? "jede Woche" : f.intervall == 1 ? "jeden Tag" : "alle \(f.intervall) Tage"
        Card {
            HStack(spacing: 0) {
                CardTitle("Sauerteig füttern", hint: erinnern
                    ? "Rhythmus \(rhythmus). Ist er fällig, erinnert dich die App um \(Einstellungen.uhrzeit(minute)) Uhr per Mitteilung, ab 2 Tagen drüber jeden Tag. Rhythmus und Uhrzeit stellst du oben rechts in den Einstellungen ein. Mit dem Stift trägst du nach, wann du zuletzt gefüttert hast."
                    : "Rhythmus \(rhythmus), einstellbar oben rechts in den Einstellungen. Die Erinnerung per Mitteilung ist dort ausgeschaltet. Mit dem Stift trägst du nach, wann du zuletzt gefüttert hast.")
                Spacer(minLength: 8)
                Button { waehlen = true } label: {
                    Image(systemName: "pencil")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(brand.primary)
                        .frame(minWidth: 44, minHeight: 32, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Datum ändern")
            }
            // Erste Spalte so breit wie ihr Inhalt (wächst bei Bedarf mit), „Wieder fällig“ bekommt den Rest.
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zuletzt gefüttert").font(.footnote).foregroundStyle(Color.hhMuted)
                    // Das Datum bleibt Text; der Kalender öffnet sich als Popover daran, die Karte springt nicht.
                    // Die Markierung liegt im Hintergrund und ändert die Größe nicht.
                    Button { waehlen = true } label: {
                        Text(f.zuletzt.map(kurz) ?? "–").fontWeight(.bold).foregroundStyle(Color.hhInk)
                    }
                    .buttonStyle(.plain)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(brand.tint)
                            .padding(.horizontal, -6)
                            .padding(.vertical, -2)
                            .opacity(waehlen ? 1 : 0)
                    }
                    .animation(.easeOut(duration: 0.15), value: waehlen)
                    .popover(isPresented: $waehlen, arrowEdge: .top) {
                        DatePicker("Zuletzt gefüttert", selection: zuletztBinding(f), in: ...Date(), displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "de_DE"))
                            .tint(brand.primary)
                            .frame(width: 320)
                            .padding(12)
                            .presentationCompactAdaptation(.popover)
                    }
                    .accessibilityLabel("Zuletzt gefüttert")
                    .accessibilityValue(f.zuletzt.map(kurz) ?? "noch nicht eingetragen")
                    .accessibilityHint("Datum ändern")
                    if f.zuletzt == nil {
                        Text("noch nicht eingetragen").font(.footnote).foregroundStyle(Color.hhMuted)
                    }
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wieder fällig").font(.footnote).foregroundStyle(Color.hhMuted)
                    if let rest {
                        // Kurze Pille hinter dem Datum, lange („überfällig“) bzw. große Schrift darunter.
                        if rest >= 0 && !gross {
                            HStack(spacing: 8) { faelligText(f); faelligPill(rest) }
                        } else {
                            faelligText(f)
                            faelligPill(rest)
                        }
                    } else {
                        faelligText(f)
                        Text(rhythmus).font(.footnote).foregroundStyle(Color.hhMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, 6)
            Button("Gefüttert") {
                setze(zuletzt: Date(), intervall: f.intervall)
                app.zeige("Gefüttert")
                schliessen?()
            }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var gross: Bool { typo >= .xxLarge }

    private func faelligText(_ f: Fuetterung) -> some View {
        Text(f.faellig.map(kurz) ?? "–").fontWeight(.bold)
    }

    @ViewBuilder private func faelligPill(_ rest: Int) -> some View {
        if rest < 0 { Pill(rest == -1 ? "1 Tag überfällig" : "\(-rest) Tage überfällig", .overdue) }
        else if rest == 0 { Pill("heute fällig", .today) }
        else if rest == 1 { Pill("morgen", .soon) }
        else { Pill("in \(rest) Tagen", .ok) }
    }

    /// Datum für den Wähler; ohne Eintrag startet er bei heute.
    private func zuletztBinding(_ f: Fuetterung) -> Binding<Date> {
        Binding(
            get: { f.zuletzt ?? Date() },
            set: { d in
                setze(zuletzt: d, intervall: f.intervall)
                app.zeige("Gesichert")
                // Tag gewählt: kurz stehen lassen, dann schließen.
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    waehlen = false
                }
            })
    }

    private func setze(zuletzt: Date?, intervall: Int) {
        db.setzeFuetterung(zuletzt: zuletzt, intervall: intervall)
        let f = db.fuetterung
        Task {
            _ = await Mitteilungen.erlaubnis()
            await Mitteilungen.planeFuettern(f)
        }
    }
}

#if DEBUG
// MARK: - Füttern

#Preview("Füttern · nie eingetragen") { FuetternKarte().vorschauKarte().vorschau(fuettern: .nie) }
#Preview("Füttern · in ein paar Tagen") { FuetternKarte().vorschauKarte().vorschau(fuettern: .ok) }
#Preview("Füttern · heute fällig") { FuetternKarte().vorschauKarte().vorschau(fuettern: .heute) }
#Preview("Füttern · überfällig") { FuetternKarte().vorschauKarte().vorschau(fuettern: .ueberfaellig) }
#endif
