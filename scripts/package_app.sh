#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="AudioRouterApp.app"
BUILD_DIR="$ROOT_DIR/.build/debug"
APP_DIR="$BUILD_DIR/$APP_NAME"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
BINARY_PATH="$BUILD_DIR/AudioRouterApp"

cd "$ROOT_DIR"

if [[ ! -x "$BINARY_PATH" ]]; then
    echo "未找到可执行文件：$BINARY_PATH"
    echo "请先运行：swift build"
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BINARY_PATH" "$MACOS_DIR/AudioRouterApp"

echo "$APP_DIR"
