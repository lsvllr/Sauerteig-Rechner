import SwiftUI

/// Knopf oben links: Sauerteig-Glas mit glattem Deckel, darin Teig mit vielen kleinen Poren. Farbe nach
/// `Fuetterung.stand`: Akzent (ruhig), gelb (fällig), rot (2 Tage drüber). Ist Füttern dran, atmen die Poren leicht.
struct FuetternGlas: View {
    var stand: Fuetterung.Stand
    @Environment(\.accessibilityReduceMotion) private var wenigerBewegung

    private var farbe: Color {
        switch stand {
        case .ruhig: Brand().accent
        case .faellig: .hhWarn
        case .dringend: .hhNeg
        }
    }

    /// Poren im Teig (Mitte x/y, Halbachsen rx/ry, Phase fürs Atmen), unregelmäßig verteilt wie im echten Glas.
    private static let poren: [(x: Double, y: Double, rx: Double, ry: Double, phase: Double)] = [
        (8.0, 14.4, 0.7, 0.55, 0.0), (11.3, 13.8, 0.45, 0.4, 1.3), (14.9, 14.7, 0.9, 0.7, 2.1), (18.2, 14.1, 0.5, 0.45, 0.7),
        (12.9, 16.0, 0.4, 0.35, 3.0), (9.7, 17.1, 1.05, 0.8, 1.8), (16.9, 17.4, 0.95, 0.75, 2.6), (19.0, 18.6, 0.4, 0.4, 0.4),
        (13.5, 18.4, 0.6, 0.5, 1.0), (7.5, 20.0, 0.6, 0.5, 2.4), (11.4, 20.6, 0.85, 0.65, 0.2), (15.2, 20.9, 0.5, 0.4, 1.6),
        (18.1, 20.8, 0.7, 0.55, 2.9),
    ]

    var body: some View {
        let bewegt = stand != .ruhig && !wenigerBewegung
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !bewegt)) { ctx in
            let t = bewegt ? ctx.date.timeIntervalSinceReferenceDate : 0
            Canvas { g, size in zeichne(&g, size, t) }
        }
        .frame(width: 26, height: 26)
    }

    /// Gezeichnet auf 26 × 26 Punkten, skaliert auf die tatsächliche Größe.
    private func zeichne(_ g: inout GraphicsContext, _ size: CGSize, _ t: Double) {
        g.scaleBy(x: size.width / 26, y: size.height / 26)
        // Deckel: eine glatte, rundliche Fläche
        g.fill(Path(roundedRect: CGRect(x: 4.5, y: 2.5, width: 17, height: 4), cornerRadius: 2), with: .color(farbe))
        // Glas
        let glas = CGRect(x: 4, y: 7.5, width: 18, height: 17)
        g.stroke(Path(roundedRect: glas, cornerRadius: 4.5), with: .color(farbe), lineWidth: 1.8)
        // Teig: füllt das Glas gut zu drei Vierteln, Oberfläche ruhig und leicht gewölbt
        let innen = glas.insetBy(dx: 2, dy: 2)
        var teig = g
        teig.clip(to: Path(roundedRect: innen, cornerRadius: 2.8))
        let oben = innen.minY + innen.height * 0.2
        var flaeche = Path()
        flaeche.move(to: CGPoint(x: innen.minX, y: innen.maxY))
        flaeche.addLine(to: CGPoint(x: innen.minX, y: oben + 0.4))
        flaeche.addQuadCurve(to: CGPoint(x: innen.maxX, y: oben + 0.4), control: CGPoint(x: innen.midX, y: oben - 0.8))
        flaeche.addLine(to: CGPoint(x: innen.maxX, y: innen.maxY))
        flaeche.closeSubpath()
        teig.fill(flaeche, with: .color(farbe.opacity(0.32)))
        // Poren: dunkler als der Teig, leicht oval; ist Füttern dran, werden sie langsam größer und kleiner
        for p in Self.poren {
            let k = 1 + 0.18 * sin(t * 1.6 + p.phase)
            let rx = p.rx * k, ry = p.ry * k
            teig.fill(Path(ellipseIn: CGRect(x: p.x - rx, y: p.y - ry, width: rx * 2, height: ry * 2)),
                      with: .color(farbe.opacity(0.8)))
        }
    }
}

extension Fuetterung {
    /// Für VoiceOver am Knopf oben links.
    func beschreibung(heute: Date = Date()) -> String {
        guard let rest = restTage(heute: heute) else { return "noch nicht eingetragen" }
        if rest < 0 { return rest == -1 ? "1 Tag überfällig" : "\(-rest) Tage überfällig" }
        if rest == 0 { return "heute fällig" }
        return rest == 1 ? "morgen fällig" : "in \(rest) Tagen fällig"
    }
}

#if DEBUG
#Preview("Glas · Zustände") {
    HStack(spacing: 28) {
        FuetternGlas(stand: .ruhig)
        FuetternGlas(stand: .faellig)
        FuetternGlas(stand: .dringend)
    }
    .scaleEffect(3)
    .padding(80)
    .background(Color.hhBg)
}
#endif
