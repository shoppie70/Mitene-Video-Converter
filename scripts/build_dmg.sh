#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-${1:-0.1.0}}"
APP_PATH="${APP_PATH:-${2:-$ROOT_DIR/dist/2分にしてね.app}}"
OUTPUT_DIR="${OUTPUT_DIR:-${3:-$ROOT_DIR/dist}}"
PRODUCT_NAME="MiteneVideoConverter-v${VERSION}.dmg"
OUTPUT_PATH="$OUTPUT_DIR/$PRODUCT_NAME"

command -v dmgbuild >/dev/null || { echo "dmgbuild is required: python3 -m pip install dmgbuild" >&2; exit 1; }
[[ -d "$APP_PATH" ]] || { echo "Missing app bundle: $APP_PATH" >&2; exit 1; }
[[ -f "$ROOT_DIR/assets/dmg-background.png" ]] || { echo "Missing DMG background PNG" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_PATH"

dmgbuild \
  -s "$ROOT_DIR/scripts/dmgbuild_settings.py" \
  -D "root_dir=$ROOT_DIR" \
  -D "app_path=$APP_PATH" \
  -D "volume_name=2分にしてね - Mitene Video Converter" \
  "2分にしてね - Mitene Video Converter" \
  "$OUTPUT_PATH"

hdiutil verify "$OUTPUT_PATH"
echo "SHA-256: $(shasum -a 256 "$OUTPUT_PATH" | awk '{print $1}')"
echo "Built: $OUTPUT_PATH"
