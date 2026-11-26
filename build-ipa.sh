#!/usr/bin/env bash
# Compila un .ipa sin firmar (SideStore lo re-firma al instalar).
# Salida: build/com.rbc33.odysseus.ipa
#
# Uso: ./build-ipa.sh
set -euo pipefail

TARGET="Odysseus"
PROJECT="OdysseusClient.xcodeproj"
APP_NAME="Odysseus"
BUNDLE_ID="com.rbc33.odysseus"

cd "$(dirname "$0")"

for cmd in xcodegen xcodebuild zip; do
  command -v "$cmd" >/dev/null || { echo "❌ Falta $cmd"; exit 1; }
done

VERSION=$(sed -n -E 's/.*MARKETING_VERSION: "([^"]+)".*/\1/p' project.yml)
BUILD=$(sed -n -E 's/.*CURRENT_PROJECT_VERSION: "([^"]+)".*/\1/p' project.yml)
echo "▶︎ Compilando $APP_NAME iOS $VERSION ($BUILD)"

xcodegen generate --quiet
IPA_NAME="$BUNDLE_ID.ipa"   # SideStore deduce el bundle ID del nombre del archivo
rm -rf build/ios "build/$IPA_NAME"   # no toca el build de Mac
xcodebuild -project "$PROJECT" -target "$TARGET" -configuration Release -sdk iphoneos \
  SYMROOT="$PWD/build/ios" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  clean build | { if command -v xcbeautify >/dev/null; then xcbeautify; else cat; fi; }

APP="build/ios/Release-iphoneos/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "❌ No se encontró $APP"; exit 1; }

mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry "../$IPA_NAME" Payload)
rm -rf build/ipa

IPA="build/$IPA_NAME"
echo "✅ $PWD/$IPA ($(( $(stat -f%z "$IPA") / 1024 )) KB)"
