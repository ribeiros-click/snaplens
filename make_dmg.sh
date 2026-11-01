#!/bin/bash
# Gera SnapLens.dmg (com atalho para /Applications) a partir de SnapLens.app.
#
# Com certificado "Developer ID Application" no Keychain, o app e o DMG são assinados.
# Para também notarizar (o Mac abre sem aviso, sem "botão direito → Abrir"), salve uma vez as credenciais:
#   xcrun notarytool store-credentials snaplens --apple-id SEU@EMAIL --team-id SEUTEAMID
#   (pede uma senha específica de app: appleid.apple.com → Iniciar sessão e segurança → Senhas de apps)
# e rode:  NOTARY_PROFILE=snaplens ./make_dmg.sh
set -euo pipefail
cd "$(dirname "$0")"
[ "${1:-}" = "--no-build" ] || ./build.sh
STAGE=.build/dmg
rm -rf "$STAGE" SnapLens.dmg && mkdir -p "$STAGE"
cp -R SnapLens.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "SnapLens" -srcfolder "$STAGE" -ov -format UDZO SnapLens.dmg >/dev/null

DEVID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
if [ -n "$DEVID" ]; then
  codesign --force --timestamp --sign "$DEVID" SnapLens.dmg
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "Enviando para notarização (leva de 1 a 15 minutos)…"
    xcrun notarytool submit SnapLens.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple SnapLens.dmg
    spctl --assess --type open --context context:primary-signature --verbose=2 SnapLens.dmg
  else
    echo "(DMG assinado; defina NOTARY_PROFILE para notarizar)"
  fi
else
  echo "(sem certificado Developer ID: DMG não assinado nem notarizado)"
fi
echo "OK -> $(pwd)/SnapLens.dmg"
