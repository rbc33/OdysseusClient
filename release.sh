#!/usr/bin/env bash
# Compila un .ipa sin firmar (SideStore lo re-firma), lo sube a GitHub Releases
# y actualiza source.json para SideStore/AltStore.
#
# Uso: ./release.sh 1.0.1 ["Notas de la versión"]
set -euo pipefail

REPO="rbc33/odysseus-ios"
BRANCH="main"
TARGET="Odysseus"
PROJECT="OdysseusClient.xcodeproj"
APP_NAME="Odysseus"
BUNDLE_ID="com.rbc33.odysseus"
MIN_OS="17.0"

VERSION="${1:?Uso: ./release.sh <versión> [notas]}"
NOTES="${2:-$APP_NAME $VERSION}"
TAG="v$VERSION"

cd "$(dirname "$0")"

# --- Comprobaciones ---------------------------------------------------------
for cmd in xcodegen xcodebuild gh python3 zip; do
  command -v "$cmd" >/dev/null || { echo "❌ Falta $cmd"; exit 1; }
done
[[ -z "$(git status --porcelain)" ]] || { echo "❌ Hay cambios sin commitear"; exit 1; }
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "❌ El release $TAG ya existe"; exit 1
fi

# --- Versión ----------------------------------------------------------------
CURRENT_BUILD=$(sed -n -E 's/.*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' project.yml)
BUILD=$(( ${CURRENT_BUILD:-0} + 1 ))
sed -i '' -E "s/(MARKETING_VERSION: )\"[^\"]*\"/\1\"$VERSION\"/" project.yml
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$BUILD\"/" project.yml
echo "▶︎ $APP_NAME $VERSION ($BUILD)"

# --- Build ------------------------------------------------------------------
xcodegen generate --quiet
rm -rf build
xcodebuild -project "$PROJECT" -target "$TARGET" -configuration Release -sdk iphoneos \
  SYMROOT="$PWD/build" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  clean build | { if command -v xcbeautify >/dev/null; then xcbeautify; else cat; fi; }

APP="build/Release-iphoneos/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "❌ No se encontró $APP"; exit 1; }

# --- Empaquetar .ipa --------------------------------------------------------
IPA_NAME="$APP_NAME-$VERSION.ipa"
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/
(cd build/ipa && zip -qry "../$IPA_NAME" Payload)
IPA="build/$IPA_NAME"
SIZE=$(stat -f%z "$IPA")
echo "✔︎ $IPA ($((SIZE / 1024)) KB)"

# --- Git + GitHub Release ---------------------------------------------------
git add project.yml
git commit -m "Bump version to $VERSION ($BUILD)"
git tag "$TAG"
git push origin "$BRANCH" "$TAG"

gh release create "$TAG" "$IPA" -R "$REPO" --title "$APP_NAME $VERSION" --notes "$NOTES"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$IPA_NAME"

# --- source.json ------------------------------------------------------------
python3 - "$VERSION" "$BUILD" "$DOWNLOAD_URL" "$SIZE" "$NOTES" "$MIN_OS" "$BUNDLE_ID" <<'PY'
import datetime, json, sys

version, build, url, size, notes, min_os, bundle = sys.argv[1:]
size = int(size)
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

with open("source.json") as f:
    src = json.load(f)

app = next(a for a in src["apps"] if a["bundleIdentifier"] == bundle)
entry = {
    "version": version,
    "buildVersion": build,
    "date": date,
    "localizedDescription": notes,
    "downloadURL": url,
    "size": size,
    "minOSVersion": min_os,
}
app["versions"] = [entry] + [v for v in app.get("versions", []) if v.get("version") != version]
# Campos legacy para clientes antiguos de AltStore
app.update(version=version, versionDate=date, versionDescription=notes, downloadURL=url, size=size)

with open("source.json", "w") as f:
    json.dump(src, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY

git add source.json
git commit -m "Update SideStore source for $VERSION"
git push origin "$BRANCH"

echo
echo "✅ Release $TAG publicado"
echo "   Source para SideStore: https://raw.githubusercontent.com/$REPO/$BRANCH/source.json"
