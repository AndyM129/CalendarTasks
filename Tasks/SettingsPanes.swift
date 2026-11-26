import SwiftUI

/// 设置 › 日程标记：状态、优先级、隐藏的状态
struct MarkersPane: View {
    @AppStorage(EmojiMarkers.statusKey) private var statusText = EmojiMarkers.defaultStatuses
    @AppStorage(EmojiMarkers.priorityKey) private var priorityText = EmojiMarkers.defaultPriorities
    @AppStorage(CalendarStore.hiddenStatusKey) private var hiddenText = CalendarStore.defaultHiddenStatuses

    var body: some View {
        Form {
            SettingsPaneHeader(pane: .markers, summary: "用日程标题开头的 emoji 标记状态与优先级。")
            Section {
                MarkerField(title: "状态", text: $statusText, fallback: EmojiMarkers.defaultStatuses)
                MarkerField(title: "优先级", text: $priorityText, fallback: EmojiMarkers.defaultPriorities)
                MarkerField(title: "隐藏的状态", text: $hiddenText, fallback: CalendarStore.defaultHiddenStatuses)
            } footer: {
                Text("识别日程标题开头的 emoji：先状态、后优先级，如「✅‼️写周报」。点击状态弹出可选项，点选后切换；无状态时显示 \(EmojiMarkers.placeholder)。「隐藏的状态」表示日程已结束，列表默认不显示，可在日期标题下方点「显示」临时查看。")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("恢复默认") {
                    statusText = EmojiMarkers.defaultStatuses
                    priorityText = EmojiMarkers.defaultPriorities
                    hiddenText = CalendarStore.defaultHiddenStatuses
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.markers.title)
    }
}

private struct MarkerField: View {
    let title: String
    @Binding var text: String
    let fallback: String

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 4) {
                TextField(title, text: $text, prompt: Text(fallback))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                Text("序列：" + EmojiMarkers.items(text, fallback: fallback).joined(separator: " → "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 设置 › 动画：界面过渡时长
struct AnimationPane: View {
    @AppStorage(Animation.durationKey) private var animationDuration = Animation.defaultDuration

    var body: some View {
        Form {
            SettingsPaneHeader(pane: .animation, summary: "调整分组折叠、新增删除、浮动边栏等界面过渡的快慢。")
            Section {
                LabeledContent("动画时长") {
                    HStack {
                        Slider(value: $animationDuration, in: 0.1...1.0, step: 0.05)
                            .frame(width: 180)
                        Text(String(format: "%.2f 秒", animationDuration))
                            .monospacedDigit()
                            .frame(width: 56, alignment: .trailing)
                    }
                }
            } footer: {
                Text("界面过渡使用无回弹的平滑弹簧曲线（与 iOS 页面 push 同类）。边栏两栏模式的展开收起、浮层弹出由系统控制，不受此设置影响。")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("恢复默认") { animationDuration = Animation.defaultDuration }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.animation.title)
    }
}

/// 设置 › 关于：仿系统设置「关于本机」，含问题反馈入口
struct AboutPane: View {
    @State private var recordCount = 0

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 112, height: 112)
                    Text(AppInfo.name)
                        .font(.largeTitle.bold())
                    Text("版本 \(AppInfo.version)")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            // 同「关于本机」：图标与名称直接放在窗口底色上，不套卡片
            .listRowBackground(Color.clear)
            Section {
                LabeledContent("版本", value: "\(AppInfo.version)（\(AppInfo.build)）")
                LabeledContent("macOS", value: AppInfo.macOSVersion)
                LabeledContent("芯片", value: AppInfo.chip)
                LabeledContent("机型", value: AppInfo.model)
            }
            Section("反馈") {
                LabeledContent {
                    Button("写邮件…") { Feedback.compose() }
                } label: {
                    Text("问题反馈")
                    Text("发送到 \(Feedback.recipient)，自动附上崩溃与卡顿记录")
                }
                NavigationLink(value: SettingsRoute.records) {
                    LabeledContent("崩溃与卡顿记录", value: recordCount == 0 ? "无" : "\(recordCount) 份")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsPane.about.title)
        .onAppear { recordCount = CrashRecorder.files.count }
    }
}

/// 关于 › 崩溃与卡顿记录
struct CrashRecordsPage: View {
    @State private var files: [URL] = []

    var body: some View {
        Form {
            Section {
                if files.isEmpty {
                    Text("暂无记录")
                        .foregroundStyle(.secondary)
                }
                ForEach(files, id: \.self) { file in
                    LabeledContent {
                        Text(CrashRecorder.modificationDate(file).formatted(date: .abbreviated, time: .standard))
                    } label: {
                        Text(Self.kind(of: file))
                        Text(file.lastPathComponent)
                    }
                }
            } footer: {
                Text("系统崩溃报告与卡顿记录保存在 ~/.config/CalendarTasks/crashes/，「问题反馈」时会打包附在邮件里。卡顿只记 1 秒以上的，最多保留最近 50 份。")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("在访达中显示") {
                    try? FileManager.default.createDirectory(at: CrashRecorder.directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(CrashRecorder.directory)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("崩溃与卡顿记录")
        .onAppear { files = CrashRecorder.files }
    }

    private static func kind(of file: URL) -> String {
        let name = file.lastPathComponent.dropFirst(CrashRecorder.processName.count + 1)
        if file.pathExtension == "ips" { return "崩溃（系统报告）" }
        if name.hasPrefix("fatal-hang-") { return "卡死后退出" }
        if name.hasPrefix("hang-") { return "卡顿" }
        return "崩溃"
    }
}
