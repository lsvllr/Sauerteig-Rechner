#!/bin/bash
# Prüft den Kern (Datenbank, Uhr, Rechner, Back-Lauf, ContentState) auf dem Mac, ohne Simulator.
# Aufruf: ios/Tools/pruefe_kern.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
# BackLive.swift braucht ActivityKit (nur iOS): nur die reine Funktion `stand` als Stummel einbinden.
sed -n '/static func stand/,/^    }/p' Sauerteig/App/BackLive.swift > "$OUT/stand.swift"
{ echo 'import Foundation'; echo 'enum BackLive {'; cat "$OUT/stand.swift"; echo '}'; } > "$OUT/BackLive.swift"
# Attribute ohne ActivityKit/AppIntents
sed -e 's/^import ActivityKit//' -e 's/^import AppIntents//' -e 's/: ActivityAttributes/: Codable, Hashable/' \
    -e '/^\/\/\/ Knopf „Erledigt“/,$d' Shared/BackAktivitaet.swift > "$OUT/BackAktivitaet.swift"
swiftc -O -o "$OUT/pruefe" \
    Sauerteig/Core/*.swift "$OUT/BackLive.swift" "$OUT/BackAktivitaet.swift" Tools/Tests/main.swift 2>&1 | grep -v "^$" || true
"$OUT/pruefe"
