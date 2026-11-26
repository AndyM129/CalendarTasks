#!/bin/zsh
# 从 GitHub Release 下载 dmg 并安装到 /Applications，然后启动。
# 用 gh 命令行下载的文件不带隔离标记（com.apple.quarantine），首次打开不会弹「Apple 无法验证」。
# 用法：
#   scripts/install-release.sh            # 安装最新正式版
#   scripts/install-release.sh v0.3.0     # 安装指定版本（含测试版 tag）
# 依赖：已登录的 gh（gh auth login）
set -euo pipefail

REPO="AndyM129/CalendarTasks"
APP_NAME="CalendarTasks"
TAG="${1:-}"

cd "${0:A:h}/.."
WORK="$PWD/build/tmp/install-release"
rm -rf "$WORK" && mkdir -p "$WORK"

echo "==> 下载 ${TAG:-最新正式版}"
gh release download ${TAG:+"$TAG"} -R "$REPO" -p "${APP_NAME}-*.dmg" -p "${APP_NAME}-*.dmg.sha256" -D "$WORK"
(cd "$WORK" && shasum -a 256 -c ./*.sha256)

DMG="$(print -l "$WORK"/*.dmg | head -1)"
MOUNT="$WORK/mnt"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" >/dev/null
trap 'hdiutil detach "$MOUNT" >/dev/null 2>&1 || true' EXIT

# 正在运行的旧版先退出，再整体替换
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "==> 退出正在运行的 $APP_NAME"
  osascript -e "tell application \"$APP_NAME\" to quit" || true
  sleep 2
fi
rm -rf "/Applications/$APP_NAME.app"
ditto "$MOUNT/$APP_NAME.app" "/Applications/$APP_NAME.app"
# 兜底：万一带了隔离标记也去掉
xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "/Applications/$APP_NAME.app/Contents/Info.plist")"
echo "==> 已安装 $APP_NAME $VERSION"
open "/Applications/$APP_NAME.app"
