#!/bin/bash
# Compila o SnapLens e monta SnapLens.app (com ícone) nesta pasta.
set -euo pipefail
cd "$(dirname "$0")"
APP=SnapLens.app
# Versão: arquivo VERSION (suba a cada release); build = nº de commits (sobe sozinho a cada atualização).
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
# Credenciais OAuth do OneDrive / Google Drive (opcional): .secrets/cloud.env com
#   ONEDRIVE_CLIENT_ID=...  GOOGLE_CLIENT_ID=...  GOOGLE_CLIENT_SECRET=...  GOOGLE_API_KEY=...
# (ou as mesmas variáveis no ambiente). Sem elas, o app mostra os Drives como "não configurados".
[ -f .secrets/cloud.env ] && set -a && . .secrets/cloud.env && set +a

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SnapLens"

rm -rf "$APP" .build/icon && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/icon/AppIcon.iconset
cp "$BIN" "$APP/Contents/MacOS/SnapLens"
cp -R Sources/SnapLens/Resources/*.lproj "$APP/Contents/Resources/"

swiftc -O Tools/make_icon.swift -o .build/icon/make_icon
.build/icon/make_icon .build/icon/icon_1024.png "${ICON:-4}"
for s in 16 32 128 256 512; do
  sips -z $s $s .build/icon/icon_1024.png --out .build/icon/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) .build/icon/icon_1024.png --out .build/icon/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns .build/icon/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>SnapLens</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
  <key>CFBundleLocalizations</key><array><string>pt-BR</string><string>en</string><string>es</string><string>it</string><string>zh-Hans</string></array>
  <key>CFBundleDisplayName</key><string>SnapLens</string>
  <key>CFBundleIdentifier</key><string>com.jjunior.snaplens</string>
  <key>CFBundleExecutable</key><string>SnapLens</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>NSHumanReadableCopyright</key><string>© 2026 José Junior</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>O SnapLens grava o microfone junto com a gravação de tela, se você ativar em Ajustes.</string>
  <key>SnapLensOneDriveClientID</key><string>${ONEDRIVE_CLIENT_ID:-}</string>
  <key>SnapLensGoogleClientID</key><string>${GOOGLE_CLIENT_ID:-}</string>
  <key>SnapLensGoogleClientSecret</key><string>${GOOGLE_CLIENT_SECRET:-}</string>
  <key>SnapLensGoogleAPIKey</key><string>${GOOGLE_API_KEY:-}</string>
  <key>NSScreenCaptureUsageDescription</key><string>O SnapLens precisa gravar a tela para capturar screenshots.</string>
</dict></plist>
PLIST

# Assinatura:
#  - "Developer ID Application" (conta paga do Apple Developer Program): Hardened Runtime + timestamp,
#    pronto para notarizar (./make_dmg.sh com NOTARY_PROFILE) e abrir sem aviso do Gatekeeper.
#  - senão "Apple Development": identidade estável mantém as permissões (Gravação de Tela) entre builds.
#  - senão ad-hoc.
IDS="$(security find-identity -v -p codesigning)"
DEVID="$(sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' <<<"$IDS" | head -1)"
DEV="$(sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' <<<"$IDS" | head -1)"
if [ -n "${APPSTORE:-}" ]; then
  echo "(build App Store: assinatura feita por make_appstore.sh)"
elif [ -n "$DEVID" ] && [ -z "${NO_DEVID:-}" ]; then
  codesign --force --options runtime --timestamp --entitlements SnapLens.developerid.entitlements --sign "$DEVID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  echo "Assinado com: $DEVID"
else
  codesign --force --deep --sign "${DEV:--}" "$APP"
  echo "Assinado com: ${DEV:-ad-hoc} (sem Developer ID: o Gatekeeper vai avisar em outros Macs)"
fi
echo "OK -> $(pwd)/$APP"
