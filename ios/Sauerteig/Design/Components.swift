import SwiftUI
import UIKit

// Bausteine der Web-App als SwiftUI-Views (übernommen aus der Haushalt-App, Design/Components.swift).

// MARK: - Karte

struct Card<Content: View>: View {
    var padding: CGFloat = Metrics.cardPadding
    var border: Color = .hhLine
    var borderWidth: CGFloat = 1
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .cardSurface(border: border, borderWidth: borderWidth)
    }
}

extension View {
    /// Kartenfläche: Hintergrund, Rand, leichter Schatten. Der Schatten hängt nur an der Form, nicht am Inhalt:
    /// Ein Schatten auf der ganzen Ansicht lässt iOS jede Karte samt Text bei jedem Bild extra zeichnen, auf langen
    /// Seiten hakt dann schnelles Scrollen.
    func cardSurface(border: Color = .hhLine, borderWidth: CGFloat = 1, shadow: Double = 0.06) -> some View {
        background {
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .fill(Color.hhCard)
                .shadow(color: .black.opacity(shadow), radius: 2, x: 0, y: 1)
        }
        .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).strokeBorder(border, lineWidth: borderWidth))
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Color.hhLine).frame(height: 1) }
}

// MARK: - Überschriften

struct CardTitle: View {
    var title: String
    var hint: String
    var font: Font
    /// Hinweis zum Inhalt der Karte (z. B. Diagramm): „i“ oben rechts in der Ecke.
    var corner: String

    init(_ title: String, hint: String = "", font: Font = .headline, corner: String = "") {
        self.title = title
        self.hint = hint
        self.font = font
        self.corner = corner
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(font).foregroundStyle(Color.hhInk)
            if !hint.isEmpty { InfoInline(text: hint) }
            if !corner.isEmpty {
                Spacer(minLength: 8)
                InfoButton(text: corner, alignment: .trailing).frame(height: 20)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// Beschriftung über einem Feld (`label.field`), optional mit „i“ direkt dahinter.
struct FieldLabel: View {
    var text: String
    var hint: String
    init(_ text: String, hint: String = "") {
        self.text = text
        self.hint = hint
    }

    var body: some View {
        if hint.isEmpty {
            Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Color.hhInk)
        } else {
            HStack(spacing: 6) {
                Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Color.hhInk)
                InfoInline(text: hint)
            }
        }
    }
}

/// „i“ in einer Textzeile: nimmt nur die Zeilenhöhe ein, die Tippfläche (44 pt) ragt unsichtbar darüber hinaus.
struct InfoInline: View {
    var text: String

    var body: some View {
        InfoButton(text: text, alignment: .center)
            .frame(width: 22, height: 20)
    }
}

/// Runder „i“-Knopf, Blase mit dem Text. Tippfläche 44 pt, das Symbol steht bündig mit dem Text davor bzw. dem Rand.
struct InfoButton: View {
    var text: String
    /// Lage des Symbols in der 44-pt-Tippfläche: `.leading` bündig mit Text davor, `.trailing` bündig mit dem rechten Rand.
    var alignment: Alignment = .leading
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            Image(systemName: "info.circle")
                .font(.body.weight(.medium))
                .foregroundStyle(Color.hhMuted)
                .frame(minWidth: 44, minHeight: 32, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Erklärung")
        .accessibilityHint(text)
        .popover(isPresented: $open) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.hhInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 300, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Sichtbarer Hinweis in grauer Kleinschrift: Status, Werte, Warnungen, leere Listen. Keine Erklärungen (→ `Hint`).
struct Note: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        if !text.isEmpty {
            Text(text).font(.footnote).foregroundStyle(Color.hhMuted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Pill

enum PillStyle {
    case neutral, effort, overdue, today, soon, room, roomOverdue, pending, solid(Color), ok
}

struct Pill: View {
    var text: String
    var style: PillStyle = .neutral
    var icon: String? = nil
    @Environment(\.brand) private var brand

    init(_ text: String, _ style: PillStyle = .neutral, icon: String? = nil) {
        self.text = text
        self.style = style
        self.icon = icon
    }

    private var colors: (bg: Color, fg: Color, line: Color) {
        switch style {
        case .neutral: return (.hhFill, .hhMuted, .hhLine)
        case .effort: return (brand.tint, brand.accent, brand.tintLine)
        case .overdue, .roomOverdue: return (.hhNegBg, .hhNegFg, .hhNegLine)
        case .today, .pending: return (.hhWarnBg, .hhWarnFg, .hhWarnLine)
        case .soon: return (.hhInfoBg, .hhInfoFg, .hhInfoLine)
        case .room: return (.hhFill2, .hhMuted, .hhLine)
        case .ok: return (.hhPosBg, .hhPos, .clear)
        case .solid(let c): return (c, .white, .clear)
        }
    }

    private var weight: Font.Weight {
        if case .room = style { return .semibold }
        return .bold
    }

    var body: some View {
        let c = colors
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 12, weight: weight))
        .foregroundStyle(c.fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(c.bg, in: Capsule())
        .overlay(Capsule().strokeBorder(c.line))
    }
}

// MARK: - Knöpfe

/// `.primary`: Markenfarbe, volle Breite optional.
struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = true
    var destructive = false
    @Environment(\.brand) private var brand
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(destructive ? Color.white : brand.onPrimary)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Metrics.ctlHeight)
            .background(destructive ? Color.hhDanger : brand.primary, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : (enabled ? 1 : 0.5))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// `.btn`: neutrale Fläche mit Rand. Text in Akzentfarbe (iOS-Stil der Web-App).
struct SecondaryButtonStyle: ButtonStyle {
    var danger = false
    var small = false
    var fullWidth = false
    @Environment(\.brand) private var brand
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(small ? .subheadline.weight(.semibold) : .body.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(danger ? Color.hhNegFg : (enabled ? brand.accent : Color.hhMuted))
            .padding(.horizontal, small ? 12 : 14)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Metrics.ctlHeight)
            .background(Color.hhField, in: RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).strokeBorder(Color.hhLine))
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

/// Eintrag einer Auswahl (MenuPicker).
struct Choice<ID: Hashable>: Identifiable, Hashable {
    var id: ID
    var name: String
    var color: String = ""

    init(_ id: ID, _ name: String, color: String = "") {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// Zeilenumbrechendes Layout für Chips (`.chips`).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW {
                y += lineH + lineSpacing
                x = 0
                lineH = 0
            }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                y += lineH + lineSpacing
                x = bounds.minX
                lineH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

struct SheetClose: ToolbarContent {
    var action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: action) { Image(systemName: "xmark") }.accessibilityLabel("Schließen")
        }
    }
}

// MARK: - Felder

/// Textfeld im Stil der App (46 pt hoch, nur Rand, Radius 12, kein eigener Hintergrund).
struct HHTextFieldStyle: TextFieldStyle {
    // swiftlint:disable:next identifier_name
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 13)
            .frame(minHeight: Metrics.ctlHeight)
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).strokeBorder(Color.hhLine))
    }
}

extension TextFieldStyle where Self == HHTextFieldStyle {
    static var hh: HHTextFieldStyle { HHTextFieldStyle() }
}

/// Beschriftetes Feld: Text darüber, Inhalt darunter.
struct LabeledField<Content: View>: View {
    var label: String
    var hint: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hint.isEmpty {
                FieldLabel(label)
            } else {
                // Erklärung als „i“ direkt neben der Beschriftung.
                FieldLabel(label, hint: hint)
            }
            content()
        }
    }
}

/// Auswahl als Menü in Feldoptik (`.sel-pick > select`).
struct MenuPicker<ID: Hashable>: View {
    var options: [Choice<ID>]
    @Binding var selection: ID
    @Environment(\.brand) private var brand

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options) { o in Text(o.name).tag(o.id) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.id == selection }?.name ?? "–")
                    .foregroundStyle(Color.hhInk)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Color.hhMuted)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: Metrics.ctlHeight)
            .overlay(RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous).strokeBorder(Color.hhLine))
        }
    }
}

struct IntStepper: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var hint: String = ""

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack(spacing: 6) {
                Text(label).foregroundStyle(Color.hhInk)
                if !hint.isEmpty { InfoInline(text: hint) }
                Spacer()
                Text("\(value)").font(.body.weight(.semibold).monospacedDigit()).contentTransition(.numericText())
            }
        }
        .frame(minHeight: Metrics.ctlHeight)
    }
}

// MARK: - Fakten (dl.facts)

struct FactRow<Value: View>: View {
    var label: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label).font(.subheadline).foregroundStyle(Color.hhMuted)
            Spacer(minLength: 8)
            value().font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 11)
    }
}

extension FactRow where Value == Text {
    init(_ label: String, _ value: String) {
        self.label = label
        self.value = { Text(value) }
    }
}

// MARK: - Seitenhintergrund

extension View {
    /// Inhalt einer Seite: Hintergrund, Ränder, maximale Breite wie `.container`.
    func pageContainer() -> some View {
        self
            .frame(maxWidth: 860)
            .padding(.horizontal, Metrics.gutter)
            .frame(maxWidth: .infinity)
    }

    func hhBackground() -> some View {
        self.background { Color.hhBg.ignoresSafeArea() }
    }
}

// MARK: - Haptik

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
}

#if DEBUG
// MARK: - Bausteine

#Preview("Bausteine") {
    @Previewable @State var wert = 22
    @Previewable @State var wahl = 10
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                CardTitle("Karte mit Titel", hint: "Erklärung hinter dem „i“.")
                FactRow("Krume", "saftig, kompakt")
                RowDivider()
                FactRow("Haltbarkeit", "5–7 Tage")
                Note("Hinweis in grau.")
            }
            Card {
                CardTitle("Knöpfe")
                Button("Primär") {}.buttonStyle(PrimaryButtonStyle())
                Button("Primär schmal") {}.buttonStyle(PrimaryButtonStyle(fullWidth: false))
                Button("Löschen") {}.buttonStyle(PrimaryButtonStyle(destructive: true))
                HStack {
                    Button("Sekundär") {}.buttonStyle(SecondaryButtonStyle())
                    Button("Klein") {}.buttonStyle(SecondaryButtonStyle(small: true))
                    Button("Gefahr") {}.buttonStyle(SecondaryButtonStyle(danger: true, small: true))
                }
            }
            Card {
                CardTitle("Pillen")
                FlowLayout {
                    Pill("neutral")
                    Pill("überfällig", .overdue)
                    Pill("heute", .today)
                    Pill("morgen", .soon)
                    Pill("in 3 Tagen", .ok)
                    Pill("Aufwand", .effort, icon: "flame")
                }
            }
            Card {
                CardTitle("Eingaben")
                Regler(label: "Sauerteig-Temperatur", wert: "\(wert) °C", value: $wert, range: 18...30, step: 1, hint: "Beispiel")
                IntStepper(label: "Zähler", value: $wert, range: 0...40)
                LabeledField(label: "Auswahl", hint: "Menü in Feldoptik") {
                    MenuPicker(options: BackLauf.vorlaufWahl.map { Choice($0, $0 == 0 ? "Keine" : "\($0) Min vorher") }, selection: $wahl)
                }
            }
            ToastView(toast: AppState.Toast(text: "Gesichert", art: .erfolg)) {}
            ToastView(toast: AppState.Toast(text: "Fehlgeschlagen", art: .fehler)) {}
            ToastView(toast: AppState.Toast(text: "Gelöscht", art: .info, rueckgaengig: {})) {}
        }
        .padding(Metrics.gutter)
    }
    .hhBackground()
}
#endif
