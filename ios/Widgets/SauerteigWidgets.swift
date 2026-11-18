import ActivityKit
import SwiftUI
import WidgetKit

/// Widget-Erweiterung der App: Live-Aktivität des Back-Timers (Attribute und Intent in Shared/BackAktivitaet.swift).
@main
struct SauerteigWidgets: WidgetBundle {
    var body: some Widget {
        BackAktivitaetWidget()
    }
}

/// Akzentfarbe der App (die Erweiterung hat keinen Zugriff auf den Asset-Katalog der App).
private let akzent = Color(red: 0.310, green: 0.275, blue: 0.898)
/// Tipp auf die Aktivität: App öffnet den laufenden Timer (AppState.open).
private let link = URL(string: "sauerteig://backtimer")!

struct BackAktivitaetWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BackAktivitaet.self) { ctx in
            SperrAnsicht(a: ctx.attributes, state: ctx.state)
                .padding(16)
                .activitySystemActionForegroundColor(akzent)
                .widgetURL(link)
        } dynamicIsland: { ctx in
            let s = ctx.state
            let i = s.laufend(Date())
            let n = s.naechster(nach: i)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Sauerteig", systemImage: "timer")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(akzent)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let n {
                        Countdown(state: s, von: i, bis: n)
                            .font(.title3.weight(.bold).monospacedDigit())
                            .frame(maxWidth: 100, alignment: .trailing)
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    SchrittInfo(a: ctx.attributes, state: s, i: i, kompakt: true)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(akzent)
            } compactTrailing: {
                if let n {
                    Countdown(state: s, von: i, bis: n)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                } else {
                    Image(systemName: "checkmark").foregroundStyle(akzent)
                }
            } minimal: {
                Image(systemName: n == nil ? "checkmark" : "timer").foregroundStyle(akzent)
            }
            .keylineTint(akzent)
            .widgetURL(link)
        }
    }
}

/// Sperrbildschirm und Mitteilungszentrale.
private struct SperrAnsicht: View {
    let a: BackAktivitaet
    let state: BackAktivitaet.ContentState

    var body: some View {
        let i = state.laufend(Date())
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                Text(state.naechster(nach: i) == nil ? "Fertig gebacken" : "Backen läuft")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(akzent)
            SchrittInfo(a: a, state: state, i: i, kompakt: false)
        }
    }
}

/// Nächster Schritt mit Countdown und Fortschritt, nach dem letzten Schritt der Hinweis zum Auskühlen.
private struct SchrittInfo: View {
    let a: BackAktivitaet
    let state: BackAktivitaet.ContentState
    let i: Int
    let kompakt: Bool

    var body: some View {
        if state.zeiten.indices.contains(i), let n = state.naechster(nach: i) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(a.titel(n)).font(.headline).lineLimit(1)
                        (Text("um ") + Text(state.datum(n), style: .time) + Text(a.dauer(n).isEmpty ? "" : " · \(a.dauer(n))"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if !kompakt {
                        Spacer(minLength: 8)
                        Countdown(state: state, von: i, bis: n)
                            .font(.system(size: 30, weight: .heavy).monospacedDigit())
                            .frame(maxWidth: 130, alignment: .trailing)
                    }
                }
                ProgressView(timerInterval: Self.spanne(state, i, n), countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(akzent)
                HStack(spacing: 8) {
                    Text("Jetzt: \(a.titel(i))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    if state.abhakbar(i) {
                        Button(intent: BackAbhakenIntent(schritt: i, at: state.zeiten[i])) {
                            Label("Erledigt", systemImage: "checkmark")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(akzent.opacity(0.18), in: Capsule())
                                .foregroundStyle(akzent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("„\(a.titel(i))“ erledigt")
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auskühlen lassen").font(.headline)
                Text("Mindestens 2 Stunden, erst dann anschneiden.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    static func spanne(_ s: BackAktivitaet.ContentState, _ i: Int, _ n: Int) -> ClosedRange<Date> {
        min(s.datum(i), s.datum(n))...s.datum(n)
    }
}

/// Zählt auf dem Gerät selbst herunter, ohne Updates.
private struct Countdown: View {
    let state: BackAktivitaet.ContentState
    let von: Int
    let bis: Int

    var body: some View {
        Text(timerInterval: SchrittInfo.spanne(state, von, bis), countsDown: true)
            .multilineTextAlignment(.trailing)
    }
}
