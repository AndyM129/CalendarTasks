#!/bin/zsh
# 编译并（重新）启动「日历任务」，供 Agent 运行、验证、调试时调用。
# 用法：scripts/tasks-run.sh [--icon] [--shot <截图路径>]
#   --icon  换过图标后刷新系统图标缓存（更新修改时间 + lsregister）
#   --shot  启动 3 秒后截全屏到指定路径
set -euo pipefail

cd "${0:A:h}/.."
APP="build/DerivedData/Build/Products/Debug/Tasks.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

refresh_icon=false
shot=""
while (( $# )); do
    case "$1" in
        --icon) refresh_icon=true ;;
        --shot) shot="$2"; shift ;;
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

open "$APP"

if [[ -n "$shot" ]]; then
    sleep 3
    screencapture -x "$shot"
    echo "截图：$shot"
fi
