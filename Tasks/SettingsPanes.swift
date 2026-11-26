import SwiftUI

// MARK: - 通用部件

/// 系统设置样式的图标：彩色圆角方块里放白色符号
struct SettingsIcon: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

struct SettingsSidebarRow: View {
    let pane: SettingsPane
    var trailing: String?

    var body: some View {
        Label {
            HStack {
                Text(pane.title)
                if let trailing {
                    Spacer()
                    Text(trailing)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        } icon: {
            SettingsIcon(systemImage: pane.systemImage, color: pane.color)
        }
        .tag(pane)
    }
}

/// 详情页顶部的说明卡片：左侧图标，右侧标题与说明（同系统设置「辅助功能」页）
struct SettingsHeaderCard: View {
    let systemImage: String
    let color: Color
    let title: String
    let summary: String

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                SettingsIcon(systemImage: systemImage, color: color, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(summary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// 进入子页面的一行：图标、标题、右侧取值与 ›
struct SettingsNavigationRow: View {
    var systemImage: String?
    var color: Color = .gray
    let title: String
    var value: String?
    let route: SettingsRoute
    @Environment(\.settingsNavigate) private var navigate

    var body: some View {
        Button { navigate(route) } label: {
            HStack(spacing: 10) {
                if let systemImage {
                    SettingsIcon(systemImage: systemImage, color: color)
                }
                Text(title)
                Spacer()
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// 详情页底部靠右的一排按钮（放在分组外，同系统设置）
struct SettingsFooterButtons<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Spacer()
            content
        }
        .padding(.top, 8)
    }
}

// MARK: - 日程标记

/// 日程标题开头的三种 emoji 标记
enum MarkerKind {
    case status, priority, hidden

    var title: String {
        switch self {
        case .status: "状态"
        case .priority: "优先级"
        case .hidden: "隐藏的状态"
        }
    }

    var systemImage: String {
        switch self {
        case .status: "checkmark"
        case .priority: "exclamationmark"
        case .hidden: "eye.slash.fill"
        }
    }

    var color: Color {
        switch self {
        case .status: .green
        case .priority: .red
        case .hidden: .gray
        }
    }

    var summary: String {
        switch self {
        case .status: "日程标题开头的状态 emoji，如「✅写周报」。点击列表里的状态弹出可选项，点选后切换；无状态时显示 \(EmojiMarkers.placeholder)。"
        case .priority: "写在状态之后的优先级 emoji，如「✅‼️写周报」。"
        case .hidden: "表示日程已结束的状态。列表默认不显示这些日程，可在日期标题下方点「显示」临时查看。"
        }
    }

    var key: String {
        switch self {
        case .status: EmojiMarkers.statusKey
        case .priority: EmojiMarkers.priorityKey
        case .hidden: CalendarStore.hiddenStatusKey
        }
    }

    var fallback: String {
        switch self {
        case .status: EmojiMarkers.defaultStatuses
        case .priority: EmojiMarkers.defaultPriorities
        case .hidden: CalendarStore.defaultHiddenStatuses
        }
    }

    /// 当前序列，用于列表右侧显示
    var sequence: String {
        let text = UserDefaults.standard.string(forKey: key) ?? fallback
        return EmojiMarkers.items(text, fallback: fallback).joined(separator: " ")
    }
}

/// 设置 › 日程标记
struct MarkersPane: View {
    // 读一下，子页面改完返回时右侧的序列跟着刷新
    @AppStorage(EmojiMarkers.statusKey) private var statusText = EmojiMarkers.defaultStatuses
    @AppStorage(EmojiMarkers.priorityKey) private var priorityText = EmojiMarkers.defaultPriorities
    @AppStorage(CalendarStore.hiddenStatusKey) private var hiddenText = CalendarStore.defaultHiddenStatuses

    var body: some View {
        Form {
            SettingsHeaderCard(systemImage: SettingsPane.markers.systemImage, color: SettingsPane.markers.color,
                               title: SettingsPane.markers.title,
                               summary: "用日程标题开头的 emoji 标记状态与优先级，先状态、后优先级，如「✅‼️写周报」。日历数据里保存的就是这些 emoji。")
            Section {
                ForEach([MarkerKind.status, .priority, .hidden], id: \.self) { kind in
                    SettingsNavigationRow(systemImage: kind.systemImage, color: kind.color, title: kind.title,
                                          value: kind.sequence, route: route(of: kind))
                }
            } header: {
                Text("标记")
            } footer: {
                SettingsFooterButtons {
                    Button("恢复默认") {
                        statusText = EmojiMarkers.defaultStatuses
                        priorityText = EmojiMarkers.defaultPriorities
                        hiddenText = CalendarStore.defaultHiddenStatuses
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func route(of kind: MarkerKind) -> SettingsRoute {
        switch kind {
        case .status: .status
        case .priority: .priority
        case .hidden: .hidden
        }
    }
}

/// 日程标记 › 状态 / 优先级 / 隐藏的状态
struct MarkerPage: View {
    let kind: MarkerKind
    @AppStorage private var text: String

    init(kind: MarkerKind) {
        self.kind = kind
        _text = AppStorage(wrappedValue: kind.fallback, kind.key)
    }

    var body: some View {
        Form {
            SettingsHeaderCard(systemImage: kind.systemImage, color: kind.color, title: kind.title, summary: kind.summary)
            Section {
                TextField("标记", text: $text, prompt: Text(kind.fallback))
                LabeledContent("序列", value: EmojiMarkers.items(text, fallback: kind.fallback).joined(separator: " → "))
            } footer: {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("按顺序输入 emoji，点击状态时按这个顺序切换。留空时使用默认值。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("恢复默认") { text = kind.fallback }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 动画

/// 设置 › 动画：界面过渡时长
struct AnimationPane: View {
    @AppStorage(Animation.durationKey) private var animationDuration = Animation.defaultDuration

    var body: some View {
        Form {
            SettingsHeaderCard(systemImage: SettingsPane.animation.systemImage, color: SettingsPane.animation.color,
                               title: SettingsPane.animation.title,
                               summary: "分组折叠、新增删除、浮动边栏等界面过渡使用无回弹的平滑弹簧曲线（与 iOS 页面 push 同类）。边栏两栏模式的展开收起、浮层弹出由系统控制，不受此设置影响。")
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
                SettingsFooterButtons {
                    Button("恢复默认") { animationDuration = Animation.defaultDuration }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - 关于

/// 设置 › 关于：仿系统设置「关于本机」，含问题反馈入口
struct AboutPane: View {
    @State private var recordCount = 0
    private let pending = Feedback.pending

    var body: some View {
        Form {
            Section {
                LabeledContent("版本", value: AppInfo.version)
                LabeledContent("构建号", value: AppInfo.build)
            } header: {
                // 同「关于本机」：图标与名称直接放在窗口底色上，不套卡片
                VStack(spacing: 4) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text(AppInfo.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("版本 \(AppInfo.version)（\(AppInfo.build)）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
            }
            // 反馈放在版本之后，不用滚动就能看到
            Section {
                LabeledContent("问题反馈") {
                    Button("写邮件…") { Feedback.compose() }
                }
                if !pending.files.isEmpty {
                    LabeledContent {
                        HStack {
                            Button("没发") { pending.discard() }
                            Button("已发送") { pending.confirmSent() }
                        }
                    } label: {
                        Text("刚才的邮件发出了吗？")
                        Text("点「已发送」后，附带的 \(pending.files.count) 份记录下次不再附带")
                    }
                }
                SettingsNavigationRow(title: "崩溃与卡顿记录", value: recordCount == 0 ? "无新记录" : "\(recordCount) 份未发送", route: .records)
            } header: {
                Text("反馈")
            } footer: {
                Text("用默认邮件 App 写信到 \(Feedback.recipient)，自动附上未发送的崩溃与卡顿记录的压缩包。")
                    .foregroundStyle(.secondary)
            }
            Section("macOS") {
                LabeledContent(AppInfo.macOSName, value: "版本 \(AppInfo.macOSVersion)")
            }
            Section("本机") {
                LabeledContent("芯片", value: AppInfo.chip)
                LabeledContent("内存", value: AppInfo.memory)
                LabeledContent("机型", value: AppInfo.model)
            }
        }
        .formStyle(.grouped)
        .onChange(of: pending.revision, initial: true) { recordCount = CrashRecorder.files.count }
    }
}

/// 关于 › 崩溃与卡顿记录
struct CrashRecordsPage: View {
    @State private var unsent: [URL] = []
    @State private var sent: [URL] = []
    @State private var confirmingDeleteAll = false
    @State private var errorMessage: String?
    private let pending = Feedback.pending

    var body: some View {
        Form {
            SettingsHeaderCard(systemImage: "exclamationmark.triangle.fill", color: .orange, title: "崩溃与卡顿记录",
                               summary: "系统崩溃报告与 1 秒以上的卡顿记录，保存在 ~/.config/CalendarTasks/crashes/。「问题反馈」只附带未发送的记录；确认邮件已发送后，记录移到「已发送」，\(CrashRecorder.sentRetentionDays) 天后自动删除。")
            Section {
                if unsent.isEmpty {
                    Text("暂无记录")
                        .foregroundStyle(.secondary)
                }
                ForEach(unsent, id: \.self, content: row)
            } header: {
                Text("未发送")
            }
            if !sent.isEmpty {
                Section {
                    ForEach(sent, id: \.self, content: row)
                } header: {
                    Text("已发送")
                }
            }
            Section {
            } footer: {
                VStack(alignment: .trailing, spacing: 8) {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                    SettingsFooterButtons {
                        Button("在访达中显示") {
                            try? FileManager.default.createDirectory(at: CrashRecorder.directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(CrashRecorder.directory)
                        }
                        Button("删除全部记录…") { confirmingDeleteAll = true }
                            .disabled(unsent.isEmpty && sent.isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("删除全部 \(unsent.count + sent.count) 份记录？", isPresented: $confirmingDeleteAll) {
            Button("移到废纸篓", role: .destructive) { trash(unsent + sent) }
        } message: {
            Text("记录会移到废纸篓，可从废纸篓恢复。")
        }
        .onChange(of: pending.revision, initial: true) {
            unsent = CrashRecorder.files
            sent = CrashRecorder.sentFiles
        }
    }

    private func row(_ file: URL) -> some View {
        LabeledContent {
            Text(CrashRecorder.modificationDate(file).formatted(date: .abbreviated, time: .standard))
        } label: {
            Text(Self.kind(of: file))
            Text(file.lastPathComponent)
        }
        // Form 里 LabeledContent 的取值默认可选中，选中后右键出的是文本菜单；关掉，并让整行（含空白处）都响应右键
        .textSelection(.disabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .contextMenu {
            Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            Button("移到废纸篓", role: .destructive) { trash([file]) }
        }
    }

    private func trash(_ urls: [URL]) {
        do {
            try pending.trash(urls)
            errorMessage = nil
        } catch {
            errorMessage = "删除失败：" + error.localizedDescription
        }
    }

    private static func kind(of file: URL) -> String {
        let name = file.lastPathComponent.dropFirst(CrashRecorder.processName.count + 1)
        if file.pathExtension == "ips" { return "崩溃（系统报告）" }
        if name.hasPrefix("fatal-hang-") { return "卡死后退出" }
        if name.hasPrefix("hang-") { return "卡顿" }
        return "崩溃"
    }
}
