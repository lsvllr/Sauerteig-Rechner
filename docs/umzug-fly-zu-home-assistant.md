# Umzug einer Docker-Web-App von Fly.io auf Home Assistant (Raspberry Pi) mit Cloudflare Tunnel

Vorlage aus dem Umzug der Haushalt-App (Repo lsvllr/Haushalt-tracker, 09.11.2026).
Angewendet auf den Sauerteig-Rechner am 10.11.2026 (`sauerteig.vollrath.app`, Add-on-Repo `lsvllr/sauerteig-addon`).

## Vorhandene Infrastruktur (schon eingerichtet, nicht neu anlegen)

- **Domain `vollrath.app`**: registriert bei Hetzner (dort auch Webhosting + Mail). **DNS liegt bei Cloudflare**
  (Free-Plan, Nameserver umgestellt). Mail-/Webspace-Einträge (A, AAAA, MX, SRV, TXT, autoconfig) stehen auf
  „DNS only“ und dürfen so bleiben. Subdomains für Apps legt der Tunnel selbst an (proxied).
  `.app` erzwingt HTTPS (HSTS-Preload): Cloudflare übernimmt das.
- **Cloudflare Tunnel „Haushalt“** (Zero Trust → Networks → Tunnels, Remote-Management per Token), läuft im
  HA-Add-on **Cloudflared** (Repo `https://github.com/brenner-tobias/ha-addons`, nur `tunnel_token` gesetzt).
  → Für eine neue App **keinen neuen Tunnel**, nur eine weitere Route anlegen (siehe Schritt 6).
- **Pi**: Raspberry Pi 4, 8 GB, SSD, **Home Assistant OS** (Add-ons heißen dort „Apps“). Zugriff auf HA per
  Tailscale und lokal `http://homeassistant.local:8123`. Internet über 5G-Router (ZTE, CGNAT, keine Portfreigabe
  möglich → deshalb Tunnel).
- **Samba share**-Add-on installiert (Freigabe `addon_configs`), **File editor** installiert.
- Bereits belegt:
  - `haus.vollrath.app` → Add-on `63a346db-haushalt:8000`
  - `sauerteig.vollrath.app` → Add-on `92312808-sauerteig:8080`
- Add-on-Repos (öffentlich, werden per Action befüllt): `github.com/lsvllr/haushalt-addon`,
  `github.com/lsvllr/sauerteig-addon`.

## Architektur

```
Handy ──https──> Cloudflare ──Tunnel──> HA: Cloudflared ──> HA-Add-on der App (<hostname>:<port>)
GitHub: push main → Action baut Image (amd64+arm64) → ghcr.io (öffentlich) → Action setzt Version im
Add-on-Repo → HA zeigt „Update verfügbar“ (Auto-Update an).
```

## Bausteine im App-Repo

1. **Dockerfile**
   - Build-Stufen (Frontend, Schema …) mit `FROM --platform=$BUILDPLATFORM …` → kein Emulator beim ARM-Build.
   - Laufzeit-Stufe `AS runtime`, dann HA-Labels je Architektur:
     ```dockerfile
     ARG TARGETARCH              # ganz oben, global, OHNE Vorgabewert (siehe Stolpersteine)
     …
     FROM runtime AS runtime-amd64
     LABEL io.hass.arch="amd64"
     FROM runtime AS runtime-arm64
     LABEL io.hass.arch="aarch64"
     FROM runtime-${TARGETARCH}
     ARG HA_VERSION=dev
     LABEL io.hass.type="addon" io.hass.version="${HA_VERSION}"
     ```
   - `CMD ["sh", "/code/start.sh"]` (rein statische Apps mit nginx: CMD des Basis-Images behalten).
2. **start.sh** (nur bei Apps mit Server/Einstellungen): Wenn `/data/options.json` existiert (= läuft als Add-on):
   jeden Schlüssel als ENV in Großbuchstaben exportieren (Python + `shlex.quote`, leere Werte überspringen,
   bool → 1/0), `DATA_DIR=/config` (= `/addon_configs/<id>_<slug>`, per Samba erreichbar, in HA-Backups),
   Proxy-Header für Client-IP `cf-connecting-ip`, `COOKIE_SECURE=1`. Sonst Start unverändert. Dann `exec` Server.
3. **Client-IP**: nur einen per ENV festgelegten Header vertrauen (`CLIENT_IP_HEADER`), nie mehrere
   (sonst fälschbar). Add-on hat keinen nach außen veröffentlichten Port → Header kommt nur von Cloudflare.
4. **ha-addon/** (Quelle, wird ins Add-on-Repo kopiert; dort nie von Hand ändern):
   - `repository.yaml` (name, url, maintainer), `README.md`
   - `<slug>/config.yaml`: name, description, `version: "0.0.0"` (setzt die Action), slug,
     `arch: [aarch64, amd64]`, `image: ghcr.io/lsvllr/<image>` (Tag = version), `init: false`,
     `startup: application`, `boot: auto`, `watchdog: http://[HOST]:[PORT:<port>]/healthz`, keine `ports`.
     Mit Daten zusätzlich: `backup: cold` (SQLite sauber), `map: [addon_config:rw]`,
     options/schema (`url`, `password?`, `bool` …; Vorgabe für app_url eintragen).
   - `<slug>/DOCS.md`, `<slug>/icon.png` (128×128, z. B. `sips -z 128 128 public/icon-512.png --out …`)
5. **.github/workflows/image.yml**
   - Job build: version = `sha-${GITHUB_SHA::7}`; qemu + buildx; Login ghcr mit `GITHUB_TOKEN`
     (`permissions: packages: write`); build-push `platforms: linux/amd64,linux/arm64`,
     `build-args: HA_VERSION=<version>`, Tags `latest` und `<version>`, Cache gha.
   - Job addon (needs build): `git clone https://x-access-token:${ADDON_TOKEN}@github.com/lsvllr/<addon-repo>.git`
     (git clone statt checkout: geht auch mit leerem Repo), `rsync -a --delete --exclude .git ha-addon/ addon/`,
     `sed` version in config.yaml, commit, `git push origin HEAD:main`.
   - Secret `ADDON_TOKEN`: Fine-grained Token, nur das Add-on-Repo, Contents Read and write.
   - Achtung: `rsync --delete` überschreibt das ganze Add-on-Repo → **eigenes Add-on-Repo je App**
     (oder Sync auf den eigenen Unterordner beschränken, wenn mehrere Apps in ein Repo sollen).
6. **deploy/fly-export.sh** (nur bei Daten auf dem Server): per `fly ssh console -C "python -c …"` SQLite-Dateien
   mit `sqlite3.backup()` konsistent kopieren + übrige Dateien (ohne -wal/-shm), tar nach /tmp,
   `fly ssh sftp get`; Secrets per `os.environ` in `fly-secrets.env`. Beide Dateien in `.gitignore` und
   `.dockerignore`.
7. **/healthz**: Endpunkt für Watchdog und Tunnel-Test (nginx: `location = /healthz { return 200 "ok\n"; }`).

## Ablauf

1. Neues **öffentliches** Add-on-Repo anlegen, Secret `ADDON_TOKEN` im App-Repo setzen.
2. Bausteine committen und pushen. Action „Image bauen“ abwarten (erster ARM-Build 15–25 Min.).
3. Paket auf **Public** stellen: `https://github.com/users/lsvllr/packages/container/<image>/settings`
   → Danger Zone → Change visibility. (Nicht Konto-Einstellungen → Packages; neue Pakete erben
   „privat“ vom privaten Repo.) Prüfen: anonymer Abruf des Manifests liefert amd64 + arm64.
4. HA → Apps → Store → ⋮ → Repositories → Add-on-Repo-URL (exakt, ohne `/` und `.git`). Add-on
   installieren, app_url prüfen, starten, Protokoll „startup complete“.
5. **Hostname des Add-ons** = `sha1(repo_url.lower())[:8]` + `-` + slug. Kontrolle über die Adresszeile:
   `…/config/app/<hash>_<slug>/…` → Unterstrich durch Bindestrich ersetzen.
   Berechnen: `python3 -c "import hashlib;print(hashlib.sha1(b'https://github.com/lsvllr/<addon-repo>').hexdigest()[:8])"`
6. Cloudflare → Tunnel „Haushalt“ → Add route → **Published application**: Subdomain, Domain `vollrath.app`,
   Path leer, **Service URL mit Schema**: `http://<hostname>:<port>`. Test `https://<sub>.vollrath.app/healthz`.
7. **Umzug der Daten** (entfällt bei rein statischen Apps): Geräte vorher einmal online öffnen
   (Offline-Warteschlange leeren) → `sh deploy/fly-export.sh` (flyctl im Dev-Container:
   `curl -L https://fly.io/install.sh | sh`, `export PATH="$HOME/.fly/bin:$PATH"`, `fly auth login`;
   App vorher im Browser wecken) → `fly scale count 0 -a <app>` (Volume bleibt, Rückweg `fly scale count 1`) →
   Add-on stoppen → Mac-Terminal: `smb://homeassistant.local/addon_configs`, in `<hash>_<slug>` Testdaten löschen,
   `tar -xzf ~/Downloads/fly-data.tgz` (Datei in VS Code per Rechtsklick → Download holen),
   `find . -name '._*' -delete` → Secrets in die Add-on-Konfiguration → starten → prüfen.
8. **Cron ersetzen** (falls die App einen hatte): `secrets.yaml`: `<name>_cron: "Bearer <token>"`;
   `configuration.yaml`: `rest_command: <name>: url: "http://<hostname>:<port>/<pfad>", method: POST,
   headers: Authorization: !secret <name>_cron` → Konfiguration prüfen → **HA neu starten** (nicht Quick
   reload) → in Entwicklerwerkzeuge → Aktionen testen → Automation mit Zeit-Auslöser.
9. **Aufräumen**: Fly-Workflows (Deploy, Cron) und `fly.toml` löschen, Export-Dateien löschen, Auto-Update am
   Add-on an; nach ein paar stabilen Tagen `fly apps destroy <app>` und Secret `FLY_API_TOKEN` löschen.
10. **Geräte**: neue Adresse = neuer Ursprung → Cookies, **localStorage**, Offline-Speicher und Push-Abos neu
    (Einladungslink, zum Home-Bildschirm, altes Icon löschen, Push einschalten). Daten, die nur im Browser
    liegen, gehen dabei verloren, wenn die App keinen Export hat.

## Stolpersteine (alle schon einmal aufgetreten)

- Dockerfile: `ARG TARGETARCH=amd64` mit Vorgabewert überschreibt den Wert, den BuildKit je Plattform setzt →
  auch das ARM-Image bekommt `io.hass.arch="amd64"`. Ohne Vorgabewert deklarieren. Prüfen:
  `docker buildx imagetools inspect ghcr.io/lsvllr/<image>:latest --format '{{json .Image}}'`.
  (Betrifft auch das Haushalt-Image, Stand 10.11.2026.)
- HA: „not a valid app repository“ → Add-on-Repo noch leer, Action erst laufen lassen.
- GitHub Actions „Internal server error. Correlation ID …“, Jobs gar nicht gestartet → GitHub-Störung,
  „Re-run all jobs“.
- Cloudflared „Provided Tunnel token is not valid“ → Token im Dashboard ist maskiert; Kopier-Symbol nutzen,
  nur den Teil ab `eyJ` einfügen.
- 502 auf der Subdomain → Add-on läuft nicht oder falscher Hostname/Port in der Route.
- Samba „problem connecting“ → Add-on ohne Benutzer/Passwort startet nicht; per IP verbinden; über
  Tailscale `100.64.0.0/10` in `allow_hosts`.
- Auto-Mode verweigert `curl … | sh` (Code aus dem Netz) → Nutzer führt Installer selbst aus.
- Nie fremde uncommittete Änderungen im Repo mitcommitten: nur die eigenen Dateien gezielt `git add`.
