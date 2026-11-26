# Sauerteig für iOS

Native iPhone- und iPad-App (SwiftUI, iOS 17+) des Sauerteig-Rechners, **local-first** nach
[LOCAL-FIRST.md](LOCAL-FIRST.md) (Vorlage aus der Haushalt-App): Das Gerät hat alle Daten und rechnet alles, ohne
Server, ohne Konto und ohne Ladeanzeige. Umgesetzt sind die Stufen 1–5 aus Abschnitt 10:

1. **Lokal, ein Gerät:** Rechner (gleiche Rundungen und Texte wie die Web-App), Rezepte sichern/laden/löschen
   (6 s Rückgängig), Füttern mit Rhythmus und lokaler Erinnerung (Uhrzeit in den
   Einstellungen oben rechts, Standard 8 Uhr; dort auch Mitteilungen und Live-Aktivität ein-/ausschalten).
2. **Back-Timer:** „Sauerteig angesetzt“ (Startzeit auch rückwirkend), „Backen beginnen“, Abhaken (auch mit
   anderer Uhrzeit über die Uhr daneben), Vorwarnung, lokale Mitteilungen auch bei geschlossener App. „Erledigt“
   heißt: Der Schritt ist fertig, der nächste beginnt jetzt. Der Timer bleibt beim laufenden Schritt, bis er
   abgehakt ist. Autolyse (während der Sauerteig reift) und Ofen vorheizen (während der Stückgare)
   werden gestartet, sobald sie fällig sind; die Zeit des Schritts davor enthält sie, und ihr „Erledigt“ beendet
   beides. Der Start der Autolyse beginnt zugleich das Backen. Das Backen läuft in zwei Stufen (mit Dampf bei voller
   Hitze, dann heruntergeschaltet ohne Dampf), mit eigener Mitteilung zum Wechsel.
3. **Live-Aktivität** ab „Backen beginnen“ auf Sperrbildschirm und Dynamic Island, mit Countdown und Fortschritt.
   Sie folgt dem Abhaken in der App und schaltet nicht von selbst weiter.
4. **Weckdienst:** `/api/wecker` (`server/wecker.ts`) schaltete früher die Aktivität per APNs weiter; die App
   meldet sich dort nicht mehr an, seit der Timer aufs Abhaken wartet.

5. **Abgleich zwischen Geräten** (`App/Abgleich.swift`, gleiches Protokoll wie die Web-App `src/abgleich.ts`): nur
   mit Konto, verknüpft in den Einstellungen per Gerätecode (oder neues Konto per Einladungscode). Der Server ist
   Relais und hält Daten nur, solange das Konto mindestens zwei Geräte hat. **Ende-zu-Ende verschlüsselt**
   (`Core/Verschluesselung.swift`, gleiches Format wie `src/schluessel.ts`): AES-256-GCM mit einem Schlüssel je
   Konto; der Server sieht nur Tabelle, uid und Zeit. Den Schlüssel bringt der 16-stellige Gerätecode mit (zweite
   Hälfte geht nie an den Server). Verteilt wird sofort: offene Apps hören auf `/api/sync/live` (Server-Sent
   Events), geschlossene weckt ein stiller APNs-Push (`content-available`), dann holt die App, plant Mitteilungen
   neu und schaltet die Live-Aktivität weiter. iOS liefert stille Pushs nach eigenem Ermessen (Akku, Häufigkeit);
   beim Öffnen holt die App ohnehin.

6. **Backtagebuch** (Tab „Tagebuch“, `Core/Tagebuch.swift`, `Pages/TagebuchAnsicht.swift`): Jedes gesicherte Rezept
   und jedes fertig gebackene Brot (Timer bis zum Ende, dann „Schließen“) ist ein Eintrag mit allen Einstellungen,
   Mengen und tatsächlichen Zeiten. Name aus der Mehlmischung, auf Wunsch eigener. Bewertung (gesamt und Krume,
   Kruste, Ofentrieb, Geschmack), Notiz, bis zu 8 Fotos (nur auf dem Gerät, `App/Bilder.swift`; noch nicht im
   Abgleich und nicht in der iCloud-Sicherung). „Nochmal backen“ lädt die Einstellungen in den Rechner. Alte
   Rezepte (Tabelle `rezept`, auch aus der Web-App) übernimmt die App einmal als Einträge.
7. **KI-Analyse der Krume:** Auf Knopfdruck gehen bis zu 3 Fotos und die Angaben zum Backen (dazu bis zu 3 frühere
   derselben Mischung) an `/api/ki/krume` (`server/ki.ts`). Der Server fragt Gemini mit festem Antwortschema und
   speichert nichts. Vorschläge, die eine Einstellung ändern, übernimmt „Mit Verbesserungen laden“. Braucht ein
   Konto und `gemini_api_key` im Add-on.

Dazu die **Sicherung in iCloud** (`App/Sicherung.swift`): die Tabellen als ein Datensatz in der privaten
CloudKit-Datenbank des Nutzers. Beim Öffnen einspielen (je Feld gewinnt die spätere Zeit), nach Änderungen und
beim Wechsel in den Hintergrund sichern. Nach Neuinstallation oder auf einem neuen iPhone kommt so alles zurück.

## Einrichten

1. `Config/Sauerteig.xcconfig`: Team-ID, Bundle-ID (`APP_BUNDLE_ID`), Server für Weckdienst und Abgleich
   (`WECKER_URL`), iCloud-Container (`ICLOUD_CONTAINER`, Standard `iCloud.<Bundle-ID>`).
2. `Sauerteig.xcodeproj` öffnen, Gerät wählen, ⌘R. Neue Swift-Dateien in `Sauerteig/`, `Widgets/`, `Shared/`
   landen von selbst im Projekt (synchronisierte Ordner).

Kostenloses Apple-Konto: `CODE_SIGN_ENTITLEMENTS` und `ICLOUD_CONTAINER` leer lassen. Dann läuft alles außer
Weckdienst und iCloud-Sicherung.

### iCloud einmalig einrichten

1. In Xcode: Target *Sauerteig* > Signing & Capabilities > **iCloud**, Haken bei **CloudKit**, unter „Containers“
   `iCloud.de.eliasvollrath.sauerteig` anhaken (mit + anlegen, falls er fehlt). Der Name steht fest in
   `Config/Sauerteig.entitlements`, weil das Entwicklerportal `$(…)`-Variablen nicht auflöst. Für den stillen
   Push stehen „Push Notifications“ (`aps-environment`) und der Hintergrundmodus `remote-notification`
   (Info.plist) schon drin.
2. Einmal aus Xcode auf einem Gerät mit iCloud starten und etwas speichern: In der Entwicklungsumgebung legt
   CloudKit den Datensatztyp `Sicherung` (Felder `daten` als Asset, `geraet` als Text) dabei selbst an.
3. **Vor dem ersten TestFlight-Build** im [CloudKit-Dashboard](https://icloud.developer.apple.com) den Container
   wählen > Schema > **Deploy Schema Changes** in die Produktion. TestFlight und App Store nutzen die Produktion;
   ohne diesen Schritt meldet die Sicherung dort einen Fehler.

## TestFlight

Einmalig: in App Store Connect die App mit der Bundle-ID `de.eliasvollrath.sauerteig` anlegen.

Nur vom Mac (GitHub baut bewusst keine TestFlight-Builds): `ios/Tools/testflight.sh` prüft den Kern, archiviert,
signiert über das in Xcode angemeldete Konto und lädt hoch. `--nur-bauen` legt nur das Archiv nach `ios/build/`.
Mit `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` in der Umgebung geht es auch ohne Xcode-Konto.

Die Build-Nummer setzt das Skript selbst (JJMMTT.HHMM, UTC), die Version steht in `MARKETING_VERSION`. Die
Exportfrage zur Verschlüsselung beantwortet `ITSAppUsesNonExemptEncryption = NO`.

## Weckdienst am Server

Von der App nicht mehr benutzt (siehe oben), nur noch für ältere Versionen. Im Home-Assistant-Add-on die Einstellungen `apns_key_id`, `apns_team_id`, `apns_topic`
(`de.eliasvollrath.sauerteig`) und `apns_key` (Inhalt der `.p8`) setzen, siehe `ha-addon/sauerteig/DOCS.md`.
Schlüssel: developer.apple.com > Keys > „Apple Push Notifications service“. Ohne APNs schaltet die Aktivität nur
weiter, wenn die App läuft (oder beim Erreichen von `staleDate` rechnet die Ansicht den Schritt aus der Uhr).

Ablauf: Die App meldet `POST /api/wecker {token: "apns:<hex>", zeiten: [ms…]}` bei jedem neuen Token und jeder
Änderung der Zeiten, `POST /api/wecker/stop` bei „Beenden“. Debug-Builds aus Xcode melden `apns-sandbox:<hex>`.

## Aufbau

```
Sauerteig/
  App/     Einstieg + AppDelegate (verdrahtet „Erledigt“ und Datenbank-Änderungen), AppState (Toast, Adressen),
           BackTimer, BackLive (Live-Aktivität), Mitteilungen, Einstellungen, Abgleich (Konto,
           Sitzungs-Schlüssel im Schlüsselbund, /api/sync), Sicherung (CloudKit)
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
nach der späteren Zeit ein. Die Web-App hat dieselbe Datenbank in TypeScript (`src/datenbank.ts`, localStorage),
gleiche Tabellen und Felder; ihr Back-Timer wird in `src/timerDaten.ts` auf die Tabelle `backlauf` abgebildet.

Abgleich (`GET /api/sync/holen?kennung=…&ab=n`, `POST /api/sync/senden {kennung, aenderungen}`): Der Server nimmt
nur an, wenn das Konto mindestens zwei Geräte hat. Je Kennung schickt ein Gerät einmal alles (Schnappschuss, Feldzeiten
bleiben erhalten), danach nur „ausstehend“. Fällt das Konto auf ein Gerät zurück, leert der Server alles und vergibt
eine neue Kennung; beim nächsten Einstieg schicken die Geräte wieder alles. Allein im Konto verwirft das Gerät
„ausstehend“. Rezepte, die früher am Server lagen, hat der Server beim Update einmal in den Abgleich gelegt; das
nächste Gerät des Kontos holt sie ab, danach sind sie dort weg.
Die Einstellungen des Rechners (Regler) sind gerätelokal (UserDefaults).

## Prüfen

- `ios/Tools/pruefe_kern.sh`: Uhr, Datenbank-Zusammenführung, Rezept-Rundreise, Abhaken, Ofen starten,
  ContentState (auch ältere Stände), Schnappschuss/Quittieren und Sicherungs-Rundreise.
- Live-Aktivität und Mitteilungen nur auf einem echten Gerät sinnvoll testbar.

Offen (LOCAL-FIRST.md 6.8): ob AlarmKit (iOS 26) Back-Schritte als Systemwecker abbilden kann.
