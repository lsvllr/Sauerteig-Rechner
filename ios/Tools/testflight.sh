#!/bin/bash
# Baut die iOS-App auf dem Mac und lädt sie zu TestFlight hoch (Stand des Ordners, wie er ist).
# Aufruf im Terminal des Macs:  ios/Tools/testflight.sh            prüft den Kern, archiviert, lädt hoch
#                               ios/Tools/testflight.sh --nur-bauen  nur archivieren (ohne Hochladen)
#
# Voraussetzung: Xcode 26 oder neuer, App in App Store Connect angelegt (Bundle-ID aus Config/Sauerteig.xcconfig).
# Signieren und Hochladen laufen über das in Xcode angemeldete Konto (Xcode > Settings > Accounts).
# Ohne Xcode-Konto (z. B. per SSH oder cron) geht es mit einem App-Store-Connect-API-Schlüssel:
#   ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=/pfad/AuthKey_….p8 ios/Tools/testflight.sh
set -euo pipefail

[ "$(uname)" = Darwin ] || { echo "Nur auf dem Mac ausführen." >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "xcodebuild fehlt: Xcode installieren." >&2; exit 1; }
cd "$(dirname "$0")/.."

NUR_BAUEN=0
[ "${1:-}" = "--nur-bauen" ] && NUR_BAUEN=1

# Build-Nummer aus Datum und Uhrzeit (UTC): steigt immer.
BUILD_NUMBER=$(date -u +%y%m%d.%H%M)
VERSION=$(grep -E '^MARKETING_VERSION' Config/Sauerteig.xcconfig | sed 's/.*= *//')
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

AUTH=()
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] && [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "▸ Anmeldung per API-Schlüssel $ASC_KEY_ID"
fi

echo "▸ Prüfe den Kern …"
Tools/pruefe_kern.sh

echo "▸ Archiviere Version $VERSION ($BUILD_NUMBER) …"
xcodebuild archive \
  -project Sauerteig.xcodeproj \
  -scheme Sauerteig \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$WORK/Sauerteig.xcarchive" \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"} \
  -quiet \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

if [ "$NUR_BAUEN" = 1 ]; then
  mkdir -p build
  rm -rf build/Sauerteig.xcarchive
  mv "$WORK/Sauerteig.xcarchive" build/
  echo "✓ Archiv in ios/build/Sauerteig.xcarchive (nicht hochgeladen)."
  exit 0
fi

echo "▸ Signiere und lade zu TestFlight hoch …"
xcodebuild -exportArchive \
  -archivePath "$WORK/Sauerteig.xcarchive" \
  -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "$WORK/export" \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"} \
  -quiet

echo "✓ Version $VERSION ($BUILD_NUMBER) hochgeladen. Nach 5–30 Minuten Verarbeitung erscheint sie in TestFlight."
