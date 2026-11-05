#!/bin/zsh
# 编译正式版（通用二进制）、注入版本元信息、ad-hoc 重签并生成 .dmg。本地与 CI 共用。
# 做法说明见 ifsd skill references/macos/release.md。
# 用法：
#   CHANNEL=stable MARKETING_VERSION=1.0.0 BUILD_NUMBER=1 ./scripts/package-dmg.sh
#   CHANNEL=beta ./scripts/package-dmg.sh
# 环境变量：
#   CHANNEL           stable | beta（默认 stable）
#   MARKETING_VERSION 版本号（为空则用 project.yml 默认值）
#   BUILD_NUMBER      构建号（默认 1）
#   LABEL             产物标签（可选；CI 传入以保证与 Release tag 一致）
# 产物：.build/dist/<DMG 前缀>-<标签>.dmg 及其 .sha256
#   正式版标签 v<版本>，测试版标签 v<版本>-beta-<短哈希>-<时间戳>
set -euo pipefail

# ---- 项目配置 ----
PROJECT="Tasks.xcodeproj"
SCHEME="Tasks"
APP_NAME="Tasks"                     # Release 产物 .app 的名字（PRODUCT_NAME），也作 dmg 卷名
DMG_PREFIX="CalendarTasks"
APP_ENTITLEMENTS="Tasks/Tasks.entitlements"  # 主 App entitlements（改 Info.plist 重签时带上，保留沙箱与日历权限）
BG_2X="Resources/dmg-bg@2x.png"      # dmg 背景 @2x 图，不存在则不设背景
INFO_PREFIX="App"                    # 注入 Info.plist 的键前缀：<前缀>BuildChannel 等
# ------------------

cd "${0:A:h}/.."
ROOT="$PWD"
CHANNEL="${CHANNEL:-stable}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DERIVED_DATA="$ROOT/.build/DerivedData"
DIST="$ROOT/.build/dist"

# xcode-select 指向 CommandLineTools 时，探测 Xcode.app，不改全局配置
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for xc in /Applications/Xcode*.app(N); do
    export DEVELOPER_DIR="$xc/Contents/Developer"
    break
  done
fi

GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
echo "==> 渠道 $CHANNEL / 版本 ${MARKETING_VERSION:-<project.yml 默认>} / 构建号 $BUILD_NUMBER / commit $GIT_SHA"

xcodegen generate

# ad-hoc 签名；不加 CODE_SIGNING_ALLOWED=NO，让编译期为 App 签名并带上 entitlements
BUILD_SETTINGS=(
  ARCHS="arm64 x86_64"
  ONLY_ACTIVE_ARCH=NO
  CODE_SIGN_IDENTITY="-"
  CODE_SIGN_STYLE=Manual
  CODE_SIGNING_REQUIRED=NO
  DEVELOPMENT_TEAM=""
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
)
[[ -n "$MARKETING_VERSION" ]] && BUILD_SETTINGS+=(MARKETING_VERSION="$MARKETING_VERSION")

rm -rf "$DERIVED_DATA/Build/Products/Release"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED_DATA" "${BUILD_SETTINGS[@]}" build

APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
PLIST="$APP/Contents/Info.plist"

# 注入渠道与构建元信息，供 App 内显示版本
plutil -replace "${INFO_PREFIX}BuildChannel" -string "$CHANNEL" "$PLIST"
plutil -replace "${INFO_PREFIX}GitCommit" -string "$GIT_SHA" "$PLIST"
plutil -replace "${INFO_PREFIX}BuildTimestamp" -string "$TIMESTAMP" "$PLIST"

# 改了 Info.plist 要重签：带上 App entitlements，保留 app-sandbox 与日历权限；禁止 --deep
codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$ROOT/$APP_ENTITLEMENTS" "$APP"
codesign --verify --strict "$APP"

SHORT_VER="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"
if [[ -z "${LABEL:-}" ]]; then
  if [[ "$CHANNEL" == "beta" ]]; then
    LABEL="v${SHORT_VER}-beta-${GIT_SHA}-${TIMESTAMP}"
  else
    LABEL="v${SHORT_VER}"
  fi
fi

# 暂存：App + /Applications 软链 + 卷图标 + HiDPI 背景
STAGING="$DIST/staging"
rm -rf "$STAGING" && mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] && cp "$APP/Contents/Resources/AppIcon.icns" "$STAGING/.VolumeIcon.icns"

HAS_BG=0
if [[ -f "$ROOT/$BG_2X" ]]; then
  W2="$(sips -g pixelWidth "$ROOT/$BG_2X" | awk '/pixelWidth/{print $2}')"
  H2="$(sips -g pixelHeight "$ROOT/$BG_2X" | awk '/pixelHeight/{print $2}')"
  BG_W=$(( W2 / 2 )); BG_H=$(( H2 / 2 ))
  mkdir -p "$STAGING/.background"
  sips -z "$BG_H" "$BG_W" "$ROOT/$BG_2X" --out "$DIST/bg_1x.png" >/dev/null
  tiffutil -cathidpicheck "$DIST/bg_1x.png" "$ROOT/$BG_2X" -out "$STAGING/.background/bg.tiff" >/dev/null
  rm -f "$DIST/bg_1x.png"
  HAS_BG=1
fi

# 先做可读写 dmg，挂载后设卷图标与窗口布局，再转压缩只读
DMG="$DIST/${DMG_PREFIX}-${LABEL}.dmg"
RW_DMG="$DIST/rw-${LABEL}.dmg"
rm -f "$DMG" "$RW_DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$RW_DMG"
MOUNT_DIR="/Volumes/$APP_NAME"
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -noverify -noautoopen

[[ -f "$MOUNT_DIR/.VolumeIcon.icns" ]] && { xcrun SetFile -a C "$MOUNT_DIR" 2>/dev/null || echo "警告: 设置卷图标失败"; }

# 窗口布局依赖 GUI 会话，失败不中断；图标位置按背景图调整百分比
if (( HAS_BG )); then
  osascript <<EOF 2>/dev/null || echo "警告: Finder 窗口布局设置失败"
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, $(( 100 + BG_W )), $(( 100 + BG_H ))}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:bg.tiff"
    set position of item "$APP_NAME.app" of container window to {$(( BG_W * 25 / 100 )), $(( BG_H * 50 / 100 ))}
    set position of item "Applications" of container window to {$(( BG_W * 75 / 100 )), $(( BG_H * 50 / 100 ))}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
fi

sync
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG"
rm -f "$RW_DMG"
rm -rf "$STAGING"
(cd "$DIST" && shasum -a 256 "${DMG:t}" > "${DMG:t}.sha256")

echo "==> 打包完成: $DMG"
