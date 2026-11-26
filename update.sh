#!/usr/bin/env bash
# Actualiza este proyecto con el contenido de un OdysseusClient.zip nuevo.
#
# Uso: ./update.sh [ruta/al/zip] [--delete]
#   Por defecto usa el zip junto a la carpeta del proyecto (~/code/swift/OdysseusClient.zip)
#   --delete  borra también los archivos que ya no vienen en el zip
set -euo pipefail

DEST="$(cd "$(dirname "$0")" && pwd)"
ZIP="$(dirname "$DEST")/OdysseusClient.zip"   # ~/code/swift/OdysseusClient.zip
DELETE=()

for arg in "$@"; do
  case "$arg" in
    --delete) DELETE=(--delete) ;;
    *) ZIP="$arg" ;;
  esac
done

[[ -f "$ZIP" ]] || { echo "❌ No existe $ZIP"; exit 1; }
command -v rsync >/dev/null || { echo "❌ Falta rsync"; exit 1; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/odysseus-update.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

unzip -q "$ZIP" -d "$TMP"
rm -rf "$TMP/__MACOSX"

# El zip trae una carpeta OdysseusClient/; si no, usa la raíz
SRC="$TMP/OdysseusClient"
[[ -d "$SRC" ]] || SRC="$TMP"

# release.sh gestiona la versión y source.json: no dejar que un zip antiguo los pise
OLD_VERSION=$(sed -n -E 's/.*MARKETING_VERSION: "([^"]+)".*/\1/p' "$DEST/project.yml" 2>/dev/null || true)
OLD_BUILD=$(sed -n -E 's/.*CURRENT_PROJECT_VERSION: "([^"]+)".*/\1/p' "$DEST/project.yml" 2>/dev/null || true)

echo "▶︎ $ZIP → $DEST"
rsync -a ${DELETE[@]+"${DELETE[@]}"} \
  --exclude '.git/' \
  --exclude 'build/' \
  --exclude '*.xcodeproj/' \
  --exclude 'DerivedData/' \
  --exclude 'xcuserdata/' \
  --exclude '.DS_Store' \
  --exclude 'source.json' \
  "$SRC/" "$DEST/"

if [[ -n "$OLD_VERSION" && -n "$OLD_BUILD" ]]; then
  sed -i '' -E "s/(MARKETING_VERSION: )\"[^\"]*\"/\1\"$OLD_VERSION\"/" "$DEST/project.yml"
  sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"[^\"]*\"/\1\"$OLD_BUILD\"/" "$DEST/project.yml"
fi

chmod +x "$DEST"/*.sh 2>/dev/null || true

if command -v xcodegen >/dev/null; then
  (cd "$DEST" && xcodegen generate --quiet) && echo "✔︎ Proyecto Xcode regenerado"
fi

if git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1; then
  echo
  git -C "$DEST" status --short
fi

echo "✅ Actualizado"
