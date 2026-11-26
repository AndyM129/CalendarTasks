import SwiftUI

/// 设置（⌘,）：仿系统设置，左栏是一级菜单（可收起），右侧是详情；工具栏的 ‹ › 在浏览过的页面间后退、前进，详情内可进入子页面
struct SettingsView: View {
    static let windowID = "settings"

    @State private var history: [SettingsLocation] = [SettingsLocation(pane: .markers)]
    @State private var index = 0

    init() {
        #if DEBUG
        // 验证用：启动参数 -debugSettingsPane markers|animation|about|status|records，启动后直接打开设置的这一页
        let start: SettingsLocation? = switch UserDefaults.standard.string(forKey: "debugSettingsPane") {
        case "animation": SettingsLocation(pane: .animation)
        case "about": SettingsLocation(pane: .about)
        case "status": SettingsLocation(pane: .markers, route: .status)
        case "records": SettingsLocation(pane: .about, route: .records)
        default: nil
        }
        if let start { _history = State(initialValue: [start]) }
        #endif
    }

    private var location: SettingsLocation { history[index] }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { location.pane }, set: { if let pane = $0 { go(to: SettingsLocation(pane: pane)) } })) {
                Section {
                    ForEach([SettingsPane.markers, .animation]) { SettingsSidebarRow(pane: $0) }
                }
                Section {
                    SettingsSidebarRow(pane: .about, trailing: "v" + AppInfo.version)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            // 套一层 NavigationStack，标题与 ‹ › 才会放在详情栏的工具栏左侧（同系统设置）；不用它的 push，返回由自己的历史管理
            NavigationStack {
                detail
                    .navigationTitle(location.title)
                    .environment(\.settingsNavigate, SettingsNavigateAction { route in
                        go(to: SettingsLocation(pane: location.pane, route: route))
                    })
                    .toolbar {
                        ToolbarItemGroup(placement: .navigation) {
                            Button("后退", systemImage: "chevron.left") { index -= 1 }
                                .disabled(index == 0)
                            Button("前进", systemImage: "chevron.right") { index += 1 }
                                .disabled(index == history.count - 1)
                        }
                    }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    @ViewBuilder private var detail: some View {
        switch location.route {
        case .status: MarkerPage(kind: .status)
        case .priority: MarkerPage(kind: .priority)
        case .hidden: MarkerPage(kind: .hidden)
        case .records: CrashRecordsPage()
        case nil:
            switch location.pane {
            case .markers: MarkersPane()
            case .animation: AnimationPane()
            case .about: AboutPane()
            }
        }
    }

    /// 同浏览器：进入新页面时丢掉「前进」的记录
    private func go(to next: SettingsLocation) {
        guard next != location else { return }
        history = Array(history[...index]) + [next]
        index = history.count - 1
    }
}

/// 打开设置窗口的菜单项（⌘,）
struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("设置…") { openWindow(id: SettingsView.windowID) }
            .keyboardShortcut(",", modifiers: .command)
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
    case status, priority, hidden, records
}

struct SettingsLocation: Hashable {
    var pane: SettingsPane
    var route: SettingsRoute?

    var title: String {
        switch route {
        case .status: MarkerKind.status.title
        case .priority: MarkerKind.priority.title
        case .hidden: MarkerKind.hidden.title
        case .records: "崩溃与卡顿记录"
        case nil: pane.title
        }
    }
}

/// 详情页里进入子页面
struct SettingsNavigateAction {
    let handler: (SettingsRoute) -> Void
    func callAsFunction(_ route: SettingsRoute) { handler(route) }
}

extension EnvironmentValues {
    @Entry var settingsNavigate = SettingsNavigateAction { _ in }
}

#if DEBUG
/// 带 -debugSettingsPane 启动时，主窗口出现后打开设置窗口
struct DebugOpenSettings: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            guard UserDefaults.standard.string(forKey: "debugSettingsPane") != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            openWindow(id: SettingsView.windowID)
        }
    }
}
#endif
