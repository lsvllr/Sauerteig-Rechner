import SwiftUI

/// Zustand der Oberfläche: Hinweis unten (Toast), Sprungziel aus Adressen.
///
/// Adressen statt fester Navigation (Abschnitt 4): Mitteilungen, Live-Aktivität (`widgetURL`) und Links öffnen alle
/// über `open(link:)`, ohne Sonderfälle.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Ziel: String { case timer, fuettern }

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var art: Art
        var rueckgaengig: (() -> Void)?

        enum Art { case erfolg, fehler, info }

        static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
    }

    @Published var toast: Toast?
    /// Wohin die Seite scrollen soll (einmalig, danach `nil`).
    @Published var ziel: Ziel?

    /// `sauerteig://backtimer`, `/backen` → Timer; `/fuettern` → Füttern.
    func open(link: String) {
        let pfad = link.replacingOccurrences(of: "sauerteig://", with: "/")
        if pfad.hasPrefix("/fuettern") { ziel = .fuettern } else { ziel = .timer }
    }

    func zeige(_ text: String, _ art: Toast.Art = .erfolg, rueckgaengig: (() -> Void)? = nil) {
        withAnimation(Metrics.enter) { toast = Toast(text: text, art: art, rueckgaengig: rueckgaengig) }
        switch art {
        case .erfolg: Haptics.success()
        case .fehler: Haptics.error()
        case .info: break
        }
        let id = toast?.id
        Task {
            try? await Task.sleep(nanoseconds: rueckgaengig == nil ? 2_500_000_000 : 6_000_000_000)
            if toast?.id == id { withAnimation(Metrics.exit) { toast = nil } }
        }
    }

    /// Löschen mit 6 s „Rückgängig“: erst ausblenden, dann endgültig (eine Löschmarke bleibt gelöscht).
    func loescheMitRueckgaengig(_ text: String, ausblenden: @escaping () -> Void, zurueck: @escaping () -> Void,
                                endgueltig: @escaping () -> Void) {
        ausblenden()
        var abgebrochen = false
        zeige(text, .info) {
            abgebrochen = true
            zurueck()
        }
        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if !abgebrochen { endgueltig() }
        }
    }
}

/// Hinweis unten mit optionalem „Rückgängig“.
struct ToastView: View {
    let toast: AppState.Toast
    var schliessen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.art == .fehler ? "exclamationmark.circle.fill" : toast.art == .erfolg ? "checkmark.circle.fill" : "info.circle.fill")
            Text(toast.text).font(.subheadline.weight(.semibold)).lineLimit(2)
            Spacer(minLength: 0)
            if let r = toast.rueckgaengig {
                Button("Rückgängig") {
                    r()
                    schliessen()
                }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.hhToastLink)
            }
        }
        .foregroundStyle(Color.hhToastFg)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(toast.art == .fehler ? Color.hhErrorToast : Color.hhToastBg, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .padding(.horizontal, Metrics.gutter)
    }
}
