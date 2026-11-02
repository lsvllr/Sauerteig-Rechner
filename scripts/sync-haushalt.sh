#!/bin/sh
# Übernimmt den Sauerteig-Rechner aus der Haushalt-App: Rechenkern, Oberfläche (React), deren CSS und das
# Basis-CSS der Haushalt-App (Karten, Regler, Schalter, Farben). Quelle ist immer die Haushalt-App; die Kopien
# in src/gemeinsam/ werden mit eingecheckt, damit der Build (Docker/Fly) ohne das Haushalt-Repo auskommt.
#
# Aufruf: scripts/sync-haushalt.sh [Pfad zum Haushalt-Repo]   (Standard: ../../Haushalt tracker)
set -eu
cd "$(dirname "$0")/.."
H="${1:-../../Haushalt tracker}"
Q="$H/frontend/src/sauerteig"
Z=src/gemeinsam
[ -d "$Q" ] || { echo "Haushalt-Repo nicht gefunden: $H" >&2; exit 1; }
mkdir -p "$Z"
# Alle Dateien des Rechners; in der Haushalt-App gelöschte verschwinden auch hier.
find "$Z" -maxdepth 1 -type f ! -name haushalt.css ! -name QUELLE -delete
for f in "$Q"/*; do
    [ -f "$f" ] && cp "$f" "$Z/"
done
cp "$H/app/static/style.css" "$Z/haushalt.css"
stand=$(git -C "$H" rev-parse --short HEAD 2>/dev/null || echo unbekannt)
# Nur die übernommenen Dateien zählen (andere offene Änderungen im Haushalt-Repo sind egal).
if [ -n "$(git -C "$H" status --porcelain -- frontend/src/sauerteig app/static/style.css 2>/dev/null)" ]; then
    stand="$stand mit lokalen Änderungen"
fi
zweig=$(git -C "$H" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unbekannt)
printf 'Haushalt-App, Branch %s, Stand %s\n' "$zweig" "$stand" > "$Z/QUELLE"
echo "Übernommen aus $H ($zweig, $stand)"
