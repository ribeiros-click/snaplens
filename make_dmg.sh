#!/bin/bash
# Gera SnapLens.dmg (com atalho para /Applications) a partir de SnapLens.app.
set -euo pipefail
cd "$(dirname "$0")"
[ "${1:-}" = "--no-build" ] || ./build.sh
STAGE=.build/dmg
rm -rf "$STAGE" SnapLens.dmg && mkdir -p "$STAGE"
cp -R SnapLens.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "SnapLens" -srcfolder "$STAGE" -ov -format UDZO SnapLens.dmg >/dev/null
echo "OK -> $(pwd)/SnapLens.dmg"
