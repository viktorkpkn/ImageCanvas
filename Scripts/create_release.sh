#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Support/Info.plist")"
APP_DIR="$ROOT_DIR/dist/ImageCanvas.app"
ASSET_DIR="$ROOT_DIR/release-assets"
ARCHIVE_PATH="$ASSET_DIR/ImageCanvas-${VERSION}-unsigned-macos.zip"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"
ARCHIVE_FILENAME="$(basename "$ARCHIVE_PATH")"
CHECKSUM_FILENAME="$(basename "$CHECKSUM_PATH")"

if [ -e "$ARCHIVE_PATH" ] || [ -e "$CHECKSUM_PATH" ]; then
  echo "Release asset already exists: $ARCHIVE_PATH" >&2
  echo "Choose a new version or remove the prior asset deliberately." >&2
  exit 1
fi

"$ROOT_DIR/Scripts/package_app.sh" "$CONFIGURATION"
codesign --verify --deep "$APP_DIR"

mkdir -p "$ASSET_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ARCHIVE_PATH"
pushd "$ASSET_DIR" > /dev/null
shasum -a 256 "$ARCHIVE_FILENAME" > "$CHECKSUM_FILENAME"
popd > /dev/null

printf 'Created %s\n' "$ARCHIVE_PATH"
printf 'Created %s\n' "$CHECKSUM_PATH"
