#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/common.sh"

require_cmd xcodebuild
require_cmd /usr/libexec/PlistBuddy
require_cmd codesign
ensure_dirs

log "building archive for ${APP_NAME} (${VERSION_TAG}) in ${RELEASE_MODE} mode"
rm -rf "$ARCHIVE_PATH"

build_args=(
  -project "$ROOT_DIR/$XCODE_PROJECT"
  -scheme "$XCODE_SCHEME"
  -configuration "$XCODE_CONFIGURATION"
  -archivePath "$ARCHIVE_PATH"
  archive
)

if [[ "$RELEASE_MODE" == "preview" ]]; then
  build_args+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

xcodebuild "${build_args[@]}"

[[ -d "$APP_PATH" ]] || fail "missing app bundle at $APP_PATH"

if [[ "$RELEASE_MODE" == "preview" ]]; then
  if [[ -n "$SPARKLE_FEED_URL" ]]; then
    /usr/libexec/PlistBuddy -c "Set :SUFeedURL $SPARKLE_FEED_URL" "$APP_PATH/Contents/Info.plist" \
      || /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$APP_PATH/Contents/Info.plist"
  fi

  if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
    /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $SPARKLE_PUBLIC_KEY" "$APP_PATH/Contents/Info.plist" \
      || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$APP_PATH/Contents/Info.plist"
  fi

  # Sparkle's generate_appcast validates Apple code signatures.
  # In preview mode we re-sign ad-hoc after plist mutation.
  codesign --force --deep --sign - "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
fi

log "archive created at $ARCHIVE_PATH"
write_github_output "archive_path" "$ARCHIVE_PATH"
write_github_output "app_path" "$APP_PATH"
write_github_output "version" "$VERSION_TAG"
