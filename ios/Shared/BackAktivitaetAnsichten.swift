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
        let i = state.laufend(Date())
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
        let i = state.laufend(Date())
        if let n = state.naechster(nach: i) {
            BackCountdown(state: state, von: i, bis: n, insel: true)
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
        BackSchrittInfo(a: a, state: state, i: state.laufend(Date()), kompakt: true)
            .padding(.horizontal, 4)
    }
}

struct BackKompaktLinks: View {
    var body: some View { Image(systemName: "timer").foregroundStyle(backAkzent) }
}

struct BackKompaktRechts: View {
    let state: BackAktivitaet.ContentState

    var body: some View {
        let i = state.laufend(Date())
        if let n = state.naechster(nach: i) {
            BackCountdown(state: state, von: i, bis: n, insel: true)
                .monospacedDigit()
                .frame(maxWidth: 64)
        } else {
            Image(systemName: "checkmark").foregroundStyle(backAkzent)
        }
    }
}

struct BackMinimal: View {
    let state: BackAktivitaet.ContentState

    var body: some View {
        Image(systemName: state.naechster(nach: state.laufend(Date())) == nil ? "checkmark" : "timer")
            .foregroundStyle(backAkzent)
    }
}

// MARK: - Teile

/// Nächster Schritt mit Countdown und Fortschritt, nach dem letzten Schritt der Hinweis zum Auskühlen.
struct BackSchrittInfo: View {
    let a: BackAktivitaet
    let state: BackAktivitaet.ContentState
    let i: Int
    let kompakt: Bool
    @Environment(\.isLuminanceReduced) private var gedimmt

    var body: some View {
        if state.zeiten.indices.contains(i), let n = state.naechster(nach: i), gedimmt && !kompakt {
            // Always-On: nur der kommende Schritt und die Restzeit.
            HStack(alignment: .firstTextBaseline) {
                Text(a.titel(n)).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                BackCountdown(state: state, von: i, bis: n)
                    .font(.system(size: 30, weight: .heavy).monospacedDigit())
                    .frame(maxWidth: 130, alignment: .trailing)
            }
        } else if state.zeiten.indices.contains(i), let n = state.naechster(nach: i) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.titel(n)).font(.headline).lineLimit(1)
                        (Text("um ") + Text(state.datum(n), style: .time) + Text(a.dauer(n).isEmpty ? "" : " · \(a.dauer(n))"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !kompakt {
                        Spacer(minLength: 8)
                        BackCountdown(state: state, von: i, bis: n)
                            .font(.system(size: 30, weight: .heavy).monospacedDigit())
                            .frame(maxWidth: 130, alignment: .trailing)
                    }
                }
                ProgressView(timerInterval: Self.spanne(state, i, n), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(backAkzent)
                Text("Jetzt: \(a.titel(i))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

    static func spanne(_ s: BackAktivitaet.ContentState, _ i: Int, _ n: Int) -> ClosedRange<Date> {
        min(s.datum(i), s.datum(n))...s.datum(n)
    }
}

/// Zählt auf dem Gerät selbst herunter, ohne Updates. Standard: immer digital („h:mm:ss“ bzw. „mm:ss“).
/// `insel` (Dynamic Island, ab iOS 18): bei einer Stunde oder mehr nur „h:mm“, darunter „mm:ss“ (höchstens zwei
/// Felder, der Wechsel passiert von selbst). Genauigkeit bewusst immer eine Sekunde, sonst schreibt das Format die
/// Einheiten aus („1 Stunde“). Unter iOS 17 gibt es dieses Format nicht, dort auch in der Insel mit Sekunden.
struct BackCountdown: View {
    let state: BackAktivitaet.ContentState
    let von: Int
    let bis: Int
    var insel = false

    var body: some View {
        let spanne = BackSchrittInfo.spanne(state, von, bis)
        Group {
            if insel, #available(iOS 18.0, *) {
                Text(.currentDate, format: .timer(countingDownIn: spanne.lowerBound..<spanne.upperBound,
                                                  maxFieldCount: 2,
                                                  maxPrecision: .seconds(1)))
            } else {
                Text(timerInterval: spanne, countsDown: true)
            }
        }
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
