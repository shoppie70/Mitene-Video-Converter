#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-${1:-0.1.0}}"
OUTPUT_DIR="${OUTPUT_DIR:-${2:-$ROOT_DIR/dist}}"
PRODUCT="MiteneVideoConverter"
APP_NAME="2分にしてね.app"
APP_PATH="$OUTPUT_DIR/$APP_NAME"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 1
fi

rm -rf "$APP_PATH"
mkdir -p "$OUTPUT_DIR/$APP_NAME/Contents/MacOS" "$OUTPUT_DIR/$APP_NAME/Contents/Resources"

swift build --package-path "$ROOT_DIR" --configuration release --arch arm64 --product "$PRODUCT"
swift build --package-path "$ROOT_DIR" --configuration release --arch x86_64 --product "$PRODUCT"

ARM_BINARY="$ROOT_DIR/.build/arm64-apple-macosx/release/$PRODUCT"
INTEL_BINARY="$ROOT_DIR/.build/x86_64-apple-macosx/release/$PRODUCT"
UNIVERSAL_BINARY="$OUTPUT_DIR/$PRODUCT-universal"

[[ -x "$ARM_BINARY" ]] || { echo "Missing arm64 binary: $ARM_BINARY" >&2; exit 1; }
[[ -x "$INTEL_BINARY" ]] || { echo "Missing x86_64 binary: $INTEL_BINARY" >&2; exit 1; }

lipo -create "$ARM_BINARY" "$INTEL_BINARY" -output "$UNIVERSAL_BINARY"
cp "$UNIVERSAL_BINARY" "$APP_PATH/Contents/MacOS/$PRODUCT"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP_PATH/Contents/Info.plist"

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
rm -f "$UNIVERSAL_BINARY"

echo "Built: $APP_PATH"
echo "Architectures: $(lipo -archs "$APP_PATH/Contents/MacOS/$PRODUCT")"
