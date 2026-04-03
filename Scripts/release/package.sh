#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_cmd ditto
require_cmd hdiutil
ensure_dirs

[[ -d "$APP_PATH" ]] || fail "app bundle not found at $APP_PATH; run build.sh first"

log "packaging Sparkle update zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

log "packaging installer dmg"
rm -f "$DMG_PATH"
DMG_STAGE_DIR="$RELEASE_DIR/dmg-stage"
rm -rf "$DMG_STAGE_DIR"
mkdir -p "$DMG_STAGE_DIR"
cp -R "$APP_PATH" "$DMG_STAGE_DIR/"
ln -s /Applications "$DMG_STAGE_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

log "created $ZIP_PATH"
log "created $DMG_PATH"

write_github_output "zip_path" "$ZIP_PATH"
write_github_output "dmg_path" "$DMG_PATH"
