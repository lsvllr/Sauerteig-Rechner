import ActivityKit
import SwiftUI
import UserNotifications

/// Einstellungen (Zahnrad oben rechts): Fütter-Rhythmus (gehört zu den Daten, gleicht sich ab), eine Kachel Mitteilungen (erlauben, Back-Timer mit Vorwarnung, Füttern-Erinnerung mit
/// Uhrzeit, Live-Aktivität; gelten für dieses Gerät, Einstellungen), dazu Geräte verknüpfen (Abgleich)
/// und die Sicherung in iCloud.
struct EinstellungenBlatt: View {
    @EnvironmentObject private var db: Datenbank
    @EnvironmentObject private var timer: BackTimer
    @EnvironmentObject private var abgleich: Abgleich
    @EnvironmentObject private var sicherung: Sicherung
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL

    @AppStorage(Einstellungen.backMitteilungenKey) private var backMelden = true
    @AppStorage(Einstellungen.fuetternMitteilungenKey) private var fuetternMelden = true
    @AppStorage(Einstellungen.fuetternMinuteKey) private var fuetternMinute = Einstellungen.fuetternMinuteStandard
    @AppStorage(Einstellungen.liveAktivitaetKey) private var live = true
    @AppStorage(Einstellungen.vorlaufKey) private var vorlauf = Einstellungen.vorlaufStandard

    @State private var status: UNAuthorizationStatus?
    @State private var liveErlaubt = true
    @State private var code = ""
    @State private var name = ""
    @State private var neuesKonto = false
    @State private var busy = false
    @State private var fehler: String?
    @State private var geraeteCode: (code: String, bis: Date)?
    @State private var trennenFragen = false
    @State private var schluesselCode = ""
    @State private var geraeteListe: [Abgleich.VerknuepftesGeraet]?
    @State private var entfernenFragen: Abgleich.VerknuepftesGeraet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    fuetternKarte
                    mitteilungenKarte
                    if abgleich.verfuegbar { kontoKarte }
                    sicherungKarte
                }
                .padding(.top, 8)
                .pageContainer()
                .padding(.bottom, 28)
            }
            .hhBackground()
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .task { await pruefe() }
        // Zurück aus den iOS-Einstellungen: Erlaubnis neu lesen.
        .onChange(of: phase) { _, p in if p == .active { Task { await pruefe() } } }
        .onChange(of: backMelden) { _, _ in Task { await timer.einstellungenGeaendert() } }
        .onChange(of: live) { _, _ in Task { await timer.einstellungenGeaendert() } }
        .onChange(of: vorlauf) { _, _ in Task { await timer.vorlaufGeaendert() } }
        .onChange(of: fuetternMelden) { _, _ in planeFuettern() }
        .onChange(of: fuetternMinute) { _, _ in planeFuettern() }
    }

    private func pruefe() async {
        status = await Mitteilungen.status()
        liveErlaubt = ActivityAuthorizationInfo().areActivitiesEnabled
    }

    private func planeFuettern() {
        let f = db.fuetterung
        Task { await Mitteilungen.planeFuettern(f) }
    }

    private func oeffneIOSEinstellungen() {
        if let u = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(u) }
    }

    // MARK: Karten

    /// Rhythmus fürs Füttern; ändert „Wieder fällig“ und plant die Erinnerung neu.
    private var fuetternKarte: some View {
        Card {
            CardTitle("Sauerteig füttern")
            IntStepper(label: "Rhythmus in Tagen", value: rhythmus, range: 1...60)
            Note(db.fuetterung.intervall == 7 ? "Jede Woche." : db.fuetterung.intervall == 1 ? "Jeden Tag." : "Alle \(db.fuetterung.intervall) Tage.")
        }
    }

    private var rhythmus: Binding<Int> {
        Binding(
            get: { db.fuetterung.intervall },
            set: { n in
                db.setzeFuetterung(zuletzt: db.fuetterung.zuletzt, intervall: n)
                planeFuettern()
            })
    }

    /// Eine Kachel für alles, was sich meldet: Erlaubnis, Back-Timer, Füttern-Erinnerung mit Uhrzeit, Live-Aktivität.
    private var mitteilungenKarte: some View {
        Card {
            CardTitle("Mitteilungen", hint: "Damit die App dich an die Schritte des Back-Timers und ans Füttern erinnert, auch wenn sie geschlossen ist. „Back-Timer“ meldet jeden Schritt des laufenden Back-Timers, auf Wunsch schon einige Minuten vorher. „Füttern“ erinnert am Fälligkeitstag zur gewählten Uhrzeit und ab 2 Tagen drüber jeden Tag, bis du fütterst. Die Live-Aktivität zeigt ab „Backen beginnen“ Countdown, Fortschritt und Knopf „Erledigt“ auf dem Sperrbildschirm und in der Dynamic Island.")
            switch status {
            case .none:
                EmptyView()
            case .notDetermined?:
                Button("Mitteilungen erlauben") {
                    Task {
                        _ = await Mitteilungen.erlaubnis()
                        await pruefe()
                        await timer.einstellungenGeaendert()
                        planeFuettern()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            case .denied?:
                Note("Mitteilungen sind in den iOS-Einstellungen für Sauerteig ausgeschaltet.")
                Button("iOS-Einstellungen öffnen") { oeffneIOSEinstellungen() }
                    .buttonStyle(SecondaryButtonStyle())
            default:
                FactRow("Erlaubnis in iOS", "erteilt")
            }
            RowDivider()
            Toggle("Back-Timer", isOn: $backMelden).tint(Brand().primary)
            if backMelden {
                HStack {
                    Text("Vorher erinnern")
                    Spacer()
                    MenuPicker(options: BackLauf.vorlaufWahl.map { Choice($0, $0 == 0 ? "Nein" : "\($0) Min vorher") },
                               selection: $vorlauf)
                }
            }
            RowDivider()
            Toggle("Füttern-Erinnerung", isOn: $fuetternMelden).tint(Brand().primary)
            if fuetternMelden {
                HStack {
                    Text("Uhrzeit")
                    Spacer()
                    DatePicker("Uhrzeit", selection: uhrzeit, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "de_DE"))
                }
            }
            RowDivider()
            Toggle("Live-Aktivität", isOn: $live).tint(Brand().primary)
            if live && !liveErlaubt {
                Note("Live-Aktivitäten sind in den iOS-Einstellungen für Sauerteig ausgeschaltet.")
                Button("iOS-Einstellungen öffnen") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .disabled(status == nil)
    }

    private var kontoKarte: some View {
        Card {
            CardTitle("Geräte verknüpfen", hint: "Rezepte, Füttern und Back-Timer liegen auf diesem Gerät. Mit einem Konto gleichen sie sich zwischen deinen Geräten ab, auch mit der Web-App. Der Server hält die Daten nur, solange mindestens zwei Geräte verknüpft sind.")
            if let k = abgleich.konto {
                FactRow("Konto", k.name)
                Note(abgleich.geraete >= 2
                     ? "\(abgleich.geraete) Geräte verknüpft, sie gleichen sich Ende-zu-Ende verschlüsselt ab. Der Server kann nichts davon lesen."
                     : "Nur dieses Gerät ist verknüpft, am Server liegt nichts. Verknüpfe ein weiteres, damit sie sich abgleichen.")
                if abgleich.schluesselFehlt {
                    RowDivider()
                    Text("Diesem Gerät fehlt der Schlüssel des Kontos. Auf einem anderen Gerät „Weiteres Gerät verknüpfen“ tippen und den Code hier eingeben.")
                        .font(.subheadline)
                        .foregroundStyle(Color.hhNegFg)
                    TextField("XXXX-XXXX-XXXX-XXXX", text: $schluesselCode)
                        .textFieldStyle(.hh)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    Button("Schlüssel holen") {
                        Task {
                            busy = true
                            defer { busy = false }
                            if let f = await abgleich.holeSchluessel(code: schluesselCode) { AppState.shared.zeige(f, .fehler) } else {
                                schluesselCode = ""
                                AppState.shared.zeige("Schlüssel übernommen")
                            }
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || schluesselCode.isEmpty)
                }
                if let g = geraeteCode {
                    RowDivider()
                    Text("Auf dem anderen Gerät in den Einstellungen unter „Geräte verknüpfen“ eingeben:")
                        .font(.subheadline)
                    Text(g.code)
                        .font(.title2.monospaced().weight(.semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity)
                    Note("Gilt bis \(g.bis.formatted(date: .omitted, time: .shortened)) Uhr, nur einmal.")
                } else {
                    Button("Weiteres Gerät verknüpfen") { Task { await holeCode() } }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(busy)
                }
                if let liste = geraeteListe {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(liste) { g in
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.istDieses ? "\(g.name) · dieses Gerät" : g.name)
                                        .font(.subheadline.weight(g.istDieses ? .semibold : .regular))
                                    Text("seit \(g.seit.formatted(date: .numeric, time: .shortened)) · zuletzt \(g.zuletztAktiv.formatted(date: .numeric, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if !g.istDieses {
                                    Button("Entfernen", role: .destructive) { entfernenFragen = g }
                                        .font(.subheadline)
                                        .disabled(busy)
                                }
                            }
                        }
                    }
                    .confirmationDialog("„\(entfernenFragen?.name ?? "")“ entfernen?", isPresented: Binding(
                        get: { entfernenFragen != nil }, set: { if !$0 { entfernenFragen = nil } }), titleVisibility: .visible,
                        presenting: entfernenFragen) { g in
                        Button("Entfernen", role: .destructive) { Task { await entferne(g) } }
                    } message: { _ in
                        Text("Das Gerät gleicht sich dann nicht mehr ab und muss neu verknüpft werden.")
                    }
                } else {
                    Button("Verknüpfte Geräte anzeigen") { Task { await ladeGeraete() } }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(busy)
                }
                Button("Dieses Gerät trennen", role: .destructive) { trennenFragen = true }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(busy)
                    .confirmationDialog("Dieses Gerät vom Konto trennen?", isPresented: $trennenFragen, titleVisibility: .visible) {
                        Button("Trennen", role: .destructive) { Task { await trenne() } }
                    } message: {
                        Text("Rezepte und Timer bleiben auf diesem Gerät, gleichen sich aber nicht mehr ab.")
                    }
            } else {
                Picker("", selection: $neuesKonto) {
                    Text("Gerätecode").tag(false)
                    Text("Einladungscode").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledField(label: neuesKonto ? "Einladungscode" : "Gerätecode",
                             hint: neuesKonto ? "Mit einem Einladungscode bekommst du ein eigenes Konto." : "Den Gerätecode zeigt ein Gerät, das schon im Konto ist („Weiteres Gerät verknüpfen“). Er gilt 15 Minuten.") {
                    TextField(neuesKonto ? "XXXX-XXXX-XXXX" : "XXXX-XXXX-XXXX-XXXX", text: $code)
                        .textFieldStyle(.hh)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                }
                if neuesKonto {
                    LabeledField(label: "Dein Name") {
                        TextField("", text: $name).textFieldStyle(.hh).textContentType(.nickname)
                    }
                }
                if let fehler { Note(fehler) }
                Button(neuesKonto ? "Konto erstellen" : "Verknüpfen") { Task { await verknuepfe() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy || code.trimmingCharacters(in: .whitespaces).isEmpty
                              || (neuesKonto && name.trimmingCharacters(in: .whitespaces).isEmpty))
            }
        }
    }

    private var sicherungKarte: some View {
        Card {
            CardTitle("iCloud-Sicherung", hint: "Rezepte, Füttern und Back-Timer werden in deiner iCloud gesichert (nur für dich sichtbar). Nach einer Neuinstallation oder auf einem neuen iPhone mit derselben Apple-ID kommen sie von selbst zurück.")
            switch sicherung.stand {
            case .aus(let t): Note(t)
            case .fehler(let t): Note(t)
            case .laeuft: FactRow("Stand", "sichert …")
            case .bereit:
                FactRow("Zuletzt gesichert", sicherung.zuletzt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "noch nie")
            }
            if case .aus = sicherung.stand {} else {
                Button("Jetzt sichern") { Task { await sicherung.abgleichen(); await sicherung.sichere(auchUnveraendert: true) } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(sicherung.stand == .laeuft)
            }
        }
    }

    private func verknuepfe() async {
        busy = true
        defer { busy = false }
        let c = code.trimmingCharacters(in: .whitespaces)
        fehler = neuesKonto
            ? await abgleich.registriere(code: c, name: name.trimmingCharacters(in: .whitespaces))
            : await abgleich.verknuepfe(code: c)
        if fehler == nil {
            code = ""
            AppState.shared.zeige("Verknüpft mit „\(abgleich.konto?.name ?? "")“")
        }
    }

    private func holeCode() async {
        busy = true
        defer { busy = false }
        switch await abgleich.geraetecode() {
        case .success(let g): geraeteCode = g
        case .failure(let f): AppState.shared.zeige(f.text, .fehler)
        }
    }

    private func ladeGeraete() async {
        busy = true
        defer { busy = false }
        switch await abgleich.verknuepfteGeraete() {
        case .success(let l): geraeteListe = l
        case .failure(let f): AppState.shared.zeige(f.text, .fehler)
        }
    }

    private func entferne(_ g: Abgleich.VerknuepftesGeraet) async {
        busy = true
        if let f = await abgleich.entferne(g) { AppState.shared.zeige(f, .fehler) } else {
            AppState.shared.zeige("„\(g.name)“ entfernt")
        }
        busy = false
        await ladeGeraete()
    }

    private func trenne() async {
        busy = true
        defer { busy = false }
        if let f = await abgleich.trenne() { AppState.shared.zeige(f, .fehler) } else {
            geraeteCode = nil
            geraeteListe = nil
            AppState.shared.zeige("Getrennt, die Daten bleiben auf diesem Gerät")
        }
    }

    /// Minuten nach Mitternacht als Datum von heute (für den DatePicker).
    private var uhrzeit: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: fuetternMinute / 60, minute: fuetternMinute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let k = Calendar.current.dateComponents([.hour, .minute], from: d)
                fuetternMinute = (k.hour ?? 8) * 60 + (k.minute ?? 0)
            })
    }
}

#if DEBUG
#Preview("Blatt · Einstellungen") {
    Color.clear.sheet(isPresented: .constant(true)) { EinstellungenBlatt() }.vorschau()
}
#endif
