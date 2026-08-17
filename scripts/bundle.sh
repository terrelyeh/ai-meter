#!/bin/bash
# 把 SwiftPM 產出的執行檔組成一個 .app bundle。
#
# 沒有 .xcodeproj 是刻意的：swift build 在 CLI 就跑得動，
# bundle 本身不過是一個 Info.plist 加一支執行檔。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-release}"
APP_NAME="AI Meter"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"

BIN="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)/AIMeter"
if [[ ! -x "$BIN" ]]; then
  echo "找不到執行檔：$BIN（先跑 swift build）" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/AIMeter"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Ad-hoc 簽章。沒有開發者憑證也能在本機跑起來，
# 而且簽過之後才不會每次 rebuild 都被系統當成新的 app 重問權限。
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
  || echo "警告：ad-hoc 簽章失敗，app 仍可執行" >&2

echo "$APP"
