#!/usr/bin/env bash
# Actualiza este proyecto con el contenido de un OdysseusClient.zip nuevo.
#
# Uso: ./update.sh [ruta/al/zip] [--delete]
#   Por defecto usa ~/Downloads/OdysseusClient.zip
#   --delete  borra también los archivos que ya no vienen en el zip
set -euo pipefail

DEST="$(cd "$(dirname "$0")" && pwd)"
ZIP="$HOME/Downloads/OdysseusClient.zip"
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

echo "▶︎ $ZIP → $DEST"
rsync -a ${DELETE[@]+"${DELETE[@]}"} \
  --exclude '.git/' \
  --exclude 'build/' \
  --exclude '*.xcodeproj/' \
  --exclude 'DerivedData/' \
  --exclude 'xcuserdata/' \
  --exclude '.DS_Store' \
  --exclude 'icon.png' \
  "$SRC/" "$DEST/"

chmod +x "$DEST/release.sh" "$DEST/update.sh" 2>/dev/null || true

if command -v xcodegen >/dev/null; then
  (cd "$DEST" && xcodegen generate --quiet) && echo "✔︎ Proyecto Xcode regenerado"
fi

if git -C "$DEST" rev-parse --git-dir >/dev/null 2>&1; then
  echo
  git -C "$DEST" status --short
fi

echo "✅ Actualizado"
