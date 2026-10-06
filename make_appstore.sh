#!/bin/bash
# Gera SnapLens.pkg para envio à Mac App Store (Transporter / altool).
#
# Pré-requisitos (developer.apple.com → Certificates, Identifiers & Profiles):
#   1. Certificado "Apple Distribution" (ou "3rd Party Mac Developer Application") no Keychain
#   2. Certificado "Mac Installer Distribution" (ou "3rd Party Mac Developer Installer") no Keychain
#   3. App ID com.jjunior.snaplens + perfil "Mac App Store Connect" salvo como SnapLens.provisionprofile
#   4. App criado no App Store Connect com o mesmo Bundle ID
#
# Uso: VERSION=1.0 BUILD=1 ICON=1 ./make_appstore.sh
set -euo pipefail
cd "$(dirname "$0")"
APP=SnapLens.app
PROFILE=SnapLens.provisionprofile

[ -f "$PROFILE" ] || { echo "Falta $PROFILE (perfil Mac App Store do App ID com.jjunior.snaplens)"; exit 1; }
APP_ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(\(Apple Distribution\|3rd Party Mac Developer Application\):[^"]*\)".*/\1/p' | head -1)"
PKG_ID="$(security find-identity -v | sed -n 's/.*"\(\(Mac Installer Distribution\|3rd Party Mac Developer Installer\):[^"]*\)".*/\1/p' | head -1)"
[ -n "$APP_ID" ] || { echo "Certificado Apple Distribution não encontrado no Keychain"; exit 1; }
[ -n "$PKG_ID" ] || { echo "Certificado Mac Installer Distribution não encontrado no Keychain"; exit 1; }

APPSTORE=1 ./build.sh
cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"

# Identificadores vindos do perfil (obrigatórios nos entitlements da App Store)
PLIST=.build/profile.plist
security cms -D -i "$PROFILE" > "$PLIST"
TEAM="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' "$PLIST")"
APPID="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' "$PLIST")"
ENT=.build/SnapLens.appstore.entitlements
cp SnapLens.entitlements "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APPID" "$ENT"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM" "$ENT"

codesign --force --options runtime --timestamp --entitlements "$ENT" --sign "$APP_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

rm -f SnapLens.pkg
productbuild --component "$APP" /Applications --sign "$PKG_ID" SnapLens.pkg
echo "OK -> $(pwd)/SnapLens.pkg  (envie com o app Transporter)"
