#!/bin/bash
# Publie une version : compile, notarise (Developer ID) puis crée la release GitHub avec mSILENCE.zip et son .sha256,
# que la mise à jour automatique de l'appli va chercher. Notes : _tools/changelogs/mSILENCE_<version>.txt (4 langues).
# Usage : scripts/release.sh <version>   (ex. 1.1.0 ; le tag devient v1.1.0)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?Usage : scripts/release.sh <version>}"
NOTARIZE=/Volumes/SKYRIM/TOOLS/MAC/_tools/notarize_app.sh
DIST="$(mktemp -d)"

VERSION="$VERSION" NO_INSTALL=1 ./build_app.sh
DIST="$DIST" "$NOTARIZE" build/export/mSILENCE.app
(cd "$DIST" && shasum -a 256 mSILENCE.zip > mSILENCE.zip.sha256)
python3 /Volumes/SKYRIM/TOOLS/MAC/_tools/release_notes.py mSILENCE "$VERSION" --sha "$DIST/mSILENCE.zip.sha256" -o "$DIST/notes.md"
gh release create "v$VERSION" "$DIST/mSILENCE.zip" "$DIST/mSILENCE.zip.sha256" --title "mSILENCE $VERSION" --notes-file "$DIST/notes.md"
rm -rf "$DIST"
