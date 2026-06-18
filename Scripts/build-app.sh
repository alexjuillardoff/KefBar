#!/usr/bin/env bash
# Compile en release et assemble un vrai bundle KefBar.app
# (sans icône Dock + exception réseau local), puis l'ouvre.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "▶︎ Compilation (release)…"
swift build -c release

APP="KefBar.app"
BIN="$(swift build -c release --show-bin-path)/KefBar"

echo "Assemblage de ${APP} ..."
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
cp "${BIN}" "${APP}/Contents/MacOS/KefBar"
cp "Resources/Info.plist" "${APP}/Contents/Info.plist"

# Signature ad-hoc : évite les avertissements Gatekeeper en local.
codesign --force --sign - "${APP}" >/dev/null 2>&1 || true

echo "OK : ${APP} construit."
echo "  Lancer : open ./${APP}"
