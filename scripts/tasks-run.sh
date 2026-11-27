#!/bin/zsh
# 编译并（重新）启动「日历任务」开发版，供 Agent 运行、验证、调试时调用。
# 通用部分（编译、结束旧进程、启动、只截窗口）在 fsd2 skill 的 teams/independent/stacks/macos/macos-run.sh，
# 这里只补本工程的参数和 --size。路径可用环境变量 MACOS_RUN 覆盖。
# 用法：scripts/tasks-run.sh [--icon] [--size <宽>x<高>] [--shot <截图路径> [--window <标题子串>]] [-- <传给 App 的启动参数>]
#   --icon   换过图标后刷新系统图标缓存
#   --size   以指定窗口尺寸（pt）、边栏展开启动，只影响本次，用于检查窗口自适应
#   --shot   启动 8 秒后只截开发版自己的窗口（不截全屏，免得带进其他 App 的内容）
#   --window 配合 --shot，截标题包含该子串的窗口，如 --window 日程标记（设置窗口）
#   --       之后的参数原样传给 App，如 -- -debugFloatingSidebar YES
set -euo pipefail

cd "${0:A:h}/.."
MACOS_RUN="${MACOS_RUN:-$HOME/.agents/skills/xinxin-fsd-v2/teams/independent/stacks/macos/macos-run.sh}"
[[ -f "$MACOS_RUN" ]] || { echo "找不到 $MACOS_RUN（装好 fsd2 skill，或用 MACOS_RUN 指定路径）" >&2; exit 2; }
# SwiftUI 主窗口位置与尺寸的存储键
FRAME_KEY='NSWindow Frame SwiftUI.ModifiedContent<SwiftUI.ModifiedContent<Tasks.ContentView, SwiftUI._EnvironmentKeyWritingModifier<Swift.Optional<Tasks.CalendarStore>>>, SwiftUI._FlexFrameLayout>-1-AppWindow-1'

run_args=(--scheme Tasks --app CalendarTasks-Dev --project Tasks.xcodeproj)
size=""
app_args=()
while (( $# )); do
    case "$1" in
        --icon) run_args+=(--icon) ;;
        --shot) run_args+=(--shot "$2"); shift ;;
        --window) run_args+=(--window "$2"); shift ;;
        --size) size="$2"; shift ;;
        --) shift; app_args=("$@"); break ;;
        *) echo "未知参数：$1" >&2; exit 2 ;;
    esac
    shift
done

if [[ -n "$size" ]]; then
    # 通过启动参数覆盖窗口尺寸记录（并跳过窗口状态恢复），不改用户的偏好设置
    w=${size%x*}; h=${size#*x}
    app_args=(-ApplePersistenceIgnoreState YES "-$FRAME_KEY" "200 200 $w $h 0 0 1728 1084 " -sidebarVisible YES "${app_args[@]}")
fi

if (( ${#app_args} )); then
    exec bash "$MACOS_RUN" "${run_args[@]}" -- "${app_args[@]}"
else
    exec bash "$MACOS_RUN" "${run_args[@]}"
fi
