import SwiftUI

/// 设置（⌘,）：仿系统设置，左栏是一级菜单（可收起），右侧是详情，详情内可进入子页面
struct SettingsView: View {
    @State private var selection: SettingsPane? = .markers
    @State private var path: [SettingsRoute] = []

    init() {
        #if DEBUG
        // 验证用：启动参数 -debugSettingsPane markers|animation|about|records，启动后直接打开设置的这一页
        switch UserDefaults.standard.string(forKey: "debugSettingsPane") {
        case "animation": _selection = State(initialValue: .animation)
        case "about": _selection = State(initialValue: .about)
        case "records": _selection = State(initialValue: .about); _path = State(initialValue: [.records])
        default: break
        }
        #endif
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    ForEach([SettingsPane.markers, .animation]) { SettingsSidebarRow(pane: $0) }
                }
                Section {
                    SettingsSidebarRow(pane: .about, trailing: "v" + AppInfo.version)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    switch selection ?? .markers {
                    case .markers: MarkersPane()
                    case .animation: AnimationPane()
                    case .about: AboutPane()
                    }
                }
                .navigationDestination(for: SettingsRoute.self) { route in
                    switch route {
                    case .records: CrashRecordsPage()
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 640)
        // 换一级菜单时回到该菜单的首页
        .onChange(of: selection) { path = [] }
    }
}

/// 一级菜单
enum SettingsPane: Hashable, Identifiable {
    case markers, animation, about

    var id: Self { self }

    var title: String {
        switch self {
        case .markers: "日程标记"
        case .animation: "动画"
        case .about: "关于"
        }
    }

    var systemImage: String {
        switch self {
        case .markers: "tag.fill"
        case .animation: "wand.and.sparkles"
        case .about: "info"
        }
    }

    var color: Color {
        switch self {
        case .markers: .orange
        case .animation: .blue
        case .about: .gray
        }
    }
}

/// 详情页内可进入的子页面
enum SettingsRoute: Hashable {
    case records
}

#if DEBUG
/// 带 -debugSettingsPane 启动时，主窗口出现后打开设置窗口
struct DebugOpenSettings: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.task {
            guard UserDefaults.standard.string(forKey: "debugSettingsPane") != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            openSettings()
        }
    }
}
#endif

/// 系统设置样式的图标：彩色圆角方块里放白色符号
struct SettingsIcon: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    var trailing: String?

    var body: some View {
        HStack {
            Label {
                Text(pane.title)
            } icon: {
                SettingsIcon(systemImage: pane.systemImage, color: pane.color)
            }
            if let trailing {
                Spacer()
                Text(trailing)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .tag(pane)
    }
}

/// 详情页顶部的大图标、标题与说明（同系统设置「通用」页）
struct SettingsPaneHeader: View {
    let pane: SettingsPane
    let summary: String

    var body: some View {
        Section {
            VStack(spacing: 8) {
                SettingsIcon(systemImage: pane.systemImage, color: pane.color, size: 56)
                Text(pane.title)
                    .font(.title2.bold())
                Text(summary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }
}
