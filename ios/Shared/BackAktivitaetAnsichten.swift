import SwiftUI

// Ansichten der Live-Aktivität. Liegen in Shared (App und Widget-Erweiterung): Die Erweiterung setzt sie in
// Widgets/SauerteigWidgets.swift zusammen, die App zeigt sie im Xcode-Canvas (Vorschau/LiveAktivitaetVorschau.swift)
// als normale SwiftUI-Vorschau, ohne die Vorschau-Technik von WidgetKit.

/// Akzentfarbe der App (die Erweiterung hat keinen Zugriff auf den Asset-Katalog der App).
let backAkzent = Color(red: 0.310, green: 0.275, blue: 0.898)

/// Sperrbildschirm und Mitteilungszentrale. Im Always-On (gedimmt) nur der kommende Schritt mit Restzeit ohne
/// Sekunden, alles Weitere erst auf dem aktiven Sperrbildschirm.
struct BackSperrAnsicht: View {
    let a: BackAktivitaet
    let state: BackAktivitaet.ContentState
    @Environment(\.isLuminanceReduced) private var gedimmt

    var body: some View {
        let i = state.laufend
        VStack(alignment: .leading, spacing: 8) {
            if !gedimmt {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text(state.naechster(nach: i) == nil ? "Fertig gebacken" : "Backen läuft")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(backAkzent)
            }
            BackSchrittInfo(a: a, state: state, i: i, kompakt: false)
        }
    }
}

// MARK: - Dynamic Island

struct BackInselLinks: View {
    var body: some View {
        Label("Sauerteig", systemImage: "timer")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(backAkzent)
            .padding(.leading, 4)
    }
}

struct BackInselRechts: View {
    let state: BackAktivitaet.ContentState

    var body: some View {
        if let z = state.ziel(Date()) {
            BackCountdown(von: state.datum(state.laufend), bis: z)
                .font(.title3.weight(.bold).monospacedDigit())
                .frame(maxWidth: 100, alignment: .trailing)
                .padding(.trailing, 4)
        }
    }
}

struct BackInselUnten: View {
    let a: BackAktivitaet
    let state: BackAktivitaet.ContentState

    var body: some View {
        BackSchrittInfo(a: a, state: state, i: state.laufend, kompakt: true)
            .padding(.horizontal, 4)
    }
}

struct BackKompaktLinks: View {
    var body: some View { Image(systemName: "timer").foregroundStyle(backAkzent) }
}

struct BackKompaktRechts: View {
    let state: BackAktivitaet.ContentState

    var body: some View {
        if let z = state.ziel(Date()) {
            BackCountdown(von: state.datum(state.laufend), bis: z)
                .monospacedDigit()
                .frame(maxWidth: 72) // Platz für „h:mm:ss“
        } else {
            Image(systemName: "checkmark").foregroundStyle(backAkzent)
        }
    }
}

struct BackMinimal: View {
    let state: BackAktivitaet.ContentState

    var body: some View {
        Image(systemName: state.naechster(nach: state.laufend) == nil ? "checkmark" : "timer")
            .foregroundStyle(backAkzent)
    }
}

// MARK: - Teile

/// Nächster Schritt mit Countdown, nach dem letzten Schritt der Hinweis zum Auskühlen.
struct BackSchrittInfo: View {
    let a: BackAktivitaet
    let state: BackAktivitaet.ContentState
    let i: Int
    let kompakt: Bool
    @Environment(\.isLuminanceReduced) private var gedimmt

    var body: some View {
        let jetzt = Date()
        if state.zeiten.indices.contains(i), let n = state.naechster(nach: i) {
            // Backen mit Dampf: Als Nächstes kommt die Stufe ohne Dampf.
            let dampf = state.mitDampf(jetzt) ? state.dampf : nil
            let ziel = state.ziel(jetzt) ?? state.datum(n)
            let naechstes = dampf.map { "Ohne Dampf · \($0.temp) °C" } ?? a.titel(n)
            if gedimmt && !kompakt {
                // Always-On: nur der kommende Schritt und die Restzeit.
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Als Nächstes").font(.caption).foregroundStyle(.secondary)
                        Text(naechstes).font(.headline).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    BackCountdown(von: state.datum(i), bis: ziel)
                        .font(.system(size: 30, weight: .heavy).monospacedDigit())
                        .frame(maxWidth: 130, alignment: .trailing)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Als Nächstes").font(.caption).foregroundStyle(.secondary)
                            Text(naechstes).font(.headline).lineLimit(1)
                            (Text("um ") + Text(ziel, style: .time)
                             + Text(dampf != nil ? " · bis \(a.titel(n)) ca. " : (a.dauer(n).isEmpty ? "" : " · \(a.dauer(n))"))
                             + (dampf != nil ? Text(state.datum(n), style: .time) : Text("")))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        if !kompakt {
                            Spacer(minLength: 8)
                            BackCountdown(von: state.datum(i), bis: ziel)
                                .font(.system(size: 30, weight: .heavy).monospacedDigit())
                                .frame(maxWidth: 130, alignment: .trailing)
                        }
                    }
                    // Zeit um: Der Timer wartet aufs Abhaken bzw. Starten in der App (neu gezeichnet, sobald die
                    // Anzeige veraltet).
                    Text(jetzt < state.datum(n) ? "Jetzt: \(jetztTitel(i, jetzt))"
                         : BackAktivitaet.mitStart(a.titel(n)) ? "\(a.titel(n)) fällig: in der App starten."
                         : "„\(a.titel(i))“ fertig? In der App abhaken.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auskühlen lassen").font(.headline)
                if !(gedimmt && !kompakt) {
                    Text("Mindestens 2 Stunden, erst dann anschneiden.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// „Backen mit Dampf · 250 °C“ bzw. „Backen ohne Dampf · 220 °C“, sonst der Titel.
    private func jetztTitel(_ i: Int, _ jetzt: Date) -> String {
        guard let d = state.dampf else { return a.titel(i) }
        return state.mitDampf(jetzt) ? "\(a.titel(i)) mit Dampf · \(d.heiss) °C" : "\(a.titel(i)) ohne Dampf · \(d.temp) °C"
    }
}

/// Zählt auf dem Gerät selbst herunter, ohne Updates: immer digital, „h:mm:ss“ ab einer Stunde, sonst „m:ss“.
/// Auch in der Dynamic Island: Das kürzere Format von iOS 18 (`.timer(…maxFieldCount: 2)`) schreibt je nach Restzeit
/// die Einheit aus („1 Stunde“).
struct BackCountdown: View {
    let von: Date
    let bis: Date

    var body: some View {
        Text(timerInterval: min(von, bis)...bis, countsDown: true)
            .multilineTextAlignment(.trailing)
    }
}

#if DEBUG && !WIDGET_EXTENSION // Vorschau läuft in der App (Beispieldaten in Sauerteig/Vorschau)
#Preview("Sperrbildschirm") {
    BackSperrAnsicht(a: BackAktivitaetMuster.alle[1].a, state: BackAktivitaetMuster.alle[1].state)
        .padding(16)
}
#Preview("Sperrbildschirm Always-On") {
    BackSperrAnsicht(a: BackAktivitaetMuster.alle[1].a, state: BackAktivitaetMuster.alle[1].state)
        .padding(16)
        .environment(\.isLuminanceReduced, true)
}
#Preview("Alle Varianten") { BackAktivitaetGalerie() }
#endif
