import SwiftUI

// Bausteine der Hauptseite (übernommen aus der Haushalt-App, Pages/SourdoughScreen.swift).

/// Regler mit Beschriftung und Wert (`.sd-slider`).
struct Regler: View {
    var label: String
    var wert: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int
    var dot: Color? = nil
    var badge: Pill? = nil
    var hint: String = ""
    @Environment(\.brand) private var brand

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if let dot { Circle().fill(dot).frame(width: 9, height: 9) }
                Text(label).font(.subheadline.weight(.semibold))
                if !hint.isEmpty { InfoInline(text: hint) }
                if let badge { badge }
                Spacer()
                Text(wert).font(.subheadline.weight(.bold).monospacedDigit()).contentTransition(.numericText())
            }
            Slider(value: Binding(get: { Double(value) }, set: { value = Int(($0 / Double(step)).rounded()) * step }),
                   in: Double(range.lowerBound)...Double(range.upperBound), step: Double(step))
                .tint(brand.primary)
                .sensoryFeedback(.selection, trigger: value)
        }
        .padding(.vertical, 4)
    }
}

/// Zutaten und Anleitung eines Schritts.
struct Anleitung: View {
    let art: SchrittArt?
    let r: Berechnung
    let w: SauerteigWerte

    private func zeile(_ l: String, _ v: String, info: String = "") -> some View {
        HStack(spacing: 4) {
            Text(l).foregroundStyle(Color.hhMuted)
            if !info.isEmpty { InfoInline(text: info) }
            Spacer()
            Text(v).fontWeight(.semibold).monospacedDigit()
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private func mehle(ohneRoggen: Bool = false, nurRoggen: Bool = false) -> some View {
        ForEach(Sorte.allCases.filter { r.mehl[$0] > 0 && (ohneRoggen ? $0 != .roggen : nurRoggen ? $0 == .roggen : true) }, id: \.self) { k in
            zeile(k.mehlName, "\(r.mehl[k]) g")
        }
    }

    @ViewBuilder
    private var sauerteigSalz: some View {
        zeile("Aktiver Sauerteig", "\(r.sauerteigGesamt) g")
        zeile("Salz", "\(r.salz) g")
        zeile("ggf. Gewürze/Nüsse", "")
    }

    /// [30, 60, 90] → „30, 60 und 90“
    static func aufzaehlung(_ z: [Int]) -> String {
        z.count > 1 ? z.dropLast().map(String.init).joined(separator: ", ") + " und \(z.last!)" : z.first.map(String.init) ?? ""
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, t in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(i + 1).").font(.subheadline.weight(.semibold)).foregroundStyle(Color.hhMuted)
                    Text(LocalizedStringKey(t)).font(.subheadline)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch art {
            case .ansetzen:
                zeile("Anstellgut", "\(r.anstellgut) g")
                zeile(r.sauerteigArt.sorte.mehlName, "\(r.sauerteigMehl) g", info: SauerteigDaten.mehlInfo)
                zeile("Wasser", "\(r.sauerteigWasser) ml")
                if !r.sauerteigHinweis.isEmpty { Pill(r.sauerteigHinweis, .today) }
                if !r.tempHinweis.isEmpty { Pill(r.tempHinweis, .today) }
                steps(["Anstellgut, Mehl und Wasser (\(r.verhaeltnis.text)) gründlich verrühren.",
                       "Abgedeckt bei \(w.sauerteigTemp) °C **\(r.zeitplan.sauerteigZeit)** reifen lassen.",
                       (r.sauerteigArt == .roggen
                        ? "Reif, wenn er Blasen wirft, gewölbt ist, feine Risse an der Oberfläche zeigt und säuerlich riecht."
                        : "Reif, wenn er sich etwa verdoppelt hat, gewölbt und durchgehend blasig ist und mild säuerlich riecht.")
                       + " Ergibt ca. \(r.sauerteigGesamt) g."])
            case .autolyse:
                mehle(ohneRoggen: true)
                zeile("Warmes Wasser", "\(r.hauptteigWasser) ml")
                steps(["Mehl und warmes Wasser verrühren, bis kein trockenes Mehl mehr zu sehen ist.",
                       "Abgedeckt **\(r.autolyseZeit)** ruhen lassen." + (r.mehl.roggen > 0 ? " Das Roggenmehl kommt erst danach dazu." : "")])
            case .mischen:
                if r.mitAutolyse {
                    Text("Zum Autolyseteig geben").font(.subheadline.weight(.bold))
                    mehle(nurRoggen: true)
                    sauerteigSalz
                    steps(r.weizenTeig
                          ? ["Alles zum Autolyseteig geben und kneten, bis der Teig glatt ist und sich vom Schüsselrand löst: von Hand ca. 10 Min"
                             + (r.mehl.dinkel > r.mehl.weizen ? ", Dinkel nur ca. 5 Min, er verträgt kein langes Kneten." : "."),
                             "Fenstertest: Ein Stück Teig lässt sich dünn ausziehen, ohne gleich zu reißen (Vollkorn reißt etwas früher)."]
                          : ["Alles zum Autolyseteig geben und gründlich verkneten, mit feuchten Händen."])
                } else {
                    mehle()
                    zeile("Warmes Wasser", "\(r.hauptteigWasser) ml")
                    sauerteigSalz
                    steps(["Alles gründlich zu einem Teig mischen, mit feuchten Händen."])
                }
            case .gare:
                if r.weizenTeig {
                    steps(["Abgedeckt bei \(w.gareTemp) °C gehen lassen: **\(r.ersteGare)**.",
                           "Nach **\(Self.aufzaehlung(r.faltZeiten)) Min** dehnen und falten: mit nasser Hand eine Seite hochziehen und über die Mitte legen, Schüssel drehen, rundum wiederholen. Danach in Ruhe gehen lassen.",
                           "Fertig, wenn der Teig um etwa die Hälfte gewachsen, gewölbt und luftig ist und Blasen am Rand zeigt."])
                } else {
                    steps(["Abgedeckt bei \(w.gareTemp) °C gehen lassen: **\(r.ersteGare)**.",
                           "Fertig, wenn der Teig sichtbar aufgegangen ist und Blasen zeigt."])
                }
            case .formen:
                if r.weizenTeig {
                    steps(["Teig auf eine leicht bemehlte Fläche geben"
                           + (w.teigTeilen ? ", halbieren (je ca. \(Int(r.einzelGewicht.rounded())) g)" : "")
                           + " und rund vorformen. \(Rechner.vorformenMin) Min entspannen lassen.",
                           "Straff formen, rund oder länglich, mit dem Schluss nach oben in einen bemehlten Gärkorb legen.",
                           "Stückgare bei \(w.gareTemp) °C: **\(r.stueckgare)**. Fertig, wenn eine Delle langsam und nicht ganz zurückfedert.",
                           "Oder abgedeckt über Nacht in den Kühlschrank (8-14 h) und kalt backen."])
                } else {
                    steps((w.teigTeilen ? ["Teig halbieren, je ca. \(Int(r.einzelGewicht.rounded())) g."] : [])
                          + ["Mit feuchten Händen rundwirken, in einen bemehlten Gärkorb legen.",
                             "Stückgare bei \(w.gareTemp) °C: **\(r.stueckgare)**. Fertig, wenn eine Delle nur zur Hälfte zurückfedert."])
                }
            case .ofen:
                steps(["Noch während der Stückgare: Ofen auf **\(r.anbackTemp) °C** vorheizen (\(r.vorheizen)), mittlere Schiene. So sind Teig und Ofen zugleich bereit.",
                       "Schüssel zum Abdecken oder ein Gefäß für Wasser (Schwaden) bereitstellen."])
            case .backen:
                steps([r.weizenTeig ? "Stürzen und einmal längs einschneiden, flach angesetzt und ca. 1 cm tief." : "Stürzen und kreuzförmig einschneiden.",
                       "\(r.dampfMin) Min bei \(r.anbackTemp) °C **mit Dampf** " + (w.teigTeilen ? "(2 Brote → engere Dampfphase)." : "(Schüssel über Brot oder Schwaden)."),
                       (r.anbackTemp > r.ofenTemp ? "Auf \(r.ofenTemp) °C herunterschalten, " : "Dann ") + "\(r.backZeit) **ohne Dampf** backen.",
                       "Klopftest: Fertiges Brot klingt hohl."])
            case .auskuehlen:
                steps(["Auf einem Gitter mindestens 2 Stunden auskühlen lassen, erst dann anschneiden."])
            case nil:
                EmptyView()
            }
        }
    }
}

#if DEBUG
#Preview("Anleitungen der Schritte") {
    let r = Vorschau.rezept
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(r.schritte.enumerated()), id: \.offset) { _, s in
                Card {
                    CardTitle(s.titel)
                    Anleitung(art: s.art, r: r, w: Vorschau.werte)
                }
            }
        }
        .padding(Metrics.gutter)
    }
    .hhBackground()
}
#endif
