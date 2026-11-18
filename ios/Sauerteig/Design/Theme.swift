import SwiftUI
import UIKit

// Farben und Maße aus src/gemeinsam/haushalt.css (:root und prefers-color-scheme: dark), wie in der Haushalt-App.

extension UIColor {
    convenience init(hex: String, alpha: CGFloat = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = CGFloat((v >> 16) & 0xff) / 255
        let g = CGFloat((v >> 8) & 0xff) / 255
        let b = CGFloat(v & 0xff) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }

    static func dynamic(_ light: String, _ dark: String) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }

    /// Mischung wie `color-mix(in srgb, self p%, other)`.
    func mixed(with other: UIColor, _ p: CGFloat) -> UIColor {
        UIColor { tc in
            let a = self.resolvedColor(with: tc)
            let b = other.resolvedColor(with: tc)
            var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
            _ = a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            _ = b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(red: r1 * p + r2 * (1 - p), green: g1 * p + g2 * (1 - p),
                           blue: b1 * p + b2 * (1 - p), alpha: a1 * p + a2 * (1 - p))
        }
    }
}

extension Color {
    init(hex: String) { self.init(uiColor: UIColor(hex: hex)) }

    static let hhBg = Color(uiColor: .dynamic("#f1f5f9", "#000000"))
    static let hhCard = Color(uiColor: .dynamic("#ffffff", "#1c1c1e"))
    static let hhField = Color(uiColor: .dynamic("#ffffff", "#2c2c2e"))
    static let hhFill = Color(uiColor: .dynamic("#f1f5f9", "#2c2c2e"))
    static let hhFill2 = Color(uiColor: .dynamic("#f8fafc", "#242426"))
    static let hhInk = Color(uiColor: .dynamic("#0f172a", "#f2f2f7"))
    static let hhMuted = Color(uiColor: .dynamic("#5b6b80", "#a1a1aa"))
    static let hhLine = Color(uiColor: .dynamic("#e2e8f0", "#38383a"))
    static let hhPos = Color(uiColor: .dynamic("#15803d", "#4ade80"))
    static let hhPosBg = Color(uiColor: .dynamic("#dcfce7", "#14351f"))
    static let hhNeg = Color(uiColor: .dynamic("#dc2626", "#f87171"))
    static let hhNegFg = Color(uiColor: .dynamic("#b91c1c", "#fca5a5"))
    static let hhNegBg = Color(uiColor: .dynamic("#fee2e2", "#3b1618"))
    static let hhNegLine = Color(uiColor: .dynamic("#fecaca", "#5b2326"))
    static let hhWarn = Color(uiColor: .dynamic("#ca8a04", "#facc15"))
    static let hhWarnFg = Color(uiColor: .dynamic("#854d0e", "#fcd34d"))
    static let hhWarnBg = Color(uiColor: .dynamic("#fef9c3", "#352a0a"))
    static let hhWarnLine = Color(uiColor: .dynamic("#fde68a", "#5a4512"))
    static let hhInfo = Color(hex: "#0ea5e9")
    static let hhInfoFg = Color(uiColor: .dynamic("#075985", "#7dd3fc"))
    static let hhInfoBg = Color(uiColor: .dynamic("#e0f2fe", "#0c2a3d"))
    static let hhInfoLine = Color(uiColor: .dynamic("#bae6fd", "#164e6b"))
    static let hhSwitchOff = Color(uiColor: .dynamic("#cbd5e1", "#48484a"))
    static let hhToastBg = Color(uiColor: .dynamic("#1a1a1a", "#2c2c2e"))
    static let hhToastFg = Color(uiColor: .dynamic("#ffffff", "#f2f2f7"))
    static let hhToastLink = Color(uiColor: .dynamic("#c7d2fe", "#a5b4fc"))
    static let hhDanger = Color(hex: "#dc2626")
    static let hhSuccess = Color(hex: "#15803d")
    static let hhErrorToast = Color(hex: "#b91c1c")
}

/// Markenfarben der Web-App (haushalt.css: --brand, --accent-light/-dark).
struct Brand: Equatable {
    var brand: UIColor = UIColor(hex: "#4f46e5")
    var brandText: UIColor = .white
    var accentLight: UIColor = UIColor(hex: "#4f46e5")
    var accentDark: UIColor = UIColor(hex: "#818cf8")

    var primary: Color { Color(uiColor: brand) }
    var onPrimary: Color { Color(uiColor: brandText) }
    var accentUI: UIColor {
        let l = accentLight, d = accentDark
        return UIColor { $0.userInterfaceStyle == .dark ? d : l }
    }
    var accent: Color { Color(uiColor: accentUI) }
    /// `--tint`: Akzent 12 % auf Kartenfarbe.
    var tint: Color { Color(uiColor: accentUI.mixed(with: .dynamic("#ffffff", "#1c1c1e"), 0.12)) }
    var tintLine: Color { Color(uiColor: accentUI.mixed(with: .dynamic("#ffffff", "#1c1c1e"), 0.26)) }
}

private struct BrandKey: EnvironmentKey {
    static let defaultValue = Brand()
}

extension EnvironmentValues {
    var brand: Brand {
        get { self[BrandKey.self] }
        set { self[BrandKey.self] = newValue }
    }
}

/// Maße und Bewegung (CSS-Variablen).
enum Metrics {
    static let ctlHeight: CGFloat = 46 // eine Höhe für alle Bedienelemente
    static let radius: CGFloat = 12
    static let radiusSmall: CGFloat = 8
    static let cardPadding: CGFloat = 18
    static let gutter: CGFloat = 16
    static let tIn: Double = 0.225
    static let tOut: Double = 0.195
    static let tSlide: Double = 0.3

    static let enter = Animation.timingCurve(0, 0, 0.2, 1, duration: tIn)
    static let exit = Animation.timingCurve(0.4, 0, 1, 1, duration: tOut)
    static let move = Animation.timingCurve(0.4, 0, 0.2, 1, duration: tSlide)
}
