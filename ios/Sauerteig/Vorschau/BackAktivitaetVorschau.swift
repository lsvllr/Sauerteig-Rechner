#if DEBUG
import SwiftUI

// Live-Aktivität im Canvas der App: dieselben Ansichten wie auf dem Gerät (Shared/BackAktivitaetAnsichten.swift),
// nachgestellt als Sperrbildschirm und Dynamic Island. Titel und Zeiten kommen aus dem echten Rezept (Rechner,
// BackLive.attribute), alle Zustände auf einer Seite. Die Rahmen sind angenähert; die Größen setzt iOS selbst. Ohne
// die Vorschau-Technik von WidgetKit (die scheitert für diese Erweiterung).

/// Ein Zustand der Aktivität: Attribute (Titel, Dauer) und Stand (Zeiten).
@MainActor
struct BackAktivitaetMuster: Identifiable {
    let name: String
    let a: BackAktivitaet
    let state: BackAktivitaet.ContentState
    nonisolated var id: String { name }

    private static let min = 60_000.0

    /// Lauf zu den Einstellungen `w`, Zeiten so verschoben, dass Schritt `i` (ab „Backen beginnt“) läuft und der
    /// nächste in `rest` Minuten kommt (beim letzten: seit `rest` Minuten). `aktuell`: was der letzte Push meldete.
    static func muster(_ name: String, _ w: SauerteigWerte = SauerteigWerte(), laufend i: Int, rest: Double,
                       aktuell: Int? = nil) -> BackAktivitaetMuster {
        let jetzt = Date().timeIntervalSince1970 * 1000
        let r = Rechner.rezept(w.eingabe)
        let l = BackLauf.neu(r.schritte, start: 0, vorlauf: 10, reife: Rechner.spanne(r.zeitplan.sauerteigZeit) ?? (0, 0))
        var z = l.schritte.dropFirst(BackLauf.beginn).map(\.at)
        let i = Swift.min(i, z.count - 1)
        let verschiebung = i + 1 < z.count ? jetzt + rest * min - z[i + 1] : jetzt - rest * min - z[i]
        z = z.map { ($0 + verschiebung).rounded() }
        var la = l
        la.start = (z[0] - 9 * 60 * min).rounded()
        return BackAktivitaetMuster(name: name, a: BackLive.attribute(la),
                                    state: .init(zeiten: z, aktuell: aktuell ?? i, weiter: i))
    }

    /// Jeder Schritt des Standard-Rezepts (Roggen Optimal, mit Autolyse), dazu Sonderfälle.
    static let alle: [BackAktivitaetMuster] = {
        let w = SauerteigWerte()
        let r = Rechner.rezept(w.eingabe)
        let z = r.schritte.dropFirst(BackLauf.beginn).map { Double($0.t) }
        var out: [BackAktivitaetMuster] = []
        for i in 0..<(z.count - 1) {
            let titel = r.schritte[i + BackLauf.beginn].titel
            out.append(muster("Läuft: \(titel)", w, laufend: i, rest: Swift.max(1, ((z[i + 1] - z[i]) / 2).rounded())))
        }
        out.append(muster("Nächster Schritt in unter 1 Min", w, laufend: 1, rest: 0.5))
        out.append(muster("Push verpasst (Uhr schaltet weiter)", w, laufend: 1, rest: 60, aktuell: 0))
        out.append(muster("Fertig gebacken", w, laufend: z.count - 1, rest: 5))
        var roggen = w
        roggen.mischung = "roggen-pur"
        out.append(muster("Reines Roggen (ohne Autolyse)", roggen, laufend: 0, rest: 90))
        return out
    }()
}

/// Sperrbildschirm: dunkle Glas-Karte wie auf dem Gerät.
private struct SperrRahmen: View {
    let m: BackAktivitaetMuster

    var body: some View {
        BackSperrAnsicht(a: m.a, state: m.state)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark)
    }
}

/// Dynamic Island, erweitert: links und rechts oben, darunter der Bereich unten.
private struct InselErweitert: View {
    let m: BackAktivitaetMuster

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BackInselLinks()
                Spacer()
                BackInselRechts(state: m.state)
            }
            BackInselUnten(a: m.a, state: m.state)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        .environment(\.colorScheme, .dark)
    }
}

/// Dynamic Island, kompakt (eine Aktivität) und minimal (neben einer zweiten).
private struct InselKlein: View {
    let state: BackAktivitaet.ContentState

    var body: some View {
        HStack(spacing: 16) {
            HStack {
                BackKompaktLinks()
                Spacer(minLength: 0)
                BackKompaktRechts(state: state)
            }
            .padding(.horizontal, 14)
            .frame(width: 250, height: 37)
            .background(.black, in: Capsule())
            BackMinimal(state: state)
                .frame(width: 37, height: 37)
                .background(.black, in: Circle())
        }
        .font(.subheadline.weight(.semibold))
        .environment(\.colorScheme, .dark)
    }
}

struct BackAktivitaetGalerie: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(BackAktivitaetMuster.alle) { m in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(m.name).font(.headline).foregroundStyle(.white)
                        Text("Sperrbildschirm").font(.caption).foregroundStyle(.white.opacity(0.7))
                        SperrRahmen(m: m)
                        Text("Dynamic Island erweitert").font(.caption).foregroundStyle(.white.opacity(0.7))
                        InselErweitert(m: m)
                        Text("Dynamic Island kompakt · minimal").font(.caption).foregroundStyle(.white.opacity(0.7))
                        InselKlein(state: m.state)
                    }
                }
            }
            .padding(16)
        }
        .background(LinearGradient(colors: [Color(red: 0.05, green: 0.15, blue: 0.35), Color(red: 0.0, green: 0.45, blue: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

#Preview("Live-Aktivität · alle") { BackAktivitaetGalerie() }
#endif
