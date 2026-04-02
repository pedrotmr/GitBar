#!/usr/bin/env bash
# Regenerate Resources/Assets.xcassets/AppIcon.appiconset from Resources/AppIcon.icon
# (Icon Composer bundle). Requires Xcode with Icon Composer (ictool).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

ICON_SRC="${1:-$ROOT/Resources/AppIcon.icon}"
APPICONSET="$ROOT/Resources/Assets.xcassets/AppIcon.appiconset"
OUT_ROOT="$ROOT/build/icon-gen"
XCODE_APP="${XCODE_APP:-/Applications/Xcode.app}"

ICTOOL="$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICTOOL" ]]; then
  ICTOOL="$XCODE_APP/Contents/Applications/Icon Composer.app/Contents/Executables/icontool"
fi
if [[ ! -x "$ICTOOL" ]]; then
  echo "ictool/icontool not found. Install Xcode and Icon Composer, or set XCODE_APP." >&2
  exit 1
fi

if [[ ! -d "$ICON_SRC" ]]; then
  echo "Missing Icon Composer bundle: $ICON_SRC" >&2
  exit 1
fi

ICONSET_DIR="$OUT_ROOT/AppIcon.iconset"
TMP_DIR="$OUT_ROOT/tmp"
mkdir -p "$ICONSET_DIR" "$TMP_DIR" "$APPICONSET"

MASTER_ART="$TMP_DIR/icon_art_824.png"
MASTER_1024="$TMP_DIR/icon_1024.png"

"$ICTOOL" "$ICON_SRC" \
  --export-preview macOS Default 824 824 1 -45 "$MASTER_ART"

sips --padToHeightWidth 1024 1024 "$MASTER_ART" --out "$MASTER_1024" >/dev/null

sizes=(16 32 64 128 256 512 1024)
for sz in "${sizes[@]}"; do
  out="$ICONSET_DIR/icon_${sz}x${sz}.png"
  sips -z "$sz" "$sz" "$MASTER_1024" --out "$out" >/dev/null
  if [[ "$sz" -ne 1024 ]]; then
    dbl=$((sz * 2))
    out2="$ICONSET_DIR/icon_${sz}x${sz}@2x.png"
    sips -z "$dbl" "$dbl" "$MASTER_1024" --out "$out2" >/dev/null
  fi
done

cp "$MASTER_1024" "$ICONSET_DIR/icon_512x512@2x.png"

# Install into asset catalog (overwrite PNGs only)
cp "$ICONSET_DIR"/*.png "$APPICONSET/"
# Asset catalog only references the standard 10 slots; drop intermediate sizes from iconutil-style set.
rm -f "$APPICONSET/icon_64x64.png" "$APPICONSET/icon_64x64@2x.png" "$APPICONSET/icon_1024x1024.png"

echo "Updated $APPICONSET ($(ls -1 "$APPICONSET"/*.png 2>/dev/null | wc -l | tr -d ' ') png files)"
