import SwiftUI

struct ContentView: View {
    /// 窗口窄于此宽度时自动收起边栏，略大于两栏最小宽度之和（220 + 260），保证收起发生在窗口被两栏卡住之前
    private static let autoCollapseWidth: CGFloat = 500

    @Environment(CalendarStore.self) private var store
    /// 冷启动时还原上次的边栏显示状态（用户手动开关的结果，不受自动收起影响）
    @AppStorage("sidebarVisible") private var savedSidebarVisible = true
    /// 界面实际用的边栏状态。用 @State 承接再写回 AppStorage：直接改 AppStorage 时视图更新不在
    /// withAnimation 的事务里，边栏展开收起会没有动画
    @State private var sidebarVisible = UserDefaults.standard.object(forKey: "sidebarVisible") as? Bool ?? true
    /// 窗口变窄导致的临时收起；窗口变宽后恢复
    @State private var autoCollapsed = false
    /// 自动收起时点边栏按钮，边栏浮在列表上方，用于临时切换日历
    @State private var floatingSidebar = false
    @State private var keyMonitor: Any?

    var body: some View {
        @Bindable var store = store
        if store.hasAccess {
            NavigationSplitView(columnVisibility: columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
                    #if DEBUG
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxX } action: {
                        DebugBench.recordSidebar($0)
                    }
            // 验证用：启动参数 -debugPickDate YES，3 秒后打开日期选择浮层
            .task {
                guard UserDefaults.standard.bool(forKey: "debugPickDate") else { return }
                try? await Task.sleep(for: .seconds(3))
                store.isPickingDate = true
            }
            #endif
            } detail: {
                Group {
                    if store.searchText.isEmpty {
                        DayListView()
                            .transition(.opacity)
                    } else {
                        SearchResultsView()
                            .transition(.opacity)
                    }
                }
                .animation(.ui, value: store.searchText.isEmpty)
                .navigationSplitViewColumnWidth(min: 260, ideal: 640)
            }
            .overlay { floatingSidebarOverlay }
            #if DEBUG
            // 验证用：启动参数 -debugFloatingSidebar YES 直接打开浮动边栏
            .task {
                guard UserDefaults.standard.bool(forKey: "debugFloatingSidebar") else { return }
                // 冷启动时窗口出现较慢，等到进入自动收起状态再打开
                for _ in 0..<30 where !autoCollapsed {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if autoCollapsed { withAnimation(.ui) { floatingSidebar = true } }
            }
            // 验证用：启动参数 -debugBench sidebar，2 秒后收起边栏、再展开，记录边栏宽度变化过程
            .task {
                guard UserDefaults.standard.string(forKey: "debugBench") == "sidebar" else { return }
                try? await Task.sleep(for: .seconds(4))
                DebugBench.sidebarWidths.removeAll()
                columnVisibility.wrappedValue = .detailOnly
                try? await Task.sleep(for: .seconds(1))
                columnVisibility.wrappedValue = .all
                try? await Task.sleep(for: .seconds(1))
                DebugBench.writeSidebarReport()
            }
            #endif
            .onChange(of: sidebarVisible) { _, visible in savedSidebarVisible = visible }
            // 启动时也要取一次宽度（onGeometryChange 不报初始值）
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.width < Self.autoCollapseWidth, initial: true) { _, narrow in
                        withAnimation(.ui) {
                            autoCollapsed = narrow
                            // 窗口变宽后改回常规两栏，不再浮动
                            if !narrow { floatingSidebar = false }
                        }
                    }
                }
            }
            .searchable(text: $store.searchText, placement: .toolbar, prompt: "搜索")
            .toolbar(removing: .title)
            .toolbar { DateNavigationToolbar() }
            .onAppear {
                keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: handleDateShortcut)
            }
            .onDisappear {
                if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
                keyMonitor = nil
            }
        } else {
            AccessRequestView()
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarVisible && !autoCollapsed ? .all : .detailOnly },
            set: { visibility in
                let show = visibility != .detailOnly
                withAnimation(.ui) {
                    if autoCollapsed {
                        // 窄窗口下边栏按钮只开关浮动边栏，不改两栏布局和用户偏好
                        if show { floatingSidebar.toggle() }
                    } else {
                        sidebarVisible = show
                    }
                }
            }
        )
    }

    /// 浮动边栏：全窗口蒙层 + 左侧边栏，点蒙层或按 Esc 收起。
    /// 外层 ZStack 常驻，蒙层和边栏各自插入、移除，各自的过渡（渐变 / 左侧滑入滑出）才会生效
    private var floatingSidebarOverlay: some View {
        ZStack(alignment: .leading) {
            if floatingSidebar {
                Color.black.opacity(0.3)
                    .contentShape(Rectangle())
                    .onTapGesture { closeFloatingSidebar() }
                    .ignoresSafeArea()
                    .transition(.opacity)
                // 边栏留在工具栏下方，不挡红绿灯和工具栏按钮
                SidebarView()
                    .frame(width: 260)
                    .frame(maxHeight: .infinity)
                    .background(.regularMaterial)
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(radius: 12)
                    .padding(8)
                    .transition(.move(edge: .leading))
                    .onExitCommand { closeFloatingSidebar() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .allowsHitTesting(floatingSidebar)
    }

    private func closeFloatingSidebar() {
        withAnimation(.ui) { floatingSidebar = false }
    }

    /// 切换日期的快捷键 ⌘← / ⌘→ / ⌘T，以及 ⌘J 打开日期选择。正在编辑文字或在弹窗里时放行，
    /// 留给文本框做移到行首/行尾、选中等操作，避免误切日期
    private func handleDateShortcut(_ event: NSEvent) -> NSEvent? {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let window = event.window, window.sheetParent == nil,
              !(window.firstResponder is NSText) else { return event }
        switch event.keyCode {
        case 123: withAnimation(.ui) { store.shiftDay(by: -1) }
        case 124: withAnimation(.ui) { store.shiftDay(by: 1) }
        default:
            switch event.charactersIgnoringModifiers {
            case "t" where !store.isToday: withAnimation(.ui) { store.goToday() }
            case "j" where store.searchText.isEmpty: store.isPickingDate = true
            default: return event
            }
        }
        return nil
    }
}

/// 工具栏：‹ 今天 ›。选日期改为点列表大标题（见 DayHeader）
private struct DateNavigationToolbar: ToolbarContent {
    @Environment(CalendarStore.self) private var store

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button("前一天", systemImage: "chevron.left") { withAnimation(.ui) { store.shiftDay(by: -1) } }
                    .help("前一天（⌘←）")
                Button("今天") { withAnimation(.ui) { store.goToday() } }
                    .help("今天（⌘T）")
                    .disabled(store.isToday)
                Button("后一天", systemImage: "chevron.right") { withAnimation(.ui) { store.shiftDay(by: 1) } }
                    .help("后一天（⌘→）")
            }
        }
    }
}

private struct AccessRequestView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("需要访问日历", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text(store.authorization == .notDetermined
                 ? "日历任务需要读取和编辑你的日历日程。"
                 : "请在「系统设置 › 隐私与安全性 › 日历」中允许日历任务完全访问。")
        } actions: {
            if store.authorization == .notDetermined {
                Button("允许访问") { Task { await store.requestAccess() } }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("打开系统设置") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
