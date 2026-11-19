import ActivityKit
import SwiftUI
import WidgetKit

// Gehört zur Widget-Erweiterung und zur App: In der App nur, damit das Canvas diese Datei in der App zeigt (in der
// Erweiterung startet Xcode die Vorschau über WidgetKit, und das scheitert für eine Erweiterung nur mit
// Live-Aktivität). Einstiegspunkt daher nur mit WIDGET_EXTENSION (gesetzt im Ziel „Widgets“).

#if WIDGET_EXTENSION
/// Widget-Erweiterung der App: Live-Aktivität des Back-Timers (Attribute und Intent in Shared/BackAktivitaet.swift,
/// Ansichten in Shared/BackAktivitaetAnsichten.swift).
@main
struct SauerteigWidgets: WidgetBundle {
    var body: some Widget {
        BackAktivitaetWidget()
    }
}
#endif

/// Tipp auf die Aktivität: App öffnet den laufenden Timer (AppState.open).
private let link = URL(string: "sauerteig://backtimer")!

struct BackAktivitaetWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BackAktivitaet.self) { ctx in
            BackSperrAnsicht(a: ctx.attributes, state: ctx.state)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Lila Rahmen wie die Keyline der aufgeklappten Dynamic Island,
                // damit sich die Aktivität auf dem Sperrbildschirm abhebt.
                .overlay {
                    ContainerRelativeShape()
                        .strokeBorder(backAkzent, lineWidth: 2)
                }
                .activitySystemActionForegroundColor(backAkzent)
                .widgetURL(link)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { BackInselLinks() }
                DynamicIslandExpandedRegion(.trailing) { BackInselRechts(state: ctx.state) }
                DynamicIslandExpandedRegion(.bottom) { BackInselUnten(a: ctx.attributes, state: ctx.state) }
            } compactLeading: {
                BackKompaktLinks()
            } compactTrailing: {
                BackKompaktRechts(state: ctx.state)
            } minimal: {
                BackMinimal(state: ctx.state)
            }
            .keylineTint(backAkzent)
            .widgetURL(link)
        }
    }
}

#if DEBUG && !WIDGET_EXTENSION // Vorschau läuft in der App (Beispieldaten in Sauerteig/Vorschau)
#Preview("Live-Aktivität") { BackAktivitaetGalerie() }
#endif
