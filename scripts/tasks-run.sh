#!/bin/zsh
# 编译并（重新）启动「日历任务」，供 Agent 运行、验证、调试时调用。
# 用法：scripts/tasks-run.sh [--icon] [--size <宽>x<高>] [--shot <截图路径> [--window <标题子串>]] [-- <传给 App 的启动参数>]
#   --icon  换过图标后刷新系统图标缓存（更新修改时间 + lsregister）
#   --size  以指定窗口尺寸（pt）、边栏展开启动，只影响本次，用于检查窗口自适应
#   --shot  启动 8 秒后只截开发版自己的窗口到指定路径（带 --size 冷启动时窗口出现较慢）。
#           不截全屏：全屏会带进用户正在用的其他 App 的内容。默认截面积最大的普通窗口
#   --window 配合 --shot，改截标题包含该子串的窗口，如 --window 日程标记（设置窗口）
#   --      之后的参数原样传给 App，如 -- -debugFloatingSidebar YES
# 截窗口用 fsd2 skill 的 scripts/macos-window-shot.swift，路径可用环境变量 WINDOW_SHOT 覆盖
set -euo pipefail

cd "${0:A:h}/.."
# Agent 终端的 PATH 里可能没有 Homebrew，XcodeGen 装在这里
export PATH="/opt/homebrew/bin:$PATH"
APP="build/DerivedData/Build/Products/Debug/CalendarTasks-Dev.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# SwiftUI 主窗口位置与尺寸的存储键
FRAME_KEY='NSWindow Frame SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<Tasks.ContentView, SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<Tasks.CalendarStore>>>, SwiftUI._FlexFrameLayout>-1-AppWindow-1'

refresh_icon=false
shot=""
window=""
size=""
WINDOW_SHOT="${WINDOW_SHOT:-$HOME/.agents/skills/xinxin-fsd-v2/scripts/macos-window-shot.swift}"
app_args=()
while (( $# )); do
    case "$1" in
        --icon) refresh_icon=true ;;
        --shot) shot="$2"; shift ;;
        --window) window="$2"; shift ;;
        --size) size="$2"; shift ;;
        --) shift; app_args=("$@"); break ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
    shift
done

if [[ -n "$shot" && ! -f "$WINDOW_SHOT" ]]; then
    echo "找不到截窗口脚本：$WINDOW_SHOT（装好 fsd2 skill，或用 WINDOW_SHOT 指定路径）" >&2
    exit 2
fi

xcodegen generate --quiet
log=build/last-build.log
mkdir -p build/tmp
# 临时目录放在工程内：环境里的 TMPDIR 可能指向不存在或沙箱外的目录，swiftc 会因此失败
export TMPDIR="$PWD/build/tmp"
if ! xcodebuild -project Tasks.xcodeproj -scheme Tasks -configuration Debug \
    -derivedDataPath build/DerivedData \
    OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox' build >"$log" 2>&1; then
    # -disable-sandbox：在 Agent 的沙箱里编译时，宏插件不能再套一层 sandbox-exec，否则 @Observable 等宏展开失败
    grep -E "error:" "$log" >&2 || tail -20 "$log" >&2
    echo "BUILD FAILED（完整日志：$log）" >&2
    exit 1
fi
echo "BUILD SUCCEEDED"

# 只结束本工程编出的开发版，不影响已安装的正式版
pkill -f "$PWD/$APP/Contents/MacOS/" 2>/dev/null && sleep 1 || true

if $refresh_icon; then
    touch "$APP" "$APP/Contents/Info.plist"
    "$LSREGISTER" -f "$APP"
fi

if [[ -n "$size" ]]; then
    # 通过启动参数覆盖窗口尺寸记录（并跳过窗口状态恢复），不改用户的偏好设置
    w=${size%x*}; h=${size#*x}
    open "$APP" --args -ApplePersistenceIgnoreState YES "-$FRAME_KEY" "200 200 $w $h 0 0 1728 1084 " \
        -sidebarVisible YES "${app_args[@]}"
elif (( ${#app_args} )); then
    open "$APP" --args "${app_args[@]}"
else
    open "$APP"
fi

if [[ -n "$shot" ]]; then
    sleep 8
    # 按进程号截：别的分支根也可能在跑同名的开发版
    pid=$(pgrep -f "$PWD/$APP/Contents/MacOS/" | head -1)
    [[ -n "$pid" ]] || { echo "开发版没有在运行，无法截图" >&2; exit 1; }
    # TMPDIR 已指向工程内的 build/tmp，swift 解释执行要写临时文件
    swift "$WINDOW_SHOT" "$pid" "$shot" ${window:+"$window"}
fi
