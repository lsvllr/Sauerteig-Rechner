# Sauerteig für iOS

Native iPhone- und iPad-App (SwiftUI, iOS 17+) des Sauerteig-Rechners, **local-first** nach
[LOCAL-FIRST.md](LOCAL-FIRST.md) (Vorlage aus der Haushalt-App): Das Gerät hat alle Daten und rechnet alles, ohne
Server und ohne Ladeanzeige. Umgesetzt sind die Stufen 1–4 aus Abschnitt 10:

1. **Lokal, ein Gerät:** Rechner (gleiche Rundungen und Texte wie die Web-App), Rezepte sichern/laden/löschen
   (6 s Rückgängig), Füttern mit Rhythmus und lokaler Erinnerung um 8 Uhr.
2. **Back-Timer:** „Sauerteig angesetzt“ (Startzeit auch rückwirkend), „Backen beginnen“, Abhaken (auch mit
   anderer Uhrzeit über die Uhr daneben), Vorwarnung, lokale Mitteilungen auch bei geschlossener App.
3. **Live-Aktivität** ab „Backen beginnen“ auf Sperrbildschirm und Dynamic Island, mit Countdown, Fortschritt und
   Knopf „Erledigt“ (läuft im Prozess der App, auch ohne Netz).
4. **Weckdienst:** Der Node-Server dieses Repos (`/api/wecker`, `server/wecker.ts`) schaltet die Aktivität per
   APNs zu jedem Schritt weiter, auch bei geschlossener App. Er kennt nur Push-Token und Uhrzeiten, keine Rezepte.

Stufe 5 (Abgleich zwischen Geräten) fehlt noch; das Datenformat ist dafür vorbereitet (siehe *Daten*).

## Einrichten

1. `Config/Sauerteig.xcconfig`: Team-ID, Bundle-ID (`APP_BUNDLE_ID`), Server des Weckdienstes (`WECKER_URL`).
2. `Sauerteig.xcodeproj` öffnen, Gerät wählen, ⌘R. Neue Swift-Dateien in `Sauerteig/`, `Widgets/`, `Shared/`
   landen von selbst im Projekt (synchronisierte Ordner).

Kostenloses Apple-Konto: `CODE_SIGN_ENTITLEMENTS` leer lassen. Dann läuft alles außer dem Weckdienst.

## TestFlight

Einmalig: in App Store Connect die App mit der Bundle-ID `de.eliasvollrath.sauerteig` anlegen.

- **Vom Mac:** `ios/Tools/testflight.sh` prüft den Kern, archiviert, signiert über das in Xcode angemeldete Konto
  und lädt hoch. `--nur-bauen` legt nur das Archiv nach `ios/build/`. Mit `ASC_KEY_ID`, `ASC_ISSUER_ID`,
  `ASC_KEY_PATH` in der Umgebung geht es auch ohne Xcode-Konto (z. B. per cron).
- **Automatisch über GitHub Actions:** `.github/workflows/testflight.yml` baut bei jedem Push auf `main`, der
  `ios/` ändert, und auf Knopfdruck. Braucht die Secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (Team-Schlüssel,
  Rolle „Admin“; Details im Kopf der Workflow-Datei). Ohne Secrets wird der Lauf übersprungen.

Die Build-Nummer setzen beide Wege selbst (JJMMTT.HHMM, UTC), die Version steht in `MARKETING_VERSION`. Die
Exportfrage zur Verschlüsselung beantwortet `ITSAppUsesNonExemptEncryption = NO`.

## Weckdienst am Server

Im Home-Assistant-Add-on die Einstellungen `apns_key_id`, `apns_team_id`, `apns_topic`
(`de.eliasvollrath.sauerteig`) und `apns_key` (Inhalt der `.p8`) setzen, siehe `ha-addon/sauerteig/DOCS.md`.
Schlüssel: developer.apple.com > Keys > „Apple Push Notifications service“. Ohne APNs schaltet die Aktivität nur
weiter, wenn die App läuft (oder beim Erreichen von `staleDate` rechnet die Ansicht den Schritt aus der Uhr).

Ablauf: Die App meldet `POST /api/wecker {token: "apns:<hex>", zeiten: [ms…]}` bei jedem neuen Token und jeder
Änderung der Zeiten, `POST /api/wecker/stop` bei „Beenden“. Debug-Builds aus Xcode melden `apns-sandbox:<hex>`.

## Aufbau

```
Sauerteig/
  App/     Einstieg + AppDelegate (verdrahtet „Erledigt“), AppState (Toast, Adressen), BackTimer, BackLive
           (Live-Aktivität + Weckdienst-Client), Mitteilungen
  Core/    Datenbank (uid, Feldzeiten, Löschmarken, hybride Uhr, ausstehende Änderungen), Daten (Rezepte, Füttern,
           Back-Lauf als Tabellen), BackLauf (Regeln), Rechner
  Pages/   HauptAnsicht, TimerKarte, FuetternKarte, Teile (Regler, Anleitung)
  Design/  Farben und Bausteine wie in der Web-/Haushalt-App
Widgets/   Widget-Erweiterung: Ansicht der Live-Aktivität
Shared/    in App und Erweiterung: BackAktivitaet (Attribute, ContentState, Intent „Erledigt“)
Config/    xcconfig, Info.plist (App, Erweiterung), Entitlements, ExportOptions
Tools/     testflight.sh, pruefe_kern.sh (Kern-Tests auf dem Mac, ohne Simulator)
```

## Daten

Eine JSON-Datei `daten.json` in Application Support. Tabellen `rezept` (Einstellungen als ein JSON-Feld im Format
der Web-App), `profil` (eine Zeile mit fester uid: Füttern), `backlauf` (je „Sauerteig angesetzt“ eine neue Zeile,
Zeitplan als ein JSON-Feld, Beenden = Löschmarke). Jede Schreiboperation erzeugt eine Änderung
`{tabelle, uid, daten, geloescht, zeit}` in „ausstehend“; `Datenbank.wende(_:)` spielt fremde Änderungen je Feld
nach der späteren Zeit ein. Für Stufe 5 fehlen nur Senden/Holen (`/sync/senden`, `/sync/holen`) und der stille Push.
Die Einstellungen des Rechners (Regler) sind gerätelokal (UserDefaults).

## Prüfen

- `ios/Tools/pruefe_kern.sh`: Uhr, Datenbank-Zusammenführung, Rezept-Rundreise, Abhaken, ContentState und das
  Push-JSON des Weckdienstes.
- Live-Aktivität und Mitteilungen nur auf einem echten Gerät sinnvoll testbar.

Offen (LOCAL-FIRST.md 6.8): ob AlarmKit (iOS 26) Back-Schritte als Systemwecker abbilden kann.
