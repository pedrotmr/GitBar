#!/usr/bin/env bash
# Regenerate Resources/Assets.xcassets/AppIcon.appiconset from Resources/AppIcon.icon
# (Icon Composer bundle). Requires Icon Composer (usually from Additional Tools for Xcode).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

ICON_SRC="${1:-$ROOT/Resources/AppIcon.icon}"
APPICONSET="$ROOT/Resources/Assets.xcassets/AppIcon.appiconset"
OUT_ROOT="$ROOT/build/icon-gen"
XCODE_DEV_DIR="$(xcode-select -p 2>/dev/null || true)"
if [[ -z "${XCODE_APP:-}" ]]; then
  if [[ -n "$XCODE_DEV_DIR" ]]; then
    XCODE_APP="${XCODE_DEV_DIR%/Contents/Developer}"
  else
    XCODE_APP="/Applications/Xcode.app"
  fi
fi

declare -a ictool_candidates=()
if [[ -n "${ICTOOL:-}" ]]; then
  ictool_candidates+=("$ICTOOL")
fi
ictool_candidates+=(
  "$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
  "$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/icontool"
  "/Applications/Additional Tools/Graphics/Icon Composer.app/Contents/Executables/ictool"
  "/Applications/Additional Tools/Graphics/Icon Composer.app/Contents/Executables/icontool"
)

ICTOOL=""
for candidate in "${ictool_candidates[@]}"; do
  if [[ -x "$candidate" ]]; then
    ICTOOL="$candidate"
    break
  fi
done

if [[ -z "$ICTOOL" ]]; then
  echo "ictool/icontool not found. Install Additional Tools for Xcode (Icon Composer), set XCODE_APP, or set ICTOOL." >&2
  exit 1
fi

if [[ ! -d "$ICON_SRC" ]]; then
  echo "Missing Icon Composer bundle: $ICON_SRC" >&2
  exit 1
fi

TMP_DIR="$OUT_ROOT/tmp"
mkdir -p "$TMP_DIR" "$APPICONSET"
rm -f "$APPICONSET"/icon_*.png

MASTER_ART="$TMP_DIR/icon_art_824.png"
MASTER_1024="$TMP_DIR/icon_1024.png"

"$ICTOOL" "$ICON_SRC" \
  --export-preview macOS Default 824 824 1 -45 "$MASTER_ART"

sips --padToHeightWidth 1024 1024 "$MASTER_ART" --out "$MASTER_1024" >/dev/null

icon_specs=(
  "16:icon_16x16.png"
  "32:icon_16x16@2x.png"
  "32:icon_32x32.png"
  "64:icon_32x32@2x.png"
  "128:icon_128x128.png"
  "256:icon_128x128@2x.png"
  "256:icon_256x256.png"
  "512:icon_256x256@2x.png"
  "512:icon_512x512.png"
  "1024:icon_512x512@2x.png"
)
for spec in "${icon_specs[@]}"; do
  size="${spec%%:*}"
  filename="${spec#*:}"
  out="$APPICONSET/$filename"
  if [[ "$size" -eq 1024 ]]; then
    cp "$MASTER_1024" "$out"
  else
    sips -z "$size" "$size" "$MASTER_1024" --out "$out" >/dev/null
  fi
done

cat > "$APPICONSET/Contents.json" <<'EOF'
{
  "images" : [
    { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
EOF

echo "Updated $APPICONSET ($(ls -1 "$APPICONSET"/icon_*.png 2>/dev/null | wc -l | tr -d ' ') png files + Contents.json)"
