import CommonCrypto
import CryptoKit
import Foundation

/// Ende-zu-Ende-Verschlüsselung des Abgleichs, gleiches Format wie die Web-App (src/schluessel.ts).
///
/// - Ein Schlüssel je Konto (AES-256-GCM), erzeugt auf einem Gerät, nie im Klartext beim Server. Der Server kennt
///   nur seine Kennung (SHA-256, erste 8 Byte hex), um Geräte mit falschem Schlüssel abzuweisen.
/// - Änderung: `daten` wird zu `{x: base64(nonce 12 ‖ Geheimtext ‖ Tag 16)}`, Klartext = JSON von `daten`. Tabelle,
///   uid und Zeit bleiben lesbar und sind als zusätzliche Daten an den Inhalt gebunden. Löschen hat keinen Inhalt.
/// - Gerätecode `AAAA-AAAA-GGGG-GGGG`: die erste Hälfte kennt der Server, die zweite nie. Aus ihr (PBKDF2-SHA256,
///   300 000 Runden, zufälliges Salz) entsteht der Schlüssel, mit dem der Kontoschlüssel verpackt 15 Minuten beim
///   Server liegt: `base64(salz 16 ‖ nonce 12 ‖ Geheimtext ‖ Tag 16)`.
enum Verschluesselung {
    static let runden: UInt32 = 300_000
    private static let zeichen = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    private static let packZusatz = Data("sauerteig-schluessel".utf8)

    static func neuerSchluessel() -> Data { SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) } }

    static func kennung(_ k: Data) -> String {
        SHA256.hash(data: k).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func zusatz(_ a: Aenderung) -> Data { Data("\(a.tabelle)\n\(a.uid)\n\(a.zeit)".utf8) }

    static func verschluessele(_ k: Data, _ a: Aenderung) throws -> Aenderung {
        var aus = a
        guard !a.geloescht else { aus.daten = [:]; return aus }
        let klar = try JSONEncoder().encode(a.daten)
        let box = try AES.GCM.seal(klar, using: SymmetricKey(data: k), authenticating: zusatz(a))
        aus.daten = ["x": .text(box.combined!.base64EncodedString())]
        return aus
    }

    /// nil: nicht lesbar. Klartext nur, was der Server beim Update aus seinem Altbestand übernommen hat.
    static func entschluessele(_ k: Data, _ a: Aenderung) -> Aenderung? {
        var aus = a
        guard !a.geloescht else { aus.daten = [:]; return aus }
        guard case .text(let x)? = a.daten["x"] else { return a.zeit.hasSuffix("-server0000") ? a : nil }
        guard let d = Data(base64Encoded: x), let box = try? AES.GCM.SealedBox(combined: d),
              let klar = try? AES.GCM.open(box, using: SymmetricKey(data: k), authenticating: zusatz(a)),
              let daten = try? JSONDecoder().decode([String: Wert].self, from: klar) else { return nil }
        aus.daten = daten
        return aus
    }

    // MARK: Gerätecode

    static func neuesGeheimnis() -> String {
        String((0..<8).map { _ in zeichen[Int.random(in: 0..<zeichen.count)] })
    }

    /// 16 Zeichen = Server-Teil + Geheimnis, 8 Zeichen = nur Server-Teil (Code vom Admin).
    static func zerlegeCode(_ eingabe: String) -> (server: String, geheim: String?) {
        let s = String(eingabe.uppercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII })
        return s.count >= 16 ? (String(s.prefix(8)), String(s.dropFirst(8).prefix(8))) : (s, nil)
    }

    static func zeigeCode(_ server: String, _ geheim: String) -> String {
        let s = Array((server + geheim).uppercased().filter { $0.isLetter || $0.isNumber })
        return stride(from: 0, to: s.count, by: 4).map { String(s[$0..<min($0 + 4, s.count)]) }.joined(separator: "-")
    }

    private static func pack(_ geheim: String, _ salz: Data) -> SymmetricKey {
        var aus = Data(count: 32)
        let pw = Array(geheim.utf8)
        _ = aus.withUnsafeMutableBytes { a in
            salz.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw.map { Int8(bitPattern: $0) }, pw.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salz.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), runden,
                                     a.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        return SymmetricKey(data: aus)
    }

    static func verpacke(_ k: Data, geheim: String) throws -> String {
        let salz = SymmetricKey(size: .init(bitCount: 128)).withUnsafeBytes { Data($0) }
        let box = try AES.GCM.seal(k, using: pack(geheim, salz), authenticating: packZusatz)
        return (salz + box.combined!).base64EncodedString()
    }

    static func entpacke(_ blob: String, geheim: String) -> Data? {
        guard let d = Data(base64Encoded: blob), d.count > 16 + 28,
              let box = try? AES.GCM.SealedBox(combined: Data(d.dropFirst(16))),
              let k = try? AES.GCM.open(box, using: pack(geheim, Data(d.prefix(16))), authenticating: packZusatz),
              k.count == 32 else { return nil }
        return k
    }
}
