#!/bin/bash
# Compila o SnapLens e monta SnapLens.app (com ícone) nesta pasta.
set -euo pipefail
cd "$(dirname "$0")"
APP=SnapLens.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/SnapLens"

rm -rf "$APP" .build/icon && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/icon/AppIcon.iconset
cp "$BIN" "$APP/Contents/MacOS/SnapLens"

swiftc -O Tools/make_icon.swift -o .build/icon/make_icon
.build/icon/make_icon .build/icon/icon_1024.png "${ICON:-1}"
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
  <key>CFBundleDisplayName</key><string>SnapLens</string>
  <key>CFBundleIdentifier</key><string>com.jjunior.snaplens</string>
  <key>CFBundleExecutable</key><string>SnapLens</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION:-1.0}</string>
  <key>CFBundleVersion</key><string>${BUILD:-1}</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
  <key>NSHumanReadableCopyright</key><string>© 2026 José Junior</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>com.jjunior.snaplens.auth</string>
    <key>CFBundleURLSchemes</key><array><string>snaplens</string></array>
  </dict></array>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>O SnapLens grava o microfone junto com a gravação de tela, se você ativar em Ajustes.</string>
  <key>NSScreenCaptureUsageDescription</key><string>O SnapLens precisa gravar a tela para capturar screenshots.</string>
</dict></plist>
PLIST

# Identidade estável mantém as permissões do macOS (Gravação de Tela) entre builds.
IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
if [ -n "${APPSTORE:-}" ]; then
  echo "(build App Store: assinatura feita por make_appstore.sh)"
else
  codesign --force --deep --sign "${IDENTITY:--}" "$APP"
fi
echo "OK -> $(pwd)/$APP"
