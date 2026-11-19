import CloudKit
import MachO
import UIKit

/// Datensicherung in der privaten CloudKit-Datenbank des Nutzers (zählt zu seinem iCloud-Speicher, der Entwickler
/// und der Server sehen nichts davon). Ein Datensatz `Sicherung/daten` mit den Tabellen der lokalen Datenbank als
/// Datei.
///
/// - Beim Start und bei Rückkehr in den Vordergrund: Sicherung holen und einspielen, je Feld gewinnt die spätere
///   Zeit (wie beim Abgleich). Nach Neuinstallation oder auf einem neuen iPhone mit derselben Apple-ID kommt so
///   alles zurück; zwei eigene Geräte ohne Konto führen ihre Stände dabei auch zusammen.
/// - Nach jeder Änderung (5 s gesammelt) und beim Wechsel in den Hintergrund: sichern, wenn sich etwas geändert hat.
///
/// Aus, wenn der Build keinen iCloud-Container hat (`ICLOUD_CONTAINER` in Config/Sauerteig.xcconfig leer, z. B. mit
/// kostenlosem Apple-Konto) oder das Gerät nicht bei iCloud angemeldet ist.
@MainActor
final class Sicherung: ObservableObject {
    static let shared = Sicherung()

    enum Stand: Equatable {
        case aus(String)
        case bereit
        case laeuft
        case fehler(String)
    }

    @Published private(set) var stand: Stand
    @Published private(set) var zuletzt: Date?

    private let containerID: String?
    private let db: Datenbank
    private var geplant: Task<Void, Never>?
    private var gesichert: Data?
    private var geholt = false

    private static let recordType = "Sicherung"
    private static let recordID = CKRecord.ID(recordName: "daten")
    private static let zuletztKey = "sicherung-zuletzt"

    init(db: Datenbank? = nil) {
        self.db = db ?? .shared
        let id = (Bundle.main.object(forInfoDictionaryKey: "ICloudContainer") as? String)?.trimmingCharacters(in: .whitespaces)
        containerID = id.flatMap { $0.hasPrefix("iCloud.") && Self.hatBerechtigung($0) ? $0 : nil }
        stand = containerID == nil ? .aus("In diesem Build ohne iCloud.") : .bereit
        zuletzt = UserDefaults.standard.object(forKey: Self.zuletztKey) as? Date
    }

    /// Ob der Build die iCloud-Berechtigung für `id` mitbringt. Ohne sie bricht CloudKit die App ab (EXC_BREAKPOINT in
    /// `CKContainer(identifier:)`). Auf dem Gerät läuft nur signiert, dort kommt sie aus derselben xcconfig wie
    /// `ICloudContainer`. Im Simulator geht auch ein unsignierter Build (xcodebuild mit CODE_SIGNING_ALLOWED=NO);
    /// Xcode bettet die Berechtigungen dort als Abschnitt `__TEXT,__entitlements` ins Programm ein.
    private static func hatBerechtigung(_ id: String) -> Bool {
        #if targetEnvironment(simulator)
        guard let kopf = _dyld_get_image_header(0) else { return false }
        var groesse: UInt = 0
        let p = kopf.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
            getsectiondata($0, "__TEXT", "__entitlements", &groesse)
        }
        guard let p else { return false }
        return String(decoding: UnsafeBufferPointer(start: p, count: Int(groesse)), as: UTF8.self).contains(id)
        #else
        return true
        #endif
    }

    /// Nur anfassen, wenn der Build den Container hat (sonst bricht CloudKit die App ab).
    private var datenbank: CKDatabase? { containerID.map { CKContainer(identifier: $0).privateCloudDatabase } }

    private func angemeldet() async -> Bool {
        guard let containerID else { return false }
        let s = try? await CKContainer(identifier: containerID).accountStatus()
        if s == .available { return true }
        stand = .aus(s == .noAccount ? "Nicht bei iCloud angemeldet." : "iCloud ist für Sauerteig nicht verfügbar.")
        return false
    }

    /// Start oder Vordergrund: Sicherung einspielen, danach den zusammengeführten Stand sichern.
    func abgleichen() async {
        guard let datenbank, await angemeldet() else { return }
        stand = .laeuft
        do {
            let r = try await datenbank.record(for: Self.recordID)
            if let a = r["daten"] as? CKAsset, let url = a.fileURL, let d = try? Data(contentsOf: url) {
                db.uebernimmSicherung(d)
                if gesichert == nil { gesichert = d }
            }
            geholt = true
        } catch let e as CKError where e.code == .unknownItem {
            geholt = true // noch keine Sicherung
        } catch {
            stand = .fehler(Self.text(error))
            return
        }
        await sichere()
    }

    /// Nach einer Änderung: in 5 s sichern (mehrere zusammen).
    func vormerken() {
        guard containerID != nil else { return }
        geplant?.cancel()
        geplant = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.sichere()
        }
    }

    /// Wechsel in den Hintergrund: gleich sichern, iOS lässt der App dafür etwas Zeit.
    func imHintergrund() {
        guard containerID != nil else { return }
        geplant?.cancel()
        let id = UIApplication.shared.beginBackgroundTask(withName: "Sicherung")
        Task {
            await sichere()
            UIApplication.shared.endBackgroundTask(id)
        }
    }

    /// Sichern, wenn sich seit dem letzten Mal etwas geändert hat. Erst nach dem ersten Holen, sonst überschriebe
    /// eine frische Installation die Sicherung mit leeren Tabellen.
    func sichere(auchUnveraendert: Bool = false) async {
        guard let datenbank, geholt, let d = db.sicherung() else { return }
        if d == gesichert && !auchUnveraendert {
            stand = .bereit
            return
        }
        stand = .laeuft
        let datei = FileManager.default.temporaryDirectory.appendingPathComponent("sicherung-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: datei) }
        do {
            try d.write(to: datei)
            let r = CKRecord(recordType: Self.recordType, recordID: Self.recordID)
            r["daten"] = CKAsset(fileURL: datei)
            r["geraet"] = UIDevice.current.name as NSString
            _ = try await datenbank.modifyRecords(saving: [r], deleting: [], savePolicy: .allKeys, atomically: true)
            gesichert = d
            zuletzt = Date()
            UserDefaults.standard.set(zuletzt, forKey: Self.zuletztKey)
            stand = .bereit
        } catch {
            stand = .fehler(Self.text(error))
        }
    }

    private static func text(_ e: Error) -> String {
        switch (e as? CKError)?.code {
        case .networkUnavailable?, .networkFailure?: return "Keine Verbindung, sichert beim nächsten Mal."
        case .quotaExceeded?: return "iCloud-Speicher ist voll."
        case .notAuthenticated?: return "Nicht bei iCloud angemeldet."
        default: return "Sichern hat nicht geklappt (\(e.localizedDescription))."
        }
    }
}
