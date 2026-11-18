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

    private func zeile(_ l: String, _ v: String) -> some View {
        HStack { Text(l).foregroundStyle(Color.hhMuted); Spacer(); Text(v).fontWeight(.semibold).monospacedDigit() }.font(.subheadline)
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
        zeile("Kümmel (optional)", "\(r.kuemmel.replacingOccurrences(of: ".", with: ",")) TL")
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
                zeile("Roggen-Vollkornmehl", "\(r.sauerteigMehl) g")
                zeile("Wasser", "\(r.sauerteigWasser) ml")
                if !r.tempHinweis.isEmpty { Pill(r.tempHinweis, .today) }
                steps(["Anstellgut, Mehl und Wasser gründlich verrühren.",
                       "Abgedeckt bei \(w.sauerteigTemp) °C **\(r.zeitplan.sauerteigZeit)** reifen lassen.",
                       "Reif, wenn er Blasen wirft, leicht gewölbt ist und säuerlich riecht. Ergibt ca. \(r.sauerteigGesamt) g."])
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
                    steps(["Alles zum Autolyseteig geben und gründlich verkneten, mit feuchten Händen.",
                           "Abgedeckt bei \(w.gareTemp) °C gehen lassen: **\(r.ersteGare)**."])
                } else {
                    mehle()
                    zeile("Warmes Wasser", "\(r.hauptteigWasser) ml")
                    sauerteigSalz
                    steps(["Alles gründlich zu einem Teig mischen, mit feuchten Händen.",
                           "Abgedeckt bei \(w.gareTemp) °C gehen lassen: **\(r.ersteGare)**."])
                }
            case .formen:
                steps((w.teigTeilen ? ["Teig halbieren, je ca. \(Int(r.einzelGewicht.rounded())) g."] : [])
                      + ["Mit feuchten Händen rundwirken, in einen bemehlten Gärkorb legen.",
                         "Stückgare bei \(w.gareTemp) °C: **\(r.stueckgare)**. Fertig, wenn eine Delle nur zur Hälfte zurückfedert."])
            case .ofen:
                steps(["Ofen auf **\(r.anbackTemp) °C** vorheizen (30-40 Min), mittlere Schiene.",
                       "Schüssel zum Abdecken oder ein Gefäß für Wasser (Schwaden) bereitstellen."])
            case .backen:
                steps(["Stürzen und kreuzförmig einschneiden.",
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
