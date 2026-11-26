import PhotosUI
import SwiftUI

/// Wurzel der App: Tabs „Backen“ (Rechner, Timer) und „Tagebuch“ mit der Tab-Leiste von iOS.
struct Wurzel: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var db: Datenbank

    var body: some View {
        TabView(selection: $app.tab) {
            HauptAnsicht()
                .hereinGleiten(.backen)
                .tabItem { Label("Backen", systemImage: "oven") }
                .tag(AppState.Tab.backen)
            TagebuchAnsicht()
                .hereinGleiten(.tagebuch)
                .tabItem { Label("Tagebuch", systemImage: "book") }
                .tag(AppState.Tab.tagebuch)
        }
        .onAppear { db.uebernimmRezepte() }
    }
}

/// Tab-Wechsel mit Bewegung: `TabView` tauscht die Seiten ohne Animation. Wird `tab` gewählt, gleitet seine Seite
/// von der Seite herein, auf der ihr Tab in der Leiste liegt (Backen links, Tagebuch rechts), und blendet dabei
/// auf. Der Hintergrund steht still, damit beim Gleiten keine Kante sichtbar wird.
private struct HereinGleiten: ViewModifier {
    let tab: AppState.Tab
    @EnvironmentObject private var app: AppState
    @State private var breite: CGFloat = 390
    @State private var mal = 0

    private struct Stand {
        var x: CGFloat = 0
        var deckkraft: Double = 1
    }

    func body(content: Content) -> some View {
        ZStack {
            Color.hhBg.ignoresSafeArea()
            content
                .keyframeAnimator(initialValue: Stand(), trigger: mal) { c, s in
                    c.offset(x: s.x).opacity(s.deckkraft)
                } keyframes: { _ in
                    KeyframeTrack(\.x) {
                        MoveKeyframe(tab == .tagebuch ? breite * 0.35 : -breite * 0.35)
                        SpringKeyframe(0, duration: 0.42, spring: .snappy)
                    }
                    KeyframeTrack(\.deckkraft) {
                        MoveKeyframe(0)
                        LinearKeyframe(1, duration: 0.2)
                    }
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { breite = $0 }
        .onChange(of: app.tab) { alt, neu in
            if neu == tab && alt != neu { mal += 1 }
        }
    }
}

extension View {
    fileprivate func hereinGleiten(_ tab: AppState.Tab) -> some View { modifier(HereinGleiten(tab: tab)) }
}

/// Tab „Tagebuch“: jedes gesicherte Rezept und jedes fertig gebackene Brot (Core/Tagebuch.swift), neueste zuerst.
struct TagebuchAnsicht: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var db: Datenbank
    @EnvironmentObject private var abgleich: Abgleich
    @State private var pfad: [String] = []
    @State private var ausgeblendet: Set<String> = []

    var body: some View {
        let eintraege = db.backeintraege.filter { !ausgeblendet.contains($0.id) }
        let _ = abgleich.bilderStand // neu angekommene Fotos zeigen
        NavigationStack(path: $pfad) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if eintraege.isEmpty {
                        Card {
                            Text("Noch nichts im Tagebuch").font(.headline)
                            Note("Im Tab „Backen“ mit „Im Tagebuch sichern“ ein Rezept ablegen. Fertig gebackene Brote aus dem Back-Timer landen von selbst hier.")
                        }
                    }
                    ForEach(eintraege) { e in
                        NavigationLink(value: e.id) { EintragZeile(e: e) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)
                .pageContainer()
                .padding(.bottom, 28)
            }
            .hhBackground()
            .navigationTitle("Tagebuch")
            .navigationDestination(for: String.self) { uid in
                EintragAnsicht(uid: uid) { loesche($0) }
            }
        }
        .toastUnten()
        .onAppear { oeffneAngefragten() }
        .onChange(of: app.eintrag) { _, _ in oeffneAngefragten() }
    }

    private func oeffneAngefragten() {
        guard let u = app.eintrag else { return }
        app.eintrag = nil
        ausgeblendet.remove(u)
        pfad = [u]
    }

    private func loesche(_ e: Backeintrag) {
        pfad = []
        app.loescheMitRueckgaengig("Eintrag gelöscht",
                                   ausblenden: { _ = withAnimation(Metrics.move) { ausgeblendet.insert(e.id) } },
                                   zurueck: { _ = withAnimation(Metrics.move) { ausgeblendet.remove(e.id) } },
                                   endgueltig: {
                                       db.loescheEintrag(e.id)
                                       for id in e.bilder {
                                           Bilder.loesche(id)
                                           abgleich.loescheBild(id)
                                       }
                                   })
    }
}

private struct EintragZeile: View {
    let e: Backeintrag

    var body: some View {
        HStack(spacing: 12) {
            Vorschaubild(id: e.bilder.first(where: Bilder.vorhanden), groesse: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(e.name).fontWeight(.semibold).foregroundStyle(Color.hhInk).lineLimit(2)
                HStack(spacing: 8) {
                    Text(e.gebacken.formatted(.dateTime.day().month().year().locale(Locale(identifier: "de_DE"))))
                        .font(.footnote).foregroundStyle(Color.hhMuted)
                    if e.bewertung > 0 { Sterne(wert: e.bewertung, font: .caption2) }
                }
                if e.verlauf != nil && e.bewertung == 0 {
                    Pill("Noch nicht bewertet", .today)
                } else if let a = e.analyse {
                    Pill(a.gareText, a.gare == "optimal" ? .ok : .neutral, icon: "sparkles")
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.hhMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .contentShape(Rectangle())
    }
}

/// Kleines quadratisches Foto; ohne Foto ein Platzhalter.
private struct Vorschaubild: View {
    let id: String?
    var groesse: CGFloat

    var body: some View {
        Group {
            if let id, let b = Bilder.lade(id) {
                Image(uiImage: b).resizable().scaledToFill()
            } else {
                Group {
                    if id == nil {
                        // Kein Brot unter den SF Symbols: Emoji, grau wie die übrigen Platzhalter
                        Text("🍞").font(.system(size: groesse * 0.46)).grayscale(1).opacity(0.55)
                    } else {
                        Image(systemName: "icloud.slash").font(.system(size: groesse * 0.36)).foregroundStyle(Color.hhMuted)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.hhFill)
            }
        }
        .frame(width: groesse, height: groesse)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Fünf Sterne; mit `setze` zum Antippen (gleicher Stern noch einmal = zurück auf 0).
struct Sterne: View {
    var wert: Int
    var font: Font = .body
    var setze: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: setze == nil ? 1 : 2) {
            ForEach(1...5, id: \.self) { i in
                let an = i <= wert
                let stern = Image(systemName: an ? "star.fill" : "star")
                    .font(font)
                    .foregroundStyle(an ? Color.hhWarn : Color.hhMuted.opacity(0.6))
                if let setze {
                    Button {
                        Haptics.tap()
                        setze(i == wert ? 0 : i)
                    } label: { stern.frame(minWidth: 36, minHeight: 36) }
                        .buttonStyle(.plain)
                } else {
                    stern
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bewertung")
        .accessibilityValue(wert == 0 ? "keine" : "\(wert) von 5 Sternen")
        .accessibilityAdjustableAction { r in
            guard let setze else { return }
            switch r {
            case .increment: setze(min(5, wert + 1))
            case .decrement: setze(max(0, wert - 1))
            @unknown default: break
            }
        }
    }
}

/// Was an `/api/ki/krume` geht: Fotos (JPEG, Base64) und Angaben zum Backen.
private struct KIAnfrage: Encodable {
    var bilder: [String]
    var kontext: KIKontext
}

private struct GrossesBild: Identifiable {
    var id: String
}

/// Ein Eintrag: Fotos, Bewertung, Notiz, KI-Analyse, alle Einstellungen und Mengen, Verlauf des Timers.
struct EintragAnsicht: View {
    let uid: String
    var loeschen: (Backeintrag) -> Void
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var db: Datenbank
    @EnvironmentObject private var abgleich: Abgleich
    @State private var notiz = ""
    @State private var notizGeladen = false
    @State private var auswahl: [PhotosPickerItem] = []
    @State private var kameraOffen = false
    @State private var gross: GrossesBild?
    @State private var umbenennen = false
    @State private var neuerName = ""
    @State private var analysiert = false
    @State private var loeschenFragen = false

    private static let maxBilder = 8

    var body: some View {
        let _ = abgleich.bilderStand // neu angekommene Fotos zeigen
        Group {
            if let e = db.backeintrag(uid) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        kopf(e)
                        fotos(e)
                        bewertung(e)
                        notizKarte(e)
                        kiKarte(e)
                        rezeptKarte(e)
                        if let l = e.verlauf { verlaufKarte(e, l) }
                    }
                    .padding(.top, 8)
                    .pageContainer()
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { neuerName = e.eigenerName; umbenennen = true } label: { Label("Umbenennen", systemImage: "pencil") }
                            Button(role: .destructive) { loeschenFragen = true } label: { Label("Löschen", systemImage: "trash") }
                        } label: { Image(systemName: "ellipsis.circle") }
                            .accessibilityLabel("Mehr")
                    }
                }
                .alert("Name", isPresented: $umbenennen) {
                    TextField(Backeintrag.automatischerName(e.werte), text: $neuerName)
                    Button("Abbrechen", role: .cancel) {}
                    Button("Sichern") { db.benenneEintrag(uid, neuerName) }
                } message: { Text("Leer lassen: Name aus der Mehlmischung.") }
                .confirmationDialog("„\(e.name)“ löschen?", isPresented: $loeschenFragen, titleVisibility: .visible) {
                    Button("Löschen", role: .destructive) { loeschen(e) }
                } message: { Text("Mit Fotos und Notizen.") }
                .onAppear {
                    if !notizGeladen {
                        notiz = e.notiz
                        notizGeladen = true
                    }
                    if app.bewerten {
                        app.bewerten = false
                        app.zeige("Fertig gebacken. Wie ist es geworden?", .info)
                    }
                }
                .onDisappear { sichereNotiz() }
                .onChange(of: auswahl) { _, items in uebernimm(items, e) }
                .fullScreenCover(isPresented: $kameraOffen) {
                    KameraAufnahme { bild in
                        kameraOffen = false
                        if let bild { fuegeHinzu([bild], e) }
                    }
                    .ignoresSafeArea()
                }
                .fullScreenCover(item: $gross) { b in grossesBild(b.id, e) }
            } else {
                Note("Diesen Eintrag gibt es nicht mehr.").padding(Metrics.gutter)
            }
        }
        .hhBackground()
        .navigationTitle("Eintrag")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Kopf

    private func kopf(_ e: Backeintrag) -> some View {
        let besser = e.analyse?.stellbar ?? []
        return Card {
            Text(e.name).font(.title3.weight(.heavy)).foregroundStyle(Color.hhInk)
            HStack(spacing: 8) {
                Text(e.gebacken.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(Locale(identifier: "de_DE"))))
                    .font(.footnote).foregroundStyle(Color.hhMuted)
                Pill(e.verlauf != nil ? "Gebacken mit Timer" : "Gesichert", .neutral)
            }
            Button {
                app.lade(e.werte, "„\(e.name)“ geladen")
            } label: { Label("Nochmal backen", systemImage: "arrow.counterclockwise") }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 4)
            if !besser.isEmpty {
                Button {
                    app.lade(e.werte.mitVorschlaegen(besser), "Mit Verbesserungen geladen")
                } label: { Label("Mit Verbesserungen laden", systemImage: "sparkles") }
                    .buttonStyle(SecondaryButtonStyle(fullWidth: true))
            }
        }
    }

    // MARK: Fotos

    private func fotos(_ e: Backeintrag) -> some View {
        Card {
            CardTitle("Fotos", hint: "Für die Analyse: Brot ganz auskühlen lassen, in der Mitte durchschneiden und den Anschnitt gerade von vorn bei Tageslicht fotografieren. Ein zweites Foto von außen zeigt Kruste und Ausbund.")
            if !e.bilder.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(e.bilder, id: \.self) { id in
                            Button { if Bilder.vorhanden(id) { gross = GrossesBild(id: id) } } label: { Vorschaubild(id: id, groesse: 96) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button(role: .destructive) { entferneBild(id, e) } label: { Label("Foto entfernen", systemImage: "trash") }
                                }
                                .accessibilityLabel(Bilder.vorhanden(id) ? "Foto ansehen" : "Foto auf einem anderen Gerät")
                        }
                    }
                }
                if e.bilder.contains(where: { !Bilder.vorhanden($0) }) {
                    Note(abgleich.konto == nil
                         ? "Fotos mit Wolke liegen auf einem anderen Gerät."
                         : "Fotos mit Wolke kommen, sobald das Gerät, auf dem sie aufgenommen wurden, online war.")
                }
            }
            if e.bilder.count < Self.maxBilder {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $auswahl, maxSelectionCount: Self.maxBilder - e.bilder.count, matching: .images) {
                        Label("Foto wählen", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    if KameraAufnahme.verfuegbar {
                        Button { kameraOffen = true } label: { Label("Kamera", systemImage: "camera") }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
            }
        }
    }

    private func grossesBild(_ id: String, _ e: Backeintrag) -> some View {
        NavigationStack {
            Group {
                if let b = Bilder.lade(id, klein: false) {
                    Image(uiImage: b).resizable().scaledToFit()
                } else {
                    Note("Foto nicht gefunden")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                SheetClose { gross = nil }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        gross = nil
                        entferneBild(id, e)
                    } label: { Image(systemName: "trash") }
                        .accessibilityLabel("Foto entfernen")
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func uebernimm(_ items: [PhotosPickerItem], _ e: Backeintrag) {
        guard !items.isEmpty else { return }
        Task {
            var bilder: [UIImage] = []
            for i in items {
                if let d = try? await i.loadTransferable(type: Data.self), let b = UIImage(data: d) { bilder.append(b) }
            }
            auswahl = []
            fuegeHinzu(bilder, e)
        }
    }

    /// Verkleinern und speichern abseits der Oberfläche, dann die IDs am Eintrag anhängen.
    private func fuegeHinzu(_ bilder: [UIImage], _ e: Backeintrag) {
        guard !bilder.isEmpty else { return }
        Task {
            let ids = await Task.detached(priority: .userInitiated) { bilder.compactMap { Bilder.speichere($0) } }.value
            guard !ids.isEmpty else { return app.zeige("Foto ließ sich nicht speichern", .fehler) }
            let jetzt = db.backeintrag(uid)?.bilder ?? e.bilder
            db.setzeBilder(uid, Array((jetzt + ids).prefix(Self.maxBilder)))
        }
    }

    private func entferneBild(_ id: String, _ e: Backeintrag) {
        let jetzt = db.backeintrag(uid)?.bilder ?? e.bilder
        db.setzeBilder(uid, jetzt.filter { $0 != id })
        Bilder.loesche(id)
        abgleich.loescheBild(id)
    }

    // MARK: Bewertung, Notiz

    private func bewertung(_ e: Backeintrag) -> some View {
        Card {
            Text("Wie ist es geworden?").font(.headline)
            Sterne(wert: e.bewertung, font: .title2) { db.bewerteEintrag(uid, gesamt: $0) }
            RowDivider()
            ForEach(Kriterien.Art.allCases, id: \.self) { k in
                HStack {
                    Text(k.name).font(.subheadline).foregroundStyle(Color.hhMuted)
                    Spacer()
                    Sterne(wert: e.kriterien[k], font: .subheadline) { v in
                        var neu = e.kriterien
                        neu[k] = v
                        db.bewerteEintrag(uid, kriterien: neu)
                    }
                }
            }
        }
    }

    private func notizKarte(_ e: Backeintrag) -> some View {
        Card {
            CardTitle("Notizen", hint: "Was ist dir aufgefallen? Zum Beispiel: Teig sehr klebrig, Sauerteig erst nach 12 h reif, Raum kühl, zu früh angeschnitten. Fließt in die Analyse ein.")
            TextEditor(text: $notiz)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).strokeBorder(Color.hhLine))
                .overlay(alignment: .topLeading) {
                    if notiz.isEmpty {
                        Text("Wie war Teig, Gare, Ofentrieb, Geschmack?")
                            .foregroundStyle(Color.hhMuted.opacity(0.7))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                // Gespeichert eine Sekunde nach dem letzten Tippen (nicht bei jedem Zeichen in die Datei).
                .task(id: notiz) {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    sichereNotiz()
                }
        }
    }

    private func sichereNotiz() {
        guard notizGeladen, let e = db.backeintrag(uid), e.notiz != notiz else { return }
        db.setzeNotiz(uid, notiz)
    }

    // MARK: KI

    private func kiKarte(_ e: Backeintrag) -> some View {
        let lokal = e.bilder.filter(Bilder.vorhanden)
        return Card {
            CardTitle("Krume analysieren", hint: "Gemini wertet das Foto vom Anschnitt aus, zusammen mit Mischung, Temperaturen, tatsächlichen Zeiten, Bewertung und Notiz sowie bis zu drei früheren Backen derselben Mischung. Vorschläge lassen sich mit „Mit Verbesserungen laden“ übernehmen.")
            if let a = e.analyse { analyseInhalt(a, e) }
            if analysiert {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Gemini sieht sich das Brot an …").font(.subheadline).foregroundStyle(Color.hhMuted)
                }
                .frame(minHeight: Metrics.ctlHeight)
            } else {
                Button { analysiere(e) } label: {
                    Label(e.analyse == nil ? "Analysieren" : "Neu analysieren", systemImage: "sparkles")
                }
                .buttonStyle(SecondaryButtonStyle(fullWidth: true))
                .disabled(lokal.isEmpty || abgleich.konto == nil)
            }
            if abgleich.konto == nil {
                Note("Die Analyse läuft über deinen Server und braucht ein Konto (Einstellungen → Geräte verknüpfen).")
            } else if lokal.isEmpty {
                Note("Erst ein Foto vom Anschnitt hinzufügen.")
            } else {
                Note("Fotos und Angaben gehen über deinen Server an Google Gemini. Dort wird nichts gespeichert.")
            }
        }
    }

    @ViewBuilder
    private func analyseInhalt(_ a: KrumenAnalyse, _ e: Backeintrag) -> some View {
        FlowLayout(spacing: 6) {
            Pill(a.gareText, a.gare == "optimal" ? .ok : (a.gare == "unklar" ? .neutral : .today))
            Pill("Porung \(a.krume.porung)", .neutral)
            Pill(a.krume.gleichmaessig ? "gleichmäßig" : "ungleichmäßig", .neutral)
            Pill("Sicherheit \(a.sicherheit)", a.sicherheit == "niedrig" ? .today : .neutral)
        }
        Text(a.diagnose).font(.subheadline).foregroundStyle(Color.hhInk).fixedSize(horizontal: false, vertical: true)
        if !a.krume.auffaelligkeiten.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(a.krume.auffaelligkeiten, id: \.self) { t in
                    Label(t, systemImage: "magnifyingglass").font(.footnote).foregroundStyle(Color.hhMuted)
                }
            }
        }
        if !a.kruste.isEmpty { FactRow("Kruste", a.kruste) }
        if !a.vorschlaege.isEmpty {
            Text("Vorschläge").font(.subheadline.weight(.bold)).padding(.top, 4)
            ForEach(Array(a.vorschlaege.enumerated()), id: \.offset) { _, v in
                VStack(alignment: .leading, spacing: 2) {
                    if let p = Stellgroesse(rawValue: v.parameter), v.aenderung != 0 {
                        let alt = e.werte[keyPath: p.pfad]
                        Label("\(p.name): \(alt) → \(p.neu(alt, v.aenderung)) \(p.einheit)", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Label(v.text, systemImage: "lightbulb").font(.subheadline.weight(.semibold))
                    }
                    if !v.grund.isEmpty { Note(v.grund) }
                }
            }
        }
        RowDivider()
    }

    private func analysiere(_ e: Backeintrag) {
        let ids = Array(e.bilder.filter(Bilder.vorhanden).prefix(3))
        guard !ids.isEmpty else { return }
        sichereNotiz()
        let aktuell = db.backeintrag(uid) ?? e
        let kontext = KIKontext(aktuell, alle: db.backeintraege)
        withAnimation(Metrics.move) { analysiert = true }
        Task {
            let bilder = await Task.detached(priority: .userInitiated) { ids.compactMap { Bilder.fuerKI($0) } }.value
            defer { withAnimation(Metrics.move) { analysiert = false } }
            guard !bilder.isEmpty, let body = try? JSONEncoder().encode(KIAnfrage(bilder: bilder, kontext: kontext)) else {
                return app.zeige("Fotos ließen sich nicht lesen", .fehler)
            }
            switch await abgleich.analysiereKrume(body) {
            case .success(var a):
                a.zeit = (Date().timeIntervalSince1970 * 1000).rounded()
                db.setzeAnalyse(uid, a)
                app.zeige("Analyse fertig")
            case .failure(let f):
                app.zeige(f.text, .fehler)
            }
        }
    }

    // MARK: Rezept, Verlauf

    private func rezeptKarte(_ e: Backeintrag) -> some View {
        let w = e.werte
        let m = e.mengen ?? Mengen(Rechner.rezept(w.eingabe))
        let a = w.anteile
        let anteile = Sorte.allCases.filter { a[$0] > 0 }.map { "\($0.name) \(a[$0]) %" }.joined(separator: " · ")
        let hauptMehl = Sorte.allCases.filter { m.mehl[$0] > 0 }.map { "\(m.mehl[$0]) g \($0.name)" }.joined(separator: ", ")
        return Card {
            Text("Rezept").font(.headline)
            FactRow("Mischung", SauerteigDaten.mischung(w.mischung)?.name ?? "Eigene Mischung")
            FactRow("Anteile", anteile)
            FactRow("Teig", "\(m.teiggewicht) g" + (w.teigTeilen ? " (2 Brote)" : ""))
            FactRow("Hydration", "\(w.hydration) %")
            FactRow("Anstellgut", "\(w.anstellgut) g")
            FactRow("Temperaturen", "Sauerteig \(w.sauerteigTemp) °C · Gare \(w.gareTemp) °C")
            FactRow("Ofen", "\(m.anbackTemp) °C Dampf \(m.dampfMin) Min, dann \(m.ofenTemp) °C \(m.backZeit)")
            RowDivider()
            FactRow("Sauerteig", "\(m.sauerteigMehl) g Mehl · \(m.sauerteigWasser) g Wasser")
            FactRow("Hauptteig", "\(hauptMehl) · \(m.hauptteigWasser) g Wasser · \(m.salz) g Salz")
            FactRow("Zeiten", "Reife \(m.sauerteigZeit) · Gare \(m.ersteGare) · Stückgare \(m.stueckgare)")
        }
    }

    private func verlaufKarte(_ e: Backeintrag, _ l: BackLauf) -> some View {
        let reife = e.reife
        let plan = Rechner.rezept(e.werte.eingabe).schritte
        return Card {
            CardTitle("Verlauf", hint: "Tatsächliche Zeiten aus dem Back-Timer, daneben die Abweichung vom Plan.")
            FactRow("Angesetzt", BackLauf.uhrzeit(l.start, jetzt: 0))
            if let t = reife.tatsaechlich {
                FactRow("Sauerteig reif nach", "\(Rechner.hm(t)) h" + (reife.geplant.map { " (geplant \(Rechner.hm($0.0))–\(Rechner.hm($0.1)) h)" } ?? ""))
            }
            RowDivider()
            ForEach(Array(l.schritte.enumerated()), id: \.offset) { i, s in
                let erledigt = i < l.offenAb
                HStack(alignment: .firstTextBaseline) {
                    Text(s.titel).font(.subheadline).foregroundStyle(erledigt ? Color.hhInk : Color.hhMuted)
                    Spacer(minLength: 8)
                    if erledigt {
                        Text(BackLauf.uhrzeit(s.at, jetzt: 0) + abweichung(i, s, l, plan))
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                    } else {
                        Text("nicht abgehakt").font(.footnote).foregroundStyle(Color.hhMuted)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    /// „ (+0:40)“: so viel später (früher) als geplant, gemessen ab dem Ansetzen.
    private func abweichung(_ i: Int, _ s: TimerSchritt, _ l: BackLauf, _ plan: [Schritt]) -> String {
        guard i > 0, plan.indices.contains(i) else { return "" }
        let d = Int(((s.at - l.start) / BackLauf.min).rounded()) - plan[i].t
        guard abs(d) >= 5 else { return "" }
        return " (\(d > 0 ? "+" : "−")\(Rechner.hm(abs(d))))"
    }
}

#if DEBUG
#Preview("Tagebuch · Liste") { TagebuchAnsicht().vorschau(rezepte: true) }
#Preview("Tagebuch · leer") { TagebuchAnsicht().vorschau() }
#Preview("Tagebuch · Eintrag") {
    NavigationStack { EintragAnsicht(uid: Vorschau.eintragUid) { _ in } }.vorschau(rezepte: true)
}
#Preview("App · Tabs") { Wurzel().vorschau(timer: .backen, rezepte: true) }
#endif
