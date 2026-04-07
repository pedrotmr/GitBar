#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_cmd curl
ensure_dirs

[[ -f "$APPCAST_PATH" ]] || fail "appcast not found at $APPCAST_PATH"

verify_appcast_enclosure_urls "$APPCAST_PATH"
log "enclosure URLs OK for $APPCAST_PATH"
