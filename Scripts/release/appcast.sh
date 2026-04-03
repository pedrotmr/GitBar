#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_cmd xcodebuild
ensure_dirs

[[ -f "$ZIP_PATH" ]] || fail "zip archive not found at $ZIP_PATH; run package.sh first"

build_generate_appcast() {
  local tool_path="$TOOLS_DIR/generate_appcast"
  if [[ -x "$tool_path" ]]; then
    echo "$tool_path"
    return
  fi

  local sparkle_checkout="$TOOLS_DIR/Sparkle"
  rm -rf "$sparkle_checkout"
  log "cloning Sparkle sources for generate_appcast"
  git clone --depth 1 https://github.com/sparkle-project/Sparkle.git "$sparkle_checkout"

  log "building generate_appcast"
  xcodebuild \
    -project "$sparkle_checkout/Sparkle.xcodeproj" \
    -scheme generate_appcast \
    -configuration Release \
    -derivedDataPath "$TOOLS_DIR/derived" \
    build >&2

  cp "$TOOLS_DIR/derived/Build/Products/Release/generate_appcast" "$tool_path"
  chmod +x "$tool_path"
  echo "$tool_path"
}

if [[ -z "$SPARKLE_DOWNLOAD_URL_PREFIX" ]]; then
  if [[ -n "${GITHUB_REPOSITORY:-}" && -n "${GITHUB_REF_NAME:-}" ]]; then
    SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/${GITHUB_REPOSITORY}/releases/download/${GITHUB_REF_NAME}"
  else
    fail "SPARKLE_DOWNLOAD_URL_PREFIX is required when not running from tagged GitHub Actions"
  fi
fi

GENERATE_APPCAST=$(build_generate_appcast)

rm -rf "$APPCAST_ARCHIVES_DIR"
mkdir -p "$APPCAST_ARCHIVES_DIR"
cp "$ZIP_PATH" "$APPCAST_ARCHIVES_DIR/"

args=(
  --download-url-prefix "$SPARKLE_DOWNLOAD_URL_PREFIX"
  -o "$APPCAST_ARCHIVES_DIR/$APPCAST_FILENAME"
)

if [[ -n "$SPARKLE_RELEASE_NOTES_URL_PREFIX" ]]; then
  args+=(--release-notes-url-prefix "$SPARKLE_RELEASE_NOTES_URL_PREFIX")
fi

if [[ -n "$SPARKLE_CHANNEL" ]]; then
  args+=(--channel "$SPARKLE_CHANNEL")
fi

if [[ -n "$SPARKLE_PRIVATE_KEY" ]]; then
  log "generating signed appcast"
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$GENERATE_APPCAST" --ed-key-file - "${args[@]}" "$APPCAST_ARCHIVES_DIR"
else
  log "SPARKLE_PRIVATE_KEY not set; generating unsigned appcast"
  "$GENERATE_APPCAST" "${args[@]}" "$APPCAST_ARCHIVES_DIR"
fi

cp "$APPCAST_ARCHIVES_DIR/$APPCAST_FILENAME" "$APPCAST_PATH"

log "appcast generated at $APPCAST_PATH"
write_github_output "appcast_path" "$APPCAST_PATH"
write_github_output "appcast_filename" "$APPCAST_FILENAME"
