#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PRODUCT_NAME="AudioRouterApp"
APP_NAME="Audio Router.app"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
DIST_DIR="$ROOT_DIR/.build/dist"
APP_DIR="$DIST_DIR/$APP_NAME"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
DMG_ROOT="$DIST_DIR/dmg-root"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")"
DMG_PATH="$DIST_DIR/AudioRouter-$VERSION-macos.dmg"

cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="$BIN_DIR/$PRODUCT_NAME"

if [[ ! -x "$BINARY_PATH" ]]; then
    echo "未找到可执行文件：$BINARY_PATH"
    exit 1
fi

rm -rf "$APP_DIR" "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$DMG_ROOT"

cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
cp "$BINARY_PATH" "$MACOS_DIR/$PRODUCT_NAME"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR"
fi

cp -R "$APP_DIR" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "Audio Router" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_ROOT"

echo "APP=$APP_DIR"
echo "DMG=$DMG_PATH"
