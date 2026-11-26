日历任务（CalendarTasks）是一个 macOS 原生 App，参照系统「提醒事项」的界面，按天浏览和编辑系统日历中的日程。标题开头的 emoji 用来标记状态与优先级，已完成的日程可以隐藏，适合把日历日程当作每天的待办来用。

数据直接读写系统日历（EventKit），与系统日历、iPhone、桌面小组件保持同一份数据。

# 1、功能

- 左边栏：「今天」「全部日历」卡片；可保存的「日历组合」；按账户分区、可多选的日历列表，账户可展开收起。
- 当日列表：大标题显示日期与条数，点标题或 ⌘J 弹出月历选日期；「全天」与「日程」两个可折叠分组，按状态 emoji 和时间排序。
- 标题 emoji：开头识别状态（默认 ⬜️✅❎）与优先级（默认 ❗️‼️）；点状态弹出气泡切换。全天日程标 ✅ 时改为当前时间的非全天日程。
- 隐藏已完成：「隐藏的状态」（默认 ✅❎）的日程默认不显示，标题下方可切换显示。
- 新增：⌘N 或点列表空白处，在末尾直接输入标题，默认建为全天日程。
- 编辑：双击日程打开编辑面板，可拖出成独立窗口；支持标题、所属日历、全天与起止时间、重复规则、提醒、备注、URL。
- 删除与撤销：Delete 或右键删除，⌘Z 撤销；重复日程会询问「仅此次 / 将来所有」。
- 搜索：在已勾选日历中，当日前后各 1 年内匹配标题、地点、备注。
- 快捷键：⌘← 前一天、⌘→ 后一天、⌘T 今天、⌘J 选日期，编辑文字时不触发。
- 窗口自适应：窗口窄于 500pt 时自动收起边栏，点边栏按钮时边栏浮在列表上方。
- 设置（⌘,）：仿系统设置，左栏一级菜单（日程标记、动画、关于），右侧详情。「日程标记」设状态、优先级、隐藏的状态的 emoji 序列，「动画」设界面动画时长，「关于」显示版本与本机信息，并有「问题反馈」入口。
- 崩溃与卡顿记录：用 [KSCrash](https://github.com/kstenerud/KSCrash) 记录崩溃与 1 秒以上的主线程卡顿，连同系统崩溃报告保存在 `~/.config/CalendarTasks/crashes/`。「设置 › 关于 › 问题反馈」用默认邮件 App 写信给作者，自动附上这些记录的压缩包；发现新的崩溃时也会提示，可直接点「发给作者」。邮件发出后点「已发送」，附带的记录移到 `crashes/sent/<日期>/`，之后的反馈不再附带，30 天后自动删除；记录页可右键或「删除全部记录…」移到废纸篓。
- 本地配置文件：上述设置、日历组合与勾选的日历保存在 `~/.config/CalendarTasks/config.json`（开发版为 `config-dev.json`），卸载重装或换机后放回即可复用；换机后日历 ID 对不上时按「账户 + 日历名」重新匹配。手工修改后重启 App 生效，格式有误时 App 不读也不覆盖它。

`#标签` 写在标题里时，只在显示上移到副标题行，日历数据不改。

# 2、环境要求

- macOS 26 Tahoe 及以上
- Xcode 26（Swift 6）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`

# 3、编译与运行

工程文件由 `project.yml` 生成，`Tasks.xcodeproj/` 不入库：

```sh
xcodegen generate
open Tasks.xcodeproj
```

`project.yml` 里配置的是作者本人的签名证书（`DEVELOPMENT_TEAM`、`CODE_SIGN_IDENTITY`），在别的机器上编译前改成自己的。建议用固定证书签名：ad-hoc 签名每次编译都会变，系统会把 App 当成新应用，日历授权随之失效。

命令行编译并启动：

```sh
scripts/tasks-run.sh                      # 编译、结束旧进程、启动
scripts/tasks-run.sh --size 900x700       # 指定窗口尺寸启动
scripts/tasks-run.sh --shot build/a.png   # 启动后截屏
scripts/tasks-run.sh -- -debugBench resize # 传入 Debug 启动参数
```

首次启动时按提示授予日历「完全访问」权限。App 开启了 App Sandbox，只申请日历权限，另外只放开 `~/.config/CalendarTasks/` 的读写（存配置文件与崩溃、卡顿记录）和 `~/Library/Logs/DiagnosticReports/` 的只读（读系统崩溃报告）。

Debug 启动参数（验证用）：`-debugCrash YES` 3 秒后崩溃，`-debugHang <秒>` 3 秒后让主线程卡住，`-debugFeedback YES` 3 秒后打开问题反馈邮件，`-debugMarkSent YES` 3 秒后把未发送的记录标为已发送，`-debugSettingsPane markers|animation|about|status|records` 启动后打开设置的对应页。

# 4、目录结构

- `Tasks/CalendarStore.swift`：EventKit 封装与全局状态；`CalendarStore+ListOrder.swift`：排序与隐藏规则。
- `Tasks/ContentView.swift`：分栏、浮动边栏、日期快捷键；`SidebarView.swift`：边栏；`DayListView.swift`：当日列表。
- `Tasks/EventEditor.swift`、`EventEditorParts.swift`、`RepeatDraft.swift`、`AlarmChoice.swift`：编辑面板。
- `Tasks/GrowingTextView.swift`、`DetachablePopover.swift`：自适应高度输入框、可拖出的浮层。
- `Tasks/EmojiMarkers.swift`：状态、优先级与 `#标签` 解析。
- `Tasks/ConfigFile.swift`：本地配置文件的读写。
- `Tasks/SettingsView.swift`、`SettingsPanes.swift`：设置窗口与各页。
- `Tasks/CrashRecorder.swift`、`Feedback.swift`：崩溃与卡顿记录、问题反馈邮件。
- `Tasks/DebugBench.swift`：Debug 版的性能与动画测量工具。
- `References/`：设计参考截图。
- `scripts/tasks-run.sh`：编译运行脚本。
