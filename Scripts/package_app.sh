#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Support/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$ROOT_DIR/Support/Info.plist")"
ARCHIVE_NAME="ImageCanvas-${VERSION}-build${BUILD_NUMBER}.zip"
FINAL_ARCHIVE="$ROOT_DIR/dist/$ARCHIVE_NAME"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/imagecanvas-package.XXXXXX")"
APP_DIR="$STAGING_ROOT/ImageCanvas.app"
STAGING_ARCHIVE="$STAGING_ROOT/$ARCHIVE_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_INFO_PLIST="$STAGING_ROOT/ImageCanvas-asset-info.plist"
BACKUP_ARCHIVE="$ROOT_DIR/.build/package/$ARCHIVE_NAME.previous"

cleanup() {
  rm -rf "$STAGING_ROOT"
}
trap cleanup EXIT

cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/Support/Info.plist" "$CONTENTS_DIR/Info.plist"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"
cp "$ROOT_DIR/.build/$CONFIGURATION/ImageCanvas" "$MACOS_DIR/ImageCanvas"
chmod +x "$MACOS_DIR/ImageCanvas"
cp "$ROOT_DIR/Support/ImageCanvasUpdateHelper.sh" "$RESOURCES_DIR/ImageCanvasUpdateHelper.sh"
chmod +x "$RESOURCES_DIR/ImageCanvasUpdateHelper.sh"

xcrun actool "$ROOT_DIR/ImageCanvas.icon" --compile "$RESOURCES_DIR" --output-format human-readable-text --notices --warnings --output-partial-info-plist "$ICON_INFO_PLIST" --app-icon ImageCanvas --enable-on-demand-resources NO --development-region en --target-device mac --minimum-deployment-target 14.0 --platform macosx --bundle-identifier local.imagecanvas.app

plutil -insert CFBundleIconFile -string ImageCanvas "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIconName -string ImageCanvas "$CONTENTS_DIR/Info.plist"

xattr -cr "$APP_DIR"
while IFS= read -r bundled_path; do
  xattr -d com.apple.FinderInfo "$bundled_path" 2>/dev/null || true
  xattr -d com.apple.provenance "$bundled_path" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$bundled_path" 2>/dev/null || true
done < <(find "$APP_DIR" -print)
codesign --force --sign - "$MACOS_DIR/ImageCanvas"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

ditto -c -k --norsrc --noextattr --keepParent "$APP_DIR" "$STAGING_ARCHIVE"

mkdir -p "$ROOT_DIR/dist"
mkdir -p "$(dirname "$BACKUP_ARCHIVE")"
rm -f "$BACKUP_ARCHIVE"
if [ -f "$FINAL_ARCHIVE" ]; then
  mv "$FINAL_ARCHIVE" "$BACKUP_ARCHIVE"
fi

if ! mv "$STAGING_ARCHIVE" "$FINAL_ARCHIVE"; then
  if [ -f "$BACKUP_ARCHIVE" ]; then
    mv "$BACKUP_ARCHIVE" "$FINAL_ARCHIVE"
  fi
  exit 1
fi

rm -f "$BACKUP_ARCHIVE"
echo "$FINAL_ARCHIVE"
