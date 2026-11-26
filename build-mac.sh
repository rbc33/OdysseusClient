#!/usr/bin/env bash
# Compila Odysseus para macOS (universal, firma ad-hoc) y crea el DMG.
# Salida: build/Odysseus.dmg  (versión = MARKETING_VERSION de project.yml)
#
# Uso: ./build-mac.sh [--open]   (--open abre la app al terminar)
set -euo pipefail

TARGET="OdysseusMac"
PROJECT="OdysseusClient.xcodeproj"
APP_NAME="Odysseus"
BUNDLE_ID="com.rbc33.odysseus.mac"

cd "$(dirname "$0")"

for cmd in xcodegen xcodebuild codesign hdiutil; do
  command -v "$cmd" >/dev/null || { echo "❌ Falta $cmd"; exit 1; }
done

VERSION=$(sed -n -E 's/.*MARKETING_VERSION: "([^"]+)".*/\1/p' project.yml)
BUILD=$(sed -n -E 's/.*CURRENT_PROJECT_VERSION: "([^"]+)".*/\1/p' project.yml)
echo "▶︎ Compilando $APP_NAME macOS $VERSION ($BUILD)"

xcodegen generate --quiet
DMG="build/$APP_NAME.dmg"
rm -rf build/mac "$DMG"            # no toca el build de iOS
xcodebuild -project "$PROJECT" -target "$TARGET" -configuration Release \
  SYMROOT="$PWD/build/mac" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  clean build | { if command -v xcbeautify >/dev/null; then xcbeautify; else cat; fi; }

APP="build/mac/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "❌ No se encontró $APP"; exit 1; }

echo "▶︎ Firmando (ad-hoc)"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"

echo "▶︎ Creando DMG"
STAGING="$(mktemp -d)/$APP_NAME"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$(dirname "$STAGING")"

echo "✅ $PWD/$DMG ($(( $(stat -f%z "$DMG") / 1024 )) KB)"
echo "   App: $PWD/$APP"

if [[ "${1:-}" == "--open" ]]; then
  open "$APP"
fi
