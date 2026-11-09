#!/bin/bash
# Compile mSILENCE.app (appli + extension réseau), signée Developer ID (équipe 35KLMK53PN) et installée.
# Usage : ./build_app.sh   (NO_INSTALL=1 pour ne pas l'installer, NO_NOTARIZE=1 pour sauter la notarisation ; produit build/export/mSILENCE.app)
#
# Pourquoi cette chaîne : l'extension réseau (filtre de contenu) exige des droits Apple liés à un profil d'approvisionnement.
# Xcode ne crée le profil « Developer ID » que si l'archive porte déjà ces droits : on archive sans signature, on pose une
# signature ad hoc avec les droits, puis l'export (-allowProvisioningUpdates) la remplace par le Developer ID et son profil.
# Aucun appareil à enregistrer dans le compte développeur.
set -euo pipefail
cd "$(dirname "$0")"

TOOLS=/Volumes/SKYRIM/TOOLS
# Exception à la règle « Applications Personnelles » : macOS n'active une extension système que si l'appli est dans /Applications.
DEST="${MSILENCE_INSTALL_DIR:-/Applications}"
VERSION="${VERSION:-1.0.0}"
# Numéro de build croissant à chaque compilation : macOS ne remplace une extension système que si son numéro de build change.
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1).$(date +%y%m%d%H%M)"

# Socle et modules communs : copies reprises à chaque build.
[ -f "$TOOLS/DESIGN/Socle/swift/Socle.swift" ] && cp "$TOOLS/DESIGN/Socle/swift/Socle.swift" "$TOOLS/DESIGN/Socle/swift/WindowPresent.swift" App/
[ -f "$TOOLS/MAC/_tools/shared/Updater.swift" ] && cp "$TOOLS/MAC/_tools/shared/Updater.swift" "$TOOLS/MAC/_tools/shared/UpdaterView.swift" App/

[ -f assets/mSILENCE.icns ] || { echo "icône absente : swift scripts/make_icon.swift puis iconutil" >&2; exit 1; }

xcodegen generate --quiet
rm -rf build
xcodebuild -project mSILENCE.xcodeproj -scheme mSILENCE -configuration Release -destination 'generic/platform=macOS' \
    -archivePath build/mSILENCE.xcarchive MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    CODE_SIGNING_ALLOWED=NO archive -quiet

A=build/mSILENCE.xcarchive/Products/Applications/mSILENCE.app
EXT="$A/Contents/Library/SystemExtensions/fr.stephan.msilence.extension.systemextension"
codesign --force -s - --options runtime --entitlements Extension/Extension.entitlements "$EXT"
codesign --force -s - --options runtime --entitlements App/mSILENCE.entitlements "$A"

xcodebuild -exportArchive -archivePath build/mSILENCE.xcarchive -exportPath build/export \
    -exportOptionsPlist scripts/ExportOptions.plist -allowProvisioningUpdates -quiet
codesign --verify --deep --strict build/export/mSILENCE.app

# macOS n'active l'extension système que d'une appli notarisée (sinon « code signature invalid »).
# On notarise l'export tel quel (notarize_app.sh re-signerait l'appli et perdrait les droits liés au profil).
if [ "${NO_NOTARIZE:-0}" != 1 ]; then
    ditto -c -k --keepParent build/export/mSILENCE.app build/notarize.zip
    xcrun notarytool submit build/notarize.zip --keychain-profile "${NOTARY_PROFILE:-Applications}" --wait
    xcrun stapler staple build/export/mSILENCE.app
fi
echo "OK : build/export/mSILENCE.app"

if [ "${NO_INSTALL:-0}" != 1 ]; then
    mkdir -p "$DEST"
    osascript -e 'tell application id "fr.stephan.msilence" to quit' 2>/dev/null || true
    rm -rf "$DEST/mSILENCE.app"
    ditto build/export/mSILENCE.app "$DEST/mSILENCE.app"
    echo "Installée : $DEST/mSILENCE.app"
    # Lien dans Applications Personnelles (là où je lance mes applis) vers la vraie appli, qui doit rester dans /Applications.
    if [ "$DEST" = /Applications ]; then
        mkdir -p "$HOME/Applications/Applications Personnelles"
        ln -sfn /Applications/mSILENCE.app "$HOME/Applications/Applications Personnelles/mSILENCE.app"
    fi
fi
