#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

if [[ "$RELEASE_MODE" != "production" ]]; then
  log "preview mode: skipping notarization"
  write_github_output "notarization" "skipped"
  exit 0
fi

require_cmd xcrun

[[ -f "$DMG_PATH" ]] || fail "dmg not found at $DMG_PATH; run package.sh first"
: "${APPLE_ID:?APPLE_ID is required in production mode}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required in production mode}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?APPLE_APP_SPECIFIC_PASSWORD is required in production mode}"

log "submitting $DMG_PATH for notarization"
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait

log "stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
if [[ -d "$APP_PATH" ]]; then
  xcrun stapler staple "$APP_PATH" || true
fi

write_github_output "notarization" "completed"
