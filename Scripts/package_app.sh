#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
FINAL_APP_DIR="$ROOT_DIR/dist/ImageCanvas.app"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/imagecanvas-package.XXXXXX")"
APP_DIR="$STAGING_ROOT/ImageCanvas.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_INFO_PLIST="$STAGING_ROOT/TestIcon-asset-info.plist"
BACKUP_APP_DIR="$ROOT_DIR/.build/package/ImageCanvas.previous.app"

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

xcrun actool "$ROOT_DIR/TestIcon.icon" \
  --compile "$RESOURCES_DIR" \
  --output-format human-readable-text \
  --notices \
  --warnings \
  --output-partial-info-plist "$ICON_INFO_PLIST" \
  --app-icon TestIcon \
  --enable-on-demand-resources NO \
  --development-region en \
  --target-device mac \
  --minimum-deployment-target 14.0 \
  --platform macosx \
  --bundle-identifier local.imagecanvas.app

plutil -insert CFBundleIconFile -string TestIcon "$CONTENTS_DIR/Info.plist"
plutil -insert CFBundleIconName -string TestIcon "$CONTENTS_DIR/Info.plist"

xattr -cr "$APP_DIR"
while IFS= read -r bundled_path; do
  xattr -d com.apple.FinderInfo "$bundled_path" 2>/dev/null || true
  xattr -d com.apple.provenance "$bundled_path" 2>/dev/null || true
  xattr -d 'com.apple.fileprovider.fpfs#P' "$bundled_path" 2>/dev/null || true
done < <(find "$APP_DIR" -print)
codesign --force --sign - "$MACOS_DIR/ImageCanvas"
codesign --force --deep --sign - "$APP_DIR"

mkdir -p "$ROOT_DIR/dist"
mkdir -p "$(dirname "$BACKUP_APP_DIR")"
rm -rf "$BACKUP_APP_DIR"
if [ -d "$FINAL_APP_DIR" ]; then
  mv "$FINAL_APP_DIR" "$BACKUP_APP_DIR"
fi

if ! mv "$APP_DIR" "$FINAL_APP_DIR"; then
  if [ -d "$BACKUP_APP_DIR" ]; then
    mv "$BACKUP_APP_DIR" "$FINAL_APP_DIR"
  fi
  exit 1
fi

rm -rf "$BACKUP_APP_DIR"
echo "$FINAL_APP_DIR"
