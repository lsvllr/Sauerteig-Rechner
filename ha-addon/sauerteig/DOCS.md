# Sauerteig-Rechner

Node-Server: liefert die App aus, verwaltet Konten, gleicht die Daten zwischen den Geräten eines Kontos ab und
schickt die Erinnerungen des Back-Timers per Web-Push an alle Geräte eines Kontos.

Web-App und iOS-App laufen ohne Server und ohne Konto, die Daten liegen auf dem Gerät. Der Server ist nur Relais:
Rezepte, Füttern und Back-Timer liegen bei ihm nur, solange ein Konto mindestens zwei Geräte hat, und nur
Ende-zu-Ende verschlüsselt (er kann sie nicht lesen). Neues meldet er den anderen Geräten sofort, der iOS-App
per stillem Push über dieselben APNs-Einstellungen wie der Weckdienst. Wird es wieder
eins (Gerät getrennt, ein halbes Jahr nicht gesehen), löscht er sie.

## Konten

Ein Konto braucht es nur, um Geräte zu verknüpfen. Es entsteht nur mit einem Einladungscode. Codes erzeugst du unter `https://sauerteig.vollrath.app/admin`
(Passwort = **admin_password**). Jeder Code gilt 14 Tage und ergibt genau ein Konto, den Namen wählt die
eingeladene Person selbst. Es gibt kein Passwort: Ein Gerät bleibt angemeldet. Weitere Geräte meldet man mit einem
Gerätecode an (15 Minuten gültig). Den erzeugt die App unter „Einstellungen → Geräte verknüpfen → Weiteres Gerät verknüpfen“, im Notfall auch
der Admin für ein Konto.

## Einstellungen

- **app_url**: öffentliche Adresse, z. B. `https://sauerteig.vollrath.app` (ohne `/` am Ende).
- **admin_password**: Passwort für `/admin`. Leer heißt: Der Admin-Bereich ist gesperrt.
- **vapid_public_key** / **vapid_private_key**: Schlüssel für Web-Push. Leer lassen: Das Add-on erzeugt beim
  ersten Start ein Paar und speichert es in `/data/vapid.json`.

- **apns_key_id** / **apns_team_id** / **apns_topic** / **apns_key**: Weckdienst für die iOS-App. Er schaltet die
  Live-Aktivität des Back-Timers auf dem Sperrbildschirm zum nächsten Schritt weiter, auch wenn die App zu ist.
  Schlüssel unter developer.apple.com > Certificates, IDs & Profiles > Keys mit „Apple Push Notifications
  service (APNs)“ anlegen. `apns_key_id` = Key ID, `apns_team_id` = Team ID, `apns_topic` = Bundle-ID der App,
  `apns_key` = Inhalt der `.p8`-Datei (alternativ die Datei als `/data/apns.p8` ablegen). Leer: Die Aktivität
  schaltet nur weiter, solange die App läuft; Mitteilungen kommen trotzdem (die plant das iPhone selbst).

- **gemini_api_key**: Schlüssel für die KI-Analyse der Krume im Backtagebuch der iOS-App (aistudio.google.com →
  „Get API key“). Die App schickt auf Knopfdruck Fotos vom Anschnitt und die Angaben zum Backen; der Server reicht
  sie an Google Gemini weiter und speichert nichts davon. Nur für angemeldete Konten, höchstens 30 Analysen je Konto
  und Tag. Leer: Die Analyse ist aus, alles andere geht weiter.
- **gemini_model**: Modell für die Analyse, leer = `gemini-3.5-flash`. Nur ändern, wenn Google das Modell
  abkündigt (Liste unter ai.google.dev/gemini-api/docs/models). Ist das Modell ausgelastet („high demand“), weicht
  der Server bei den nächsten Versuchen auf `gemini-3.8-flash` und `gemini-3.5-flash-lite` aus.

Nach dem Ändern speichern und das Add-on neu starten.

## Daten

`/data/sauerteig.db` (SQLite: Konten, Sitzungen, Push-Abos, Zeitplan laufender Back-Timer für den Push, Abgleich
nur bei Konten mit mindestens zwei Geräten, Weckdienst: nur Push-Token und
Uhrzeiten der Live-Aktivitäten) und `/data/vapid.json`. Beide
sind in den HA-Backups enthalten. Während eines Backups stoppt das Add-on kurz.

## Erreichbarkeit

Kein Port nach außen. Im HA-Netz unter `<Hostname>:8080` (Hostname siehe Info-Seite des Add-ons), öffentlich über
das Cloudflared-Add-on (Route im Tunnel → `http://<Hostname>:8080`). Der Watchdog prüft `/healthz` und startet das
Add-on bei Bedarf neu.
