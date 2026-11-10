#!/bin/sh
# Start des Servers. Als Home-Assistant-Add-on (/data/options.json vorhanden):
#   - Einstellungen als ENV in Großbuchstaben (app_url → APP_URL, vapid_* → VAPID_*), leere Werte überspringen
#   - VAPID-Schlüssel ohne Einstellung: einmal erzeugen und in /data/vapid.json behalten (in HA-Backups),
#     damit die Push-Abos der Geräte einen Neustart überleben
# Sonst (lokal) unverändert.
set -eu
cd /app

if [ -f /data/options.json ]; then
    eval "$(node -e '
        const o = require("/data/options.json");
        const q = (s) => "\x27" + String(s).replace(/\x27/g, "\x27\\\x27\x27") + "\x27";
        for (const [k, v] of Object.entries(o)) {
            if (v === "" || v === null || v === undefined) continue;
            const w = typeof v === "boolean" ? (v ? "1" : "0") : v;
            console.log(`export ${k.toUpperCase()}=${q(w)}`);
        }
    ')"
    if [ -z "${VAPID_PUBLIC_KEY:-}" ] || [ -z "${VAPID_PRIVATE_KEY:-}" ]; then
        if [ ! -s /data/vapid.json ]; then
            node -e '
                const k = require("web-push").generateVAPIDKeys();
                require("fs").writeFileSync("/data/vapid.json", JSON.stringify(k), { mode: 0o600 });
            '
            echo "Neue VAPID-Schlüssel in /data/vapid.json erzeugt."
        fi
        eval "$(node -e '
            const k = require("/data/vapid.json");
            console.log(`export VAPID_PUBLIC_KEY=\x27${k.publicKey}\x27 VAPID_PRIVATE_KEY=\x27${k.privateKey}\x27`);
        ')"
    fi
fi

exec node dist-server/server.js
