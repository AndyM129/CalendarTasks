import SwiftUI

struct ContentView: View {
    /// 窗口窄于此宽度时自动收起边栏，略大于两栏最小宽度之和（220 + 260），保证收起发生在窗口被两栏卡住之前
    private static let autoCollapseWidth: CGFloat = 500

    @Environment(CalendarStore.self) private var store
    /// 冷启动时还原上次的边栏显示状态（用户手动开关的结果，不受自动收起影响）
    @AppStorage("sidebarVisible") private var sidebarVisible = true
    /// 窗口变窄导致的临时收起；窗口变宽后恢复
    @State private var autoCollapsed = false
    /// 自动收起时点边栏按钮，边栏浮在列表上方，用于临时切换日历
    @State private var floatingSidebar = false

    var body: some View {
        @Bindable var store = store
        if store.hasAccess {
            NavigationSplitView(columnVisibility: columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
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
                .animation(.snappy, value: store.searchText.isEmpty)
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
                if autoCollapsed { withAnimation(.snappy) { floatingSidebar = true } }
            }
            #endif
            // 启动时也要取一次宽度（onGeometryChange 不报初始值）
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size.width < Self.autoCollapseWidth, initial: true) { _, narrow in
                        withAnimation(.snappy) {
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
        } else {
            AccessRequestView()
        }
    }

    private var columnVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarVisible && !autoCollapsed ? .all : .detailOnly },
            set: { visibility in
                let show = visibility != .detailOnly
                withAnimation(.snappy) {
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

    /// 浮动边栏：全窗口蒙层 + 左侧边栏，点蒙层或按 Esc 收起
    @ViewBuilder private var floatingSidebarOverlay: some View {
        if floatingSidebar {
            ZStack(alignment: .leading) {
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
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            .onExitCommand { closeFloatingSidebar() }
        }
    }

    private func closeFloatingSidebar() {
        withAnimation(.snappy) { floatingSidebar = false }
    }
}

/// 工具栏：‹ 今天 › + 日期选择器
private struct DateNavigationToolbar: ToolbarContent {
    @Environment(CalendarStore.self) private var store
    @State private var pickingDate = false

    var body: some ToolbarContent {
        @Bindable var store = store
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button("前一天", systemImage: "chevron.left") { withAnimation(.snappy) { store.shiftDay(by: -1) } }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("今天") { withAnimation(.snappy) { store.goToday() } }
                    .keyboardShortcut("t", modifiers: .command)
                    .disabled(store.isToday)
                Button("后一天", systemImage: "chevron.right") { withAnimation(.snappy) { store.shiftDay(by: 1) } }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
        }
        // 日期文字无背景，点击弹出日历选择
        ToolbarItem(placement: .primaryAction) {
            Button {
                pickingDate.toggle()
            } label: {
                Text(store.day, format: .dateTime.year().month().day())
                    .monospacedDigit()
            }
            .buttonStyle(.plain)
            .help("选择日期")
            .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
                DatePicker("日期", selection: dayBinding, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.graphical)
                    .padding()
            }
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            Button("新增日程", systemImage: "plus") {
                store.searchText = ""
                withAnimation(.snappy) { store.isAddingEvent = true }
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(store.calendarForNewEvents == nil)
        }
    }

    /// 选择器返回的时间统一归到当天 0 点，选中后收起
    private var dayBinding: Binding<Date> {
        Binding(
            get: { store.day },
            set: { date in
                withAnimation(.snappy) { store.day = Calendar.current.startOfDay(for: date) }
                pickingDate = false
            }
        )
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
