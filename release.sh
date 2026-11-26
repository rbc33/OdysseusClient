#!/usr/bin/env bash
# Sube la versión, compila iOS (.ipa) y macOS (.dmg), publica ambos en GitHub Releases,
# actualiza source.json (SideStore) y el cask del tap de Homebrew.
#
# Uso: ./release.sh 1.1.0 ["Notas de la versión"]
set -euo pipefail

REPO="rbc33/OdysseusClient"
BRANCH="main"
APP_NAME="Odysseus"
BUNDLE_ID="com.rbc33.odysseus"
MAC_BUNDLE_ID="com.rbc33.odysseus.mac"
MIN_OS="17.0"

TAP_REPO="rbc33/homebrew-odysseusclient"
CASK="odysseusclient"

VERSION="${1:?Uso: ./release.sh <versión> [notas]}"
NOTES="${2:-$APP_NAME $VERSION}"
TAG="v$VERSION"

cd "$(dirname "$0")"
TAP_DIR="$(cd .. && pwd)/homebrew-odysseusclient"   # junto a homebrew-ghostbar, homebrew-purrl…

# --- Comprobaciones ---------------------------------------------------------
for cmd in gh python3 shasum; do
  command -v "$cmd" >/dev/null || { echo "❌ Falta $cmd"; exit 1; }
done
[[ -z "$(git status --porcelain)" ]] || { echo "❌ Hay cambios sin commitear"; exit 1; }
if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  echo "❌ El release $TAG ya existe"; exit 1
fi

# Tap de Homebrew: se crea y clona la primera vez
if [[ ! -d "$TAP_DIR/.git" ]]; then
  if ! gh repo view "$TAP_REPO" >/dev/null 2>&1; then
    echo "▶︎ Creando $TAP_REPO"
    gh repo create "$TAP_REPO" --public --description "Homebrew tap for Odysseus (macOS client)"
  fi
  gh repo clone "$TAP_REPO" "$TAP_DIR"
fi
if [[ -n "$(git -C "$TAP_DIR" status --porcelain)" ]]; then
  echo "❌ El tap ($TAP_DIR) tiene cambios sin commitear"; exit 1
fi
git -C "$TAP_DIR" pull -q --rebase 2>/dev/null || true   # el repo recién creado está vacío

# --- Versión ----------------------------------------------------------------
CURRENT_BUILD=$(sed -n -E 's/.*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' project.yml)
BUILD=$(( ${CURRENT_BUILD:-0} + 1 ))
sed -i '' -E "s/(MARKETING_VERSION: )\"[^\"]*\"/\1\"$VERSION\"/" project.yml
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$BUILD\"/" project.yml
echo "▶︎ $APP_NAME $VERSION ($BUILD)"

# Si algún build falla, deja project.yml como estaba
trap 'status=$?; [[ $status -ne 0 ]] && git checkout -q project.yml 2>/dev/null; exit $status' EXIT

# --- Build ------------------------------------------------------------------
./build-ipa.sh
./build-mac.sh

IPA_NAME="$BUNDLE_ID.ipa"   # SideStore deduce el bundle ID del nombre del archivo
IPA="build/$IPA_NAME"
DMG_NAME="$APP_NAME.dmg"
DMG="build/$DMG_NAME"
[[ -f "$IPA" ]] || { echo "❌ No se generó $IPA"; exit 1; }
[[ -f "$DMG" ]] || { echo "❌ No se generó $DMG"; exit 1; }
SIZE=$(stat -f%z "$IPA")
DMG_SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')

trap - EXIT

# --- Git + GitHub Release ---------------------------------------------------
git add project.yml
git commit -m "Bump version to $VERSION ($BUILD)"
git tag "$TAG"
git push origin "$BRANCH" "$TAG"

gh release create "$TAG" "$IPA" "$DMG" -R "$REPO" --title "$APP_NAME $VERSION" --notes "$NOTES"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG/$IPA_NAME"

# --- source.json (SideStore) ------------------------------------------------
python3 - "$VERSION" "$BUILD" "$DOWNLOAD_URL" "$SIZE" "$NOTES" "$MIN_OS" "$BUNDLE_ID" "$REPO" <<'PY'
import datetime, json, sys

version, build, url, size, notes, min_os, bundle, repo = sys.argv[1:]
size = int(size)
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

with open("source.json") as f:
    text = f.read()
# Migración tras renombrar el repo (odysseus-ios → OdysseusClient)
text = text.replace("rbc33/odysseus-ios", repo)
src = json.loads(text)
src["website"] = f"https://github.com/{repo}"

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

# --- Homebrew cask ----------------------------------------------------------
mkdir -p "$TAP_DIR/Casks"
cat > "$TAP_DIR/Casks/$CASK.rb" <<RUBY
cask "$CASK" do
  version "$VERSION"
  sha256 "$DMG_SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/$DMG_NAME"
  name "$APP_NAME"
  desc "Native macOS client for a self-hosted Odysseus AI workspace"
  homepage "https://github.com/$REPO"

  depends_on macos: ">= :sonoma"

  app "$APP_NAME.app"

  # Firma ad-hoc (sin notarizar): quitar la cuarentena para que Gatekeeper la abra
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/$APP_NAME.app"]
  end

  zap trash: [
    "~/Library/Preferences/$MAC_BUNDLE_ID.plist",
    "~/Library/WebKit/$MAC_BUNDLE_ID",
    "~/Library/Caches/$MAC_BUNDLE_ID",
    "~/Library/HTTPStorages/$MAC_BUNDLE_ID",
  ]
end
RUBY

if [[ ! -f "$TAP_DIR/README.md" ]]; then
  cat > "$TAP_DIR/README.md" <<MD
# homebrew-odysseusclient

\`\`\`bash
brew install --cask rbc33/odysseusclient/odysseusclient
\`\`\`

Cliente macOS para Odysseus self-hosted: https://github.com/$REPO
MD
fi

git -C "$TAP_DIR" add -A
git -C "$TAP_DIR" commit -q -m "Update $CASK to $VERSION"
git -C "$TAP_DIR" push -q origin HEAD:main

echo
echo "✅ Release $TAG publicado"
echo "   SideStore: https://raw.githubusercontent.com/$REPO/$BRANCH/source.json"
echo "   Homebrew:  brew install --cask rbc33/odysseusclient/odysseusclient"
