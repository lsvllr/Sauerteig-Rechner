# Sauerteig-Rechner

Node-Server: liefert die App aus, verwaltet Konten und Rezepte und schickt die Erinnerungen des Back-Timers per
Web-Push an alle Geräte eines Kontos.

## Konten

Ein Konto entsteht nur mit einem Einladungscode. Codes erzeugst du unter `https://sauerteig.vollrath.app/admin`
(Passwort = **admin_password**). Jeder Code gilt 14 Tage und ergibt genau ein Konto, den Namen wählt die
eingeladene Person selbst. Es gibt kein Passwort: Ein Gerät bleibt angemeldet. Weitere Geräte meldet man mit einem
Gerätecode an (15 Minuten gültig). Den erzeugt die App unter „Konto → Weiteres Gerät anmelden“, im Notfall auch
der Admin für ein Konto.

## Einstellungen

- **app_url**: öffentliche Adresse, z. B. `https://sauerteig.vollrath.app` (ohne `/` am Ende).
- **admin_password**: Passwort für `/admin`. Leer heißt: Der Admin-Bereich ist gesperrt.
- **vapid_public_key** / **vapid_private_key**: Schlüssel für Web-Push. Leer lassen: Das Add-on erzeugt beim
  ersten Start ein Paar und speichert es in `/data/vapid.json`.

Nach dem Ändern speichern und das Add-on neu starten.

## Daten

`/data/sauerteig.db` (SQLite: Konten, Rezepte, Push-Abos, laufende Back-Timer) und `/data/vapid.json`. Beide
sind in den HA-Backups enthalten. Während eines Backups stoppt das Add-on kurz.

## Erreichbarkeit

Kein Port nach außen. Im HA-Netz unter `<Hostname>:8080` (Hostname siehe Info-Seite des Add-ons), öffentlich über
das Cloudflared-Add-on (Route im Tunnel → `http://<Hostname>:8080`). Der Watchdog prüft `/healthz` und startet das
Add-on bei Bedarf neu.
