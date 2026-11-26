import SwiftUI
import UIKit

/// Fotos der Tagebuch-Einträge als JPEG in Application Support/bilder (groß: lange Seite 2048 px, klein: 480 px für
/// Listen). Im Eintrag stehen nur die IDs; die Fotos selbst gleicht `Abgleich.gleicheBilderAb` verschlüsselt über
/// `/api/bild` ab (nur mit Konto ab zwei Geräten). Nicht in der iCloud-Sicherung.
enum Bilder {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    private static var ordner: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let o = dir.appendingPathComponent("bilder", isDirectory: true)
        try? FileManager.default.createDirectory(at: o, withIntermediateDirectories: true)
        return o
    }

    /// Nur IDs, die die App selbst erzeugt (keine Pfade aus fremden Daten).
    private static func gueltig(_ id: String) -> Bool { UUID(uuidString: id) != nil }

    private static func url(_ id: String, klein: Bool) -> URL? {
        guard gueltig(id) else { return nil }
        return ordner?.appendingPathComponent(id + (klein ? "-klein" : "") + ".jpg")
    }

    /// Foto speichern (groß und klein). Rückgabe: ID oder nil.
    static func speichere(_ bild: UIImage) -> String? {
        let id = UUID().uuidString.lowercased()
        guard let gross = verkleinert(bild, lang: 2048).jpegData(compressionQuality: 0.8),
              let klein = verkleinert(bild, lang: 480).jpegData(compressionQuality: 0.7),
              let ug = url(id, klein: false), let uk = url(id, klein: true) else { return nil }
        do {
            try gross.write(to: ug, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try klein.write(to: uk, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return nil
        }
        return id
    }

    /// Großes Foto, wie es auf dem Gerät liegt (für den Abgleich).
    static func rohdaten(_ id: String) -> Data? { url(id, klein: false).flatMap { try? Data(contentsOf: $0) } }

    /// Foto aus dem Abgleich (großes JPEG) unter seiner ID ablegen; das kleine entsteht daraus.
    static func uebernimm(_ daten: Data, id: String) -> Bool {
        guard let b = UIImage(data: daten), let klein = verkleinert(b, lang: 480).jpegData(compressionQuality: 0.7),
              let ug = url(id, klein: false), let uk = url(id, klein: true) else { return false }
        do {
            try daten.write(to: ug, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try klein.write(to: uk, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return false
        }
        return true
    }

    static func lade(_ id: String, klein: Bool = true) -> UIImage? {
        let key = (id + (klein ? "-k" : "-g")) as NSString
        if let b = cache.object(forKey: key) { return b }
        guard let u = url(id, klein: klein), let b = UIImage(contentsOfFile: u.path) else { return nil }
        cache.setObject(b, forKey: key)
        return b
    }

    static func vorhanden(_ id: String) -> Bool {
        url(id, klein: true).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    static func loesche(_ id: String) {
        for k in [true, false] {
            if let u = url(id, klein: k) { try? FileManager.default.removeItem(at: u) }
            cache.removeObject(forKey: (id + (k ? "-k" : "-g")) as NSString)
        }
    }

    /// Für die KI: lange Seite 1280 px, JPEG als Base64. Liegt das Foto nicht auf dem Gerät: nil.
    static func fuerKI(_ id: String) -> String? {
        guard let u = url(id, klein: false), let b = UIImage(contentsOfFile: u.path) else { return nil }
        return verkleinert(b, lang: 1280).jpegData(compressionQuality: 0.75)?.base64EncodedString()
    }

    /// Lange Seite höchstens `lang` Pixel, Ausrichtung eingerechnet (das JPEG steht danach immer aufrecht).
    static func verkleinert(_ b: UIImage, lang: CGFloat) -> UIImage {
        let px = CGSize(width: b.size.width * b.scale, height: b.size.height * b.scale)
        let f = min(1, lang / max(px.width, px.height, 1))
        let ziel = CGSize(width: (px.width * f).rounded(), height: (px.height * f).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: ziel, format: format).image { _ in b.draw(in: CGRect(origin: .zero, size: ziel)) }
    }
}

/// Kamera (UIImagePickerController); `fertig(nil)` bei Abbrechen.
struct KameraAufnahme: UIViewControllerRepresentable {
    var fertig: (UIImage?) -> Void

    static var verfuegbar: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Koordinator { Koordinator(fertig: fertig) }

    final class Koordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let fertig: (UIImage?) -> Void
        init(fertig: @escaping (UIImage?) -> Void) { self.fertig = fertig }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            fertig(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { fertig(nil) }
    }
}
