#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

ensure_dirs

[[ -f "$ZIP_PATH" ]] || fail "zip asset missing at $ZIP_PATH"
[[ -f "$DMG_PATH" ]] || fail "dmg asset missing at $DMG_PATH"
[[ -f "$APPCAST_PATH" ]] || fail "appcast missing at $APPCAST_PATH"

PUBLISH_DIR="$RELEASE_DIR/publish"
rm -rf "$PUBLISH_DIR"
mkdir -p "$PUBLISH_DIR/assets"

cp "$ZIP_PATH" "$PUBLISH_DIR/assets/"
cp "$DMG_PATH" "$PUBLISH_DIR/assets/"
cp "$APPCAST_PATH" "$PUBLISH_DIR/assets/"

cat > "$PUBLISH_DIR/release-metadata.json" <<META
{
  "app": "${APP_NAME}",
  "version": "${VERSION_TAG}",
  "mode": "${RELEASE_MODE}",
  "assets": [
    "$(basename "$ZIP_PATH")",
    "$(basename "$DMG_PATH")",
    "$(basename "$APPCAST_PATH")"
  ]
}
META

log "publish assets staged at $PUBLISH_DIR"
write_github_output "publish_dir" "$PUBLISH_DIR"
