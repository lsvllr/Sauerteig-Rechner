# iOS-App local-first – Grundfunktion und Vorlage

Stand: 17.11.2026. Beschreibt, wie die Haushalt-App für iOS funktioniert, wenn der Umbau aus `SYNC.md` fertig ist
(Stufe 8), und was davon heute schon so läuft. Gedacht als Vorlage für neue Apps nach demselben Muster, zuerst die
**Sauerteig-App**: Sie soll von Anfang an so gebaut werden, ohne den Umweg über Server-Seiten.

Wichtigster Teil für die Sauerteig-App: **Back-Timer mit Live-Aktivität** (Abschnitt 6).

---

## 1. Grundsätze

1. **Das Gerät hat alle Daten.** Die lokale Datenbank ist die Wahrheit, nicht der Server. Die App startet,
   zeigt und speichert ohne Netz.
2. **Das Gerät rechnet alles.** Seiten (View-Models) und Aktionen entstehen lokal. Es gibt keine Ladeanzeige und
   kein „Speichern fehlgeschlagen“, weil nichts auf eine Antwort wartet.
3. **Der Server ist nur Relais.** Er speichert und verteilt Änderungen zwischen Geräten, am Ende verschlüsselt, und
   kann sie nicht lesen. Ohne Server funktioniert die App für ein Gerät vollständig.
4. **Abgleich pro Feld.** Jede Änderung ist `{tabelle, uid, feld, wert, zeit}`. Je Feld gewinnt die spätere Zeit
   (hybride logische Uhr). Gelöscht bleibt gelöscht.
5. **Erinnerungen sind lokal.** Mitteilungen plant das Gerät selbst (`UNUserNotificationCenter`). Der Server
   schickt nur noch, was iOS lokal nicht kann: die Live-Aktivität weiterschalten (Abschnitt 6.5) und stille
   Pushs „es gibt Neues“.

## 2. Heute und am Ende

| Teil | Heute (Stufe 4) | Am Ende (Stufe 8) | Sauerteig-App |
|---|---|---|---|
| Daten | Server-SQLite; Kopie auf dem Gerät (`kopie.json`) nur gelesen | lokale Kopie ist die Wahrheit | lokal von Anfang an |
| Seiten | `GET /api/page/<pfad>` vom Server; nur Einkaufsliste aus dem Kern | alle aus dem Kern (`page(pfad)`) | lokal in Swift |
| Aktionen | `POST /api/act/…`, offline in die Warteschlange; Einkauf lokal | alle lokal (`aktion(pfad, daten)`) → Änderungen | lokal |
| Abgleich | `/sync/senden`, `/sync/holen`, Anstoß per SSE | dazu stiller APNs-Push, Daten verschlüsselt | optional, gleiches Protokoll |
| Mitteilungen | Back-Timer und Erinnerungen per Server-Push | lokal geplant | lokal |
| Live-Aktivität Back-Timer | App startet, Server schaltet per APNs weiter, Server kennt den Zeitplan | App startet und schaltet weiter, Server nur Weckdienst ohne Inhalte | wie „am Ende“ |
| Sauerteig-Rechner | rechnet schon heute lokal in Swift (`Core/Sauerteig.swift`) | unverändert | übernehmen |

---

## 3. Daten auf dem Gerät

### Tabellen

- Jede Zeile hat eine **`uid`** (UUID, als Text). Verweise zwischen Tabellen laufen nur über die uid.
- Eine Zahl-ID gibt es höchstens lokal (für Adressen wie `/rezept/3`). In Haushalt nimmt der Kern dafür die ersten
  48 Bit der uid (`lokaleId`), dann ist sie auf allen Geräten gleich und braucht keinen Speicher.
- Pro Feld wird neben dem Wert die **Zeit der letzten Änderung** gespeichert. Gelöschte Zeilen bleiben als
  Löschmarke (`_geloescht`) stehen, sonst kommen sie beim nächsten Abgleich zurück.
- Eindeutige Namen (z. B. Rezeptname, falls eindeutig gewollt): Legen zwei Geräte offline denselben an, werden die
  Zeilen zusammengelegt (ältere uid gewinnt, Verweise umbiegen). Besser: Namen nicht eindeutig machen.
- Felder, die als Ganzes gelten müssen, als **ein** Feld speichern (JSON-Text). Beispiel: der Zeitplan eines
  Back-Laufs. Sonst mischt der Abgleich pro Feld Schritte aus zwei Fassungen.

### Speicher

- Haushalt heute: `actor LocalCopy`, eine JSON-Datei `kopie.json` in Application Support, geschrieben nur bei
  Änderung. Reicht für einige tausend Zeilen.
- Sauerteig-App: dieselbe Form genügt (`[tabelle: [uid: Row]]`, `Row = {d: Werte, z: Zeiten}`). SQLite oder
  SwiftData erst, wenn es viel mehr Daten werden. Wichtig ist nur, dass jede Schreiboperation eine **Änderung**
  erzeugt (Abschnitt 3.3) und nichts am Protokoll vorbei schreibt.

### Änderungen

```json
{"tabelle": "backlauf", "uid": "8d0c…", "daten": {"vorlauf": 10}, "geloescht": false,
 "zeit": "1763371234567-0003-ios3f9a2c1d"}
```

- Neue Zeile: alle Felder. Geänderte Zeile: nur die geänderten Felder (gleicher Wert zählt nicht). Löschen:
  `geloescht: true`.
- Jede eigene Änderung wird sofort lokal angewendet und landet in **„ausstehend“** (in Haushalt `aus` in
  `kopie.json`). Beim Lesen liegen ausstehende Änderungen über der Kopie.

### Hybride logische Uhr (HLC)

- Format `<ms seit 1970, 13-stellig>-<Zähler, 4 hex>-<Gerät>`, als Text sortierbar.
- Gerät: 8–64 Zeichen `[A-Za-z0-9_]`, einmal zufällig erzeugt (`ios…`), in UserDefaults.
- Die eigene Uhr geht **nie hinter die späteste gesehene Zeit** zurück (auch fremde Zeiten aus dem Abgleich). Gleiche
  Millisekunde → Zähler +1.
- Der Server lehnt Zeiten ab, die mehr als 10 Minuten vor seiner Uhr liegen (`uhr`).

## 4. Seiten und Aktionen

Jede Seite ist eine Adresse (`/backen`, `/rezept/<id>`). Zwei Funktionen machen die ganze Logik:

- `page(pfad) -> ViewModel`: liest die Tabellen, rechnet, formatiert. SwiftUI zeigt nur an.
- `aktion(pfad, felder) -> (ergebnis, [Änderung])`: prüft Eingaben, erzeugt Änderungen; Zeit und neue uids kommen von
  außen hinein (dann ist das Ergebnis testbar und auf jedem Gerät gleich).

Haushalt hat diese Logik in TypeScript (`frontend/src/kern/`), weil Web-App und iOS-App sie teilen; iOS führt
dasselbe Bündel in JavaScriptCore aus (`Core/Kern.swift`). **Für die Sauerteig-App:** Gibt es keine Web-App, die
dieselbe Logik braucht, direkt in Swift schreiben (der Rechner liegt schon in Swift vor). Soll der eigenständige
Web-Rechner weiterleben und dieselben Daten zeigen, lohnt sich der TS-Kern wie in Haushalt.

Adressen statt fester Navigation haben sich bewährt: Mitteilungen, Live-Aktivität (`widgetURL`), Universal Links
und Links in Daten öffnen alle über `AppState.open(link:)`, ohne Sonderfälle.

## 5. Abgleich zwischen Geräten (optional)

Für die Sauerteig-App erst nötig, wenn mehrere Geräte (iPhone + iPad, zwei Personen) dieselben Rezepte und denselben
Timer sehen sollen. Das Datenformat aus Abschnitt 3 macht ihn später ohne Umbau möglich.

- **Senden**: `POST /sync/senden {geraet, aenderungen}` → `angenommen`/`abgelehnt` je `zeit`. Wiederholung mit
  wachsendem Abstand (15 s … 2 min), sofort bei Netz oder Rückkehr in den Vordergrund. Angenommene fallen aus
  „ausstehend“, sobald sie über `holen` zurückkommen; abgelehnte zeigt die App unter „Nicht gespeichert“.
- **Holen**: `GET /sync/holen?ab=<nummer>` seitenweise (höchstens 500), `bis` ist der neue Stand. Neue `kennung`
  oder `letzte` kleiner als der eigene Stand → Kopie verwerfen und neu holen (Server zurückgesetzt).
- **Anstoß**: im Vordergrund Server-Sent Events (`GET /sync/live`, `event: neu`, alle 25 s `: ping`; Cloudflare
  schließt stille Verbindungen nach rund 100 s). Im Hintergrund stiller APNs-Push (`content-available: 1`), die App
  holt dann und plant ihre Mitteilungen neu.
- **Zusammenführen**: je Feld die spätere `zeit`. Damit erledigt sich, was Haushalt heute beim Back-Timer von Hand
  macht (`BackLauf.abgleich`, `geaendert_ms`, `gestoppt`): „die letzte Änderung gilt, egal auf welchem Gerät“ ist
  einfach die Regel des Abgleichs.
- **Verschlüsselung** (Haushalt Stufe 7): ein Schlüssel je Zuhause bzw. je Teilen-Gruppe, im Einladungslink hinter
  `#` (geht nie an den Server), Wiederherstellungsschlüssel zum Ausdrucken. `daten` wird verschlüsselt, `tabelle`,
  `uid` und `zeit` bleiben lesbar, damit der Server sortieren und verteilen kann.

---

## 6. Back-Timer und Live-Aktivität

### 6.1 Ablauf aus Sicht der Nutzer

1. **„Sauerteig angesetzt“** (Startzeit wählbar, auch in der Vergangenheit): Phase *reifen*. Die App zeigt „reif ca.
   02:30–04:30, Backen beginnt ca. 03:30“ und plant eine Mitteilung „Sauerteig prüfen“ (plus Vorwarnung).
2. **„Backen beginnen“**: Phase *backen*. Alle folgenden Schritte werden ab jetzt neu gerechnet. Ab hier läuft die
   **Live-Aktivität** auf dem Sperrbildschirm und in der Dynamic Island.
3. Zu jedem Schritt eine Mitteilung bei Fälligkeit („Jetzt: Dehnen und Falten“) und, wenn eingestellt, eine vorher
   („In 10 Min: …“). Vorwarnung wählbar: 0, 5, 10, 15, 20, 30, 45, 60 Minuten.
4. **Abhaken** in der App oder per Knopf **„Erledigt“** in der Live-Aktivität: Der Schritt gilt ab jetzt, alle
   späteren rücken um denselben Betrag mit.
5. Nach dem letzten Schritt (aus dem Ofen) zeigt die Aktivität 2 Stunden „Auskühlen lassen“ und verschwindet dann.
   **„Beenden“** räumt alles sofort ab.

### 6.2 Datenmodell

```swift
struct TimerSchritt: Codable, Hashable { var at: Double; var titel: String; var dauer: String }  // at: ms seit 1970

struct BackLauf: Codable, Hashable {
    enum Phase: String, Codable { case reifen, backen }
    var phase: Phase
    var start: Double          // Sauerteig angesetzt (ms)
    var reife: [Double]        // reif zwischen [von, bis] (ms)
    var vorlauf: Int           // Vorwarnung in Minuten
    var schritte: [TimerSchritt]  // Schritt 0 = ansetzen, Schritt 1 = „Backen beginnt“ (BackLauf.beginn)
    var weiter: Int?           // erster noch nicht abgehakter Schritt
}
```

Regeln (heute in `Core/Sauerteig.swift`, genau so übernehmen):

- `hakeAb(i, jetzt)`: Verschiebung `d = jetzt - schritte[i].at`, auf Schritt `i` und alle späteren addieren,
  `weiter = i + 1`, `phase = .backen`. „Backen beginnen“ ist `hakeAb(beginn)`.
- Abhaken geht nur für den nächsten offenen Schritt oder einen schon erledigten (der wird auf jetzt aktualisiert).
  Aus der Live-Aktivität darf auch übersprungen werden (`ueberspringen: true`), sie zeigt nur den laufenden Schritt.
- Zeiten als **Zahl in ms**, nie als `Date` im Codable-Modell (siehe Stolperfallen).
- Drei Stunden nach dem letzten Schritt räumt sich der Lauf beim nächsten Start selbst ab.

**Mit Abgleich** wird der Lauf eine Tabelle `backlauf` (eine Zeile je Profil/Gruppe) mit den Feldern `phase`,
`start`, `reife`, `vorlauf`, `weiter` und `schritte` als **ein** JSON-Feld. Beenden = Löschmarke.

### 6.3 Mitteilungen (immer lokal)

- Bei jeder Änderung des Laufs (eigene oder per Abgleich empfangene): alle ausstehenden Mitteilungen mit Präfix
  `backtimer.` entfernen und aus `meldungen(jetzt:)` neu planen (`UNTimeIntervalNotificationTrigger`).
- Kennung je Mitteilung `backtimer.<index>:bald` / `backtimer.<index>:jetzt`. iOS hält höchstens 64 ausstehende
  Mitteilungen je App, deshalb höchstens 60 planen.
- `userInfo["url"] = "/backen"`: Tippen öffnet den Timer (`userNotificationCenter(_:didReceive:)` → `open(link:)`).
- Mitteilungen kommen auch bei geschlossener App. Dafür braucht es **keinen Server**. Heute schaltet Haushalt sie ab,
  sobald der Server per Push meldet (`fern`); das entfällt am Ende und in der Sauerteig-App ganz.
- Andere Geräte planen ihre Mitteilungen selbst, sobald der Lauf per Abgleich bei ihnen ankommt (stiller Push weckt
  die App).

### 6.4 Live-Aktivität: was iOS kann und was nicht

Diese Grenzen bestimmen den ganzen Aufbau:

| iOS-Regel | Folge |
|---|---|
| Starten (`Activity.request`) nur, während die App im Vordergrund ist (Ausnahme: Push-to-Start ab iOS 17.2) | Start beim Tippen auf „Backen beginnen“; beim Öffnen der App ggf. nachholen |
| Eine Aktivität ist höchstens **8 Stunden** aktiv, danach beendet iOS sie (bleibt bis zu 4 h sichtbar) | Erst ab „Backen beginnen“; die Reifezeit (oft 8–12 h) zeigt sie nicht |
| Die Ansicht wird **nicht** nach Uhrzeit neu gezeichnet, nur bei einem Update, beim Erreichen von `staleDate` oder neuem Rendern durch das System | Was sich von selbst ändern muss, über `Text(timerInterval:)` und `ProgressView(timerInterval:)` (zählen ohne Update) |
| Updates kommen von der App (`activity.update`, solange ihr Prozess läuft) oder per **APNs-Push** an den Token der Aktivität | Den Wechsel zum nächsten Schritt bei geschlossener App kann nur ein Push auslösen |
| Ein Push braucht den `.p8`-Schlüssel, der gehört nicht auf das Gerät | Kleiner Weckdienst am Server (6.6) |
| Knöpfe in der Aktivität sind `LiveActivityIntent`s, `perform()` läuft **im Prozess der App** (iOS weckt sie im Hintergrund) | „Erledigt“ ändert direkt die lokale Datenbank und die Aktivität, auch ohne Netz |
| Attribute (`ActivityAttributes`) sind fest, nur `ContentState` ändert sich | Was sich während des Backens nicht ändert, in die Attribute |

### 6.5 Live-Aktivität: Aufbau

**Wer schaltet weiter:**

1. **Die App selbst**, wann immer ihr Code läuft: beim Start, beim Öffnen, nach jedem Abhaken, im
   `LiveActivityIntent`, nach einem stillen Push. Sie rechnet den Stand aus dem lokalen Lauf (`abgleichen(lauf)`).
2. **`staleDate`** = Zeit des nächsten Schritts + 30 s. Dann zeichnet iOS die Ansicht neu, und die Ansicht rechnet
   den laufenden Schritt aus der Uhr (`laufend(jetzt)`), auch wenn kein Push kam. Das hilft einmal je Update.
3. **Der Weckdienst** (6.6) schickt zu jeder Schrittzeit einen Push mit dem neuen `ContentState`. Ohne ihn bleibt
   die Anzeige nach dem ersten fälligen Schritt stehen, bis die App wieder läuft (Mitteilungen kommen trotzdem).

**Inhalt trennen, damit der Server nichts Lesbares braucht** (neu gegenüber Haushalt heute, wo Titel und Dauer im
`ContentState` stehen und der Server sie kennt):

```swift
// Shared/BackAktivitaet.swift – in App UND Widget-Erweiterung
struct BackAktivitaet: ActivityAttributes {
    // fest für diese Aktivität, nur auf dem Gerät
    var start: Double            // ms, erkennt den Lauf wieder
    var titel: [String]          // Schritte ab „Backen beginnt“
    var dauer: [String]

    struct ContentState: Codable, Hashable {
        var zeiten: [Double]     // ms je Schritt, ändert sich beim Abhaken
        var aktuell: Int         // laufender Schritt laut Absender
        var weiter: Int? = nil   // erster offener Schritt; nur die App kennt ihn, Push lässt ihn weg

        func laufend(_ jetzt: Date) -> Int {   // Push verpasst? Die Uhr schiebt weiter.
            let ms = jetzt.timeIntervalSince1970 * 1000
            let nachUhr = zeiten.lastIndex { $0 <= ms } ?? 0
            return min(max(aktuell, nachUhr, 0), max(zeiten.count - 1, 0))
        }
        func abhakbar(_ i: Int) -> Bool { i + 1 < zeiten.count && i >= (weiter ?? 0) }
    }
}
```

Der Push-Inhalt ist damit nur `{"zeiten": [...], "aktuell": 3}`: Zeitpunkte, kein Rezept. Ändern sich Titel während
des Backens (selten, z. B. anderes Rezept geladen), beendet die App die Aktivität und startet sie neu (geht nur im
Vordergrund, und dort passiert so eine Änderung).

**Ablauf in der App** (`BackLive.abgleichen(lauf)`, Vorbild `App/BackLive.swift`):

```
lauf == nil oder phase != .backen        → alle Aktivitäten sofort beenden
letzter Schritt erreicht                 → end(content, dismissalPolicy: .after(letzter + 2 h))
es läuft eine Aktivität                  → update(content), wenn sich der Stand geändert hat
                                            (bei neuer Startzeit aktualisieren statt neu starten: kein Flackern)
keine Aktivität, für diesen Lauf noch nie
gestartet, Aktivitäten erlaubt           → Activity.request(attributes:content:pushType: .token)
```

- Merken, für welchen Lauf (`start`) schon gestartet wurde (UserDefaults). Hat man die Aktivität auf dem
  Sperrbildschirm weggewischt, startet sie für diesen Lauf **nicht** von selbst neu.
- `pushTokenUpdates` beobachten: Der Token kommt erst nach dem Start und kann wechseln. Jeder neue Token geht mit den
  Zeiten an den Weckdienst.
- `content` immer mit `staleDate` (nächster Schritt + 30 s).

**Knopf „Erledigt“:**

```swift
struct BackAbhakenIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Back-Schritt erledigt"
    static let isDiscoverable = false
    @Parameter(title: "Schritt") var schritt: Int
    @Parameter(title: "Zeit") var at: Double   // Zeit, die die Aktivität zeigte
    init() {}
    init(schritt: Int, at: Double) { self.schritt = schritt; self.at = at }
    func perform() async throws -> some IntentResult {
        await BackAbhaken.ausfuehren?(schritt, at)   // im AppDelegate gesetzt, in der Erweiterung leer
        return .result()
    }
}
enum BackAbhaken { nonisolated(unsafe) static var ausfuehren: (@Sendable (Int, Double) async -> Void)? }
```

In der App: `at` mit dem aktuellen Lauf vergleichen (passt es nicht, hat sich der Zeitplan inzwischen geändert →
nichts tun), `hakeAb(i, ueberspringen: true)`, lokal speichern (= Änderung für den Abgleich), Mitteilungen neu
planen, Aktivität aktualisieren, Weckdienst informieren. Auf das Ende warten (`await`), sonst legt iOS die App vorher
schlafen. Ohne Netz geht alles außer dem Weckdienst; der bekommt die Zeiten beim nächsten Senden.

**Ansicht** (Vorbild `HaushaltWidgets/HaushaltWidgets.swift`):

- Sperrbildschirm: „Backen läuft“, Titel des **nächsten** Schritts, „um 14:35 · 30-45 Min“, großer Countdown
  `Text(timerInterval: jetzt...naechster, countsDown: true)`, Fortschrittsbalken
  `ProgressView(timerInterval: laufender...naechster)`, darunter „Jetzt: <laufender Schritt>“ und der Knopf
  „Erledigt“ (`Button(intent:)`), wenn `abhakbar`.
- Nach dem letzten Schritt: „Fertig gebacken – Auskühlen lassen, mindestens 2 Stunden“.
- Dynamic Island: kompakt Symbol + Countdown, erweitert wie Sperrbildschirm ohne großen Countdown, minimal Symbol
  (Häkchen, wenn fertig).
- `widgetURL(URL(string: "sauerteig://backtimer"))`: Tippen öffnet den laufenden Timer.
- Die Erweiterung hat keinen Zugriff auf den Asset-Katalog der App: Akzentfarbe als Konstante.

### 6.6 Weckdienst am Server

Einzige Aufgabe: Zur richtigen Zeit einen APNs-Push an die Live-Aktivität schicken. Er braucht keine Datenbank des
Zuhauses und liest keine Rezeptdaten.

- **Anmelden**: `POST /wecker {token: "apns:<Aktivitäts-Token>", zeiten: [ms…]}`. Gleicher Token erneut → ersetzt.
  `POST /wecker/stop {token}` bei Beenden. Debug-Builds melden `apns-sandbox:<token>` (anderer APNs-Server).
- **Schleife** alle 10 s: Ist eine Zeit erreicht (und nicht älter als 10 min, z. B. nach Neustart), Push schicken:
  - Header: `apns-push-type: liveactivity`, `apns-topic: <Bundle-ID>.push-type.liveactivity`, `apns-priority: 10`,
    `apns-expiration` = jetzt + 1 h. Gleicher `.p8`-Schlüssel wie für Mitteilungen.
  - Nutzlast: `{"aps": {"timestamp": <s>, "event": "update", "content-state": {"zeiten": […], "aktuell": i},
    "stale-date": <nächste Zeit/1000 + 30>}}`. Beim letzten Schritt `"event": "end"` mit
    `"dismissal-date": <letzte Zeit/1000 + 7200>`, bei Stop `end` mit `dismissal-date` jetzt.
  - Antwortet Apple mit 410 (Token ungültig, Aktivität vom System beendet): Eintrag löschen.
- Zeit `timestamp` immer mitschicken: iOS verwirft Updates, die älter sind als das letzte.
- Vorbild: `app/backtimer.py` (`notify_activities`, `activity_state`) und `app/apns.py` (`send_activity`).

Datenschutz: Der Dienst kennt Token und Zeitpunkte, sonst nichts. Das ist die bewusste Ausnahme vom „Server liest
nichts“, ohne sie geht ein weiterschaltender Sperrbildschirm bei geschlossener App nicht.

### 6.7 Mehrere Geräte

- Der Lauf kommt per Abgleich auf die anderen Geräte. Jedes Gerät plant daraus **eigene** Mitteilungen und
  meldet **eigene** Aktivität beim Weckdienst an. Der Weckdienst kennt keine Gruppen, nur Tokens.
- Ein anderes Gerät startet seine Aktivität, sobald die App dort im Vordergrund ist. Soll sie auch ohne Öffnen
  erscheinen: Push-to-Start (iOS 17.2, `Activity<BackAktivitaet>.pushToStartTokenUpdates`). Achtung: Dann stehen die
  Attribute (Titel) in der Nutzlast und damit beim Server. Für die Sauerteig-App zunächst weglassen.
- „Erledigt“ auf Gerät A → Änderung im Abgleich → stiller Push → Gerät B aktualisiert Lauf, Mitteilungen,
  Aktivität und meldet die neuen Zeiten beim Weckdienst.

### 6.8 Prüfen für iOS 26+: AlarmKit

Seit iOS 26 gibt es AlarmKit: vom System geführte Countdowns und Alarme mit eigener Live-Aktivität, die auch durch
Fokus und Stummschaltung klingeln, ohne Server. Vor dem Bau prüfen, ob sich ein Back-Schritt als AlarmKit-Countdown
abbilden lässt (z. B. „Ofen vorheizen“ als Wecker) und ob mehrere Schritte nacheinander gehen. Könnte den Weckdienst
für den Fall „geschlossene App“ ersetzen oder ergänzen. Nicht verifiziert, bewusst als offene Frage.

---

## 7. Füttern-Erinnerung

Heute schickt der Server täglich eine Push (`feeding_reminders`, Felder `sauerteig_gefuettert` und
`sauerteig_intervall` am Profil). Am Ende und in der Sauerteig-App: eine lokale Mitteilung zum Datum
„zuletzt gefüttert + Rhythmus“ (`UNCalendarNotificationTrigger`, feste Uhrzeit), bei jedem „Gefüttert“ und bei
empfangener Änderung neu planen.

## 8. Xcode-Projekt

```
SauerteigApp/
  App/        Einstieg, AppDelegate (setzt BackAbhaken.ausfuehren), Router (Adressen), AppState
  Core/       lokale Datenbank + Änderungen + Uhr, Rechner, BackLauf, BackTimer (Mitteilungen), BackLive
  Pages/      eine Datei je Bereich (Rechner, Timer, Rezepte, Füttern)
  Design/     Farben, Bausteine
Widgets/      Widget-Erweiterung: Live-Aktivität (Ansicht)
Shared/       in beiden Zielen: BackAktivitaet (Attribute, ContentState, Intent)
Config/       xcconfig, Info.plist (App, Erweiterung), Entitlements
```

- **Info.plist der App**: `NSSupportsLiveActivities = YES`, URL-Schema (`CFBundleURLTypes`, z. B. `sauerteig`) für
  `widgetURL`. Mit Weckdienst/stillem Push: `UIBackgroundModes` → `remote-notification`.
- **Erweiterung**: `NSExtensionPointIdentifier = com.apple.widgetkit-extension`, Bundle-ID `<App-Bundle-ID>.widgets`,
  `@main struct …: WidgetBundle` mit `ActivityConfiguration(for: BackAktivitaet.self)`.
- **Entitlements**: `aps-environment` (nur mit Weckdienst/Push; braucht das bezahlte Entwicklerkonto).
- **Ordner `Shared`** in beiden Zielen (Target Membership), sonst kennt die Erweiterung Attribute und Intent nicht.
- Mitteilungen: Erlaubnis bei „Sauerteig angesetzt“ erfragen (`requestAuthorization([.alert, .sound])`),
  `willPresent` → `[.banner, .sound, .list]`, damit sie auch bei offener App erscheinen.
- Ab iOS 17 (Haushalt: iOS 17+, `Button(intent:)` in Live-Aktivitäten braucht iOS 17).

## 9. Stolperfallen (aus Haushalt gelernt)

- **`Date` im `ContentState`**: Der Decoder von ActivityKit liest `Date` als Sekunden seit 2001, der Server schickt
  aber Unix-Zeit. Immer `Double` in ms, `Date` nur als berechnete Eigenschaft.
- **`ContentState` muss genau zum Push-JSON passen.** Fehlt ein Pflichtfeld, verwirft iOS das Update still. Felder,
  die nur die App setzt, optional mit Standardwert (`weiter: Int? = nil`).
- **`String(format: "%d", …)` mit `Int`** liest nur 32 Bit: ms-Zeiten werden falsch, der Server lehnte mit `zeit` ab.
  Zahlen per String-Interpolation formatieren.
- **ms-Zeiten runden** (`.rounded()`), bevor sie verglichen oder gesendet werden; sonst stimmen Vergleiche zwischen
  JSON-Rundreise und lokalem Wert nicht (`at.rounded() == at.rounded()` im Intent).
- **Weggewischte Aktivität** nicht wieder starten (Merker je Lauf), sonst taucht sie bei jedem Öffnen auf.
- **Aktualisieren statt beenden und neu starten**, wenn sich der Lauf ändert: sonst verschwindet sie kurz.
- **Intent ohne `await`** auf die Arbeit: iOS beendet die App, bevor gespeichert ist.
- **Push-Token** kommt verzögert und wechselt: immer `pushTokenUpdates` beobachten, nicht nur `pushToken` lesen.
- **64 ausstehende Mitteilungen** je App: ältere fallen still weg.
- **Debug vs. Release**: Debug-Builds bekommen Tokens für den Sandbox-Server von APNs (`apns-sandbox:`).
- **JSON-Bool**: `true` und `1` je nach Decoder verschieden; Werte aus der Kopie tolerant lesen.

## 10. Reihenfolge für die Sauerteig-App

1. **Lokal, ein Gerät**: Datenmodell mit uid, Feldzeiten und Änderungsliste (noch ohne Senden), Rechner, Rezepte
   speichern, Füttern-Erinnerung lokal.
2. **Back-Timer**: `BackLauf`, Abhaken, lokale Mitteilungen.
3. **Live-Aktivität ohne Server**: Start bei „Backen beginnen“, Weiterschalten durch die App, `staleDate`, Knopf
   „Erledigt“. Funktioniert schon gut, solange man die App zwischendurch öffnet oder abhakt.
4. **Weckdienst**: kleiner Endpunkt (kann im bestehenden Haushalt-Add-on auf dem Pi laufen, eigenes Topic = Bundle-ID
   der Sauerteig-App), `pushType: .token`, Token und Zeiten melden.
5. **Abgleich** (wenn gewünscht): `/sync/senden|holen|live` wie Haushalt, stiller Push, später Verschlüsselung.

## Verweise in diesem Repo

| Was | Wo |
|---|---|
| Plan und Stufen | `SYNC.md` |
| Rechner, `BackLauf`, Abhaken, Mitteilungstexte | `ios/Haushalt/Core/Sauerteig.swift` |
| `BackTimer` (Mitteilungen planen, heute noch Server-Abgleich) | `ios/Haushalt/Pages/SourdoughScreen.swift` |
| Live-Aktivität starten/aktualisieren/beenden, Token | `ios/Haushalt/App/BackLive.swift` |
| Attribute, `ContentState`, Intent „Erledigt“ | `ios/Shared/BackAktivitaet.swift` |
| Ansicht Sperrbildschirm und Dynamic Island | `ios/HaushaltWidgets/HaushaltWidgets.swift` |
| Intent im AppDelegate verdrahtet | `ios/Haushalt/App/Push.swift` |
| Server: Schritte melden, Aktivität per APNs weiterschalten | `app/backtimer.py`, `app/apns.py` |
| Lokale Kopie, ausstehende Änderungen, Uhr | `ios/Haushalt/Core/LocalCopy.swift` |
| Kern in JavaScriptCore, lokale Seiten | `ios/Haushalt/Core/Kern.swift`, `ios/Haushalt/App/LocalPages.swift` |
| Timer der Web-App (gleiche Regeln) | `frontend/src/sauerteig/timer.ts` |
