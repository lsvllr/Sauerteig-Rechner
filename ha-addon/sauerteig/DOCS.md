# Sauerteig-Rechner

Node-Server: liefert die App aus und schickt die Erinnerungen des Back-Timers per Web-Push. Rezepte liegen im
Browser der Geräte, laufende Back-Timer nur im Speicher des Servers (die App meldet sie nach einem Neustart beim
nächsten Öffnen erneut).

## Einstellungen

- **app_url**: öffentliche Adresse, z. B. `https://sauerteig.vollrath.app` (ohne `/` am Ende). Steht als Kontakt
  in den Push-Nachrichten.
- **vapid_public_key** / **vapid_private_key**: Schlüssel für Web-Push. Leer lassen: das Add-on erzeugt beim
  ersten Start ein Paar und behält es in `/data/vapid.json` (in den HA-Backups enthalten). Nur eintragen, wenn
  bestehende Push-Abos weiter gelten sollen (gleiche Adresse wie vorher).

Nach dem Ändern speichern und das Add-on neu starten.

## Erreichbarkeit

Kein Port nach außen. Im HA-Netz unter `<Hostname>:8080` (Hostname siehe Info-Seite des Add-ons), öffentlich über
das Cloudflared-Add-on (Route im Tunnel → `http://<Hostname>:8080`). Der Watchdog prüft `/healthz` und startet das
Add-on bei Bedarf neu.
