#!/bin/zsh
# 编译并（重新）启动「日历任务」，供 Agent 运行、验证、调试时调用。
# 用法：scripts/tasks-run.sh [--icon] [--size <宽>x<高>] [--shot <截图路径>]
#   --icon  换过图标后刷新系统图标缓存（更新修改时间 + lsregister）
#   --size  以指定窗口尺寸（pt）、边栏展开启动，只影响本次，用于检查窗口自适应
#   --shot  启动 8 秒后截全屏到指定路径（带 --size 冷启动时窗口出现较慢）
set -euo pipefail

cd "${0:A:h}/.."
APP="build/DerivedData/Build/Products/Debug/Tasks.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# SwiftUI 主窗口位置与尺寸的存储键
FRAME_KEY='NSWindow Frame SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<Tasks.ContentView, SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<Tasks.CalendarStore>>>, SwiftUI._FlexFrameLayout>-1-AppWindow-1'

refresh_icon=false
shot=""
size=""
while (( $# )); do
    case "$1" in
        --icon) refresh_icon=true ;;
        --shot) shot="$2"; shift ;;
        --size) size="$2"; shift ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
    shift
done

xcodegen generate --quiet
log=build/last-build.log
mkdir -p build
if ! xcodebuild -project Tasks.xcodeproj -scheme Tasks -configuration Debug \
    -derivedDataPath build/DerivedData build >"$log" 2>&1; then
    grep -E "error:" "$log" >&2 || tail -20 "$log" >&2
    echo "BUILD FAILED（完整日志：$log）" >&2
    exit 1
fi
echo "BUILD SUCCEEDED"

pkill -x Tasks 2>/dev/null && sleep 1 || true

if $refresh_icon; then
    touch "$APP" "$APP/Contents/Info.plist"
    "$LSREGISTER" -f "$APP"
fi

if [[ -n "$size" ]]; then
    # 通过启动参数覆盖窗口尺寸记录（并跳过窗口状态恢复），不改用户的偏好设置
    w=${size%x*}; h=${size#*x}
    open "$APP" --args -ApplePersistenceIgnoreState YES "-$FRAME_KEY" "200 200 $w $h 0 0 1728 1084 " \
        -sidebarVisible YES
else
    open "$APP"
fi

if [[ -n "$shot" ]]; then
    sleep 8
    screencapture -x "$shot"
    echo "截图：$shot"
fi
