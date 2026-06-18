#!/usr/bin/env bash
# Compile, signe (Developer ID + hardened runtime), notarise chez Apple
# et agrafe le ticket, puis produit KefBar.zip prêt à distribuer.
#
# Pré-requis (voir docs/DISTRIBUTION.md) :
#   1. Un certificat « Developer ID Application » dans le trousseau.
#   2. Un profil notarytool enregistré (xcrun notarytool store-credentials).
#
# Configuration par variables d'environnement :
#   DEVELOPER_ID    nom exact de l'identité de signature
#                   (par défaut : la première « Developer ID Application » du trousseau)
#   NOTARY_PROFILE  nom du profil notarytool (par défaut : KefBarNotary)
#
# Exemple :
#   DEVELOPER_ID="Developer ID Application: Alexis Juillard (TEAMID)" \
#   NOTARY_PROFILE="KefBarNotary" ./Scripts/notarize-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

APP="KefBar.app"
ZIP="KefBar.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-KefBarNotary}"

# Identité de signature : explicite, sinon la première Developer ID du trousseau.
if [[ -z "${DEVELOPER_ID:-}" ]]; then
  DEVELOPER_ID="$(security find-identity -v -p codesigning \
    | grep -m1 "Developer ID Application" \
    | sed -E 's/.*"([^"]+)".*/\1/')"
fi
if [[ -z "${DEVELOPER_ID:-}" ]]; then
  echo "✗ Aucun certificat « Developer ID Application » trouvé dans le trousseau." >&2
  echo "  Voir docs/DISTRIBUTION.md pour le créer." >&2
  exit 1
fi
echo "▶︎ Identité : ${DEVELOPER_ID}"
echo "▶︎ Profil notarytool : ${NOTARY_PROFILE}"

echo "▶︎ Compilation (release, binaire universel arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/KefBar"

echo "▶︎ Assemblage de ${APP}…"
rm -rf "${APP}"
mkdir -p "${APP}/Contents/MacOS"
cp "${BIN}" "${APP}/Contents/MacOS/KefBar"
cp "Resources/Info.plist" "${APP}/Contents/Info.plist"

echo "▶︎ Signature (Developer ID + hardened runtime + timestamp sécurisé)…"
codesign --force --options runtime --timestamp \
  --sign "${DEVELOPER_ID}" "${APP}"
codesign --verify --strict --verbose=2 "${APP}"

echo "▶︎ Compression pour notarisation…"
rm -f "${ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

echo "▶︎ Envoi à Apple (notarisation, attente du verdict)…"
xcrun notarytool submit "${ZIP}" \
  --keychain-profile "${NOTARY_PROFILE}" --wait

echo "▶︎ Agrafage du ticket sur ${APP}…"
xcrun stapler staple "${APP}"

echo "▶︎ Re-compression de l'app agrafée pour distribution…"
rm -f "${ZIP}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

echo "▶︎ Vérification Gatekeeper…"
spctl --assess --type execute --verbose=4 "${APP}" || true

echo
echo "✓ ${APP} notarisé et agrafé. Distribuez ${ZIP} :"
echo "  gh release upload v0.1 ${ZIP} --clobber"
