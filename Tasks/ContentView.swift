import SwiftUI

struct ContentView: View {
    @Environment(CalendarStore.self) private var store
    /// 冷启动时还原上次的边栏显示状态
    @AppStorage("sidebarVisible") private var sidebarVisible = true

    var body: some View {
        @Bindable var store = store
        if store.hasAccess {
            NavigationSplitView(columnVisibility: columnVisibility) {
                SidebarView()
                    .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
            } detail: {
                if store.searchText.isEmpty {
                    DayListView()
                } else {
                    SearchResultsView()
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
            get: { sidebarVisible ? .all : .detailOnly },
            set: { sidebarVisible = $0 != .detailOnly }
        )
    }
}

/// 工具栏：‹ 今天 › + 日期选择器
private struct DateNavigationToolbar: ToolbarContent {
    @Environment(CalendarStore.self) private var store

    var body: some ToolbarContent {
        @Bindable var store = store
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button("前一天", systemImage: "chevron.left") { store.shiftDay(by: -1) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("今天") { store.goToday() }
                    .keyboardShortcut("t", modifiers: .command)
                    .disabled(store.isToday)
                Button("后一天", systemImage: "chevron.right") { store.shiftDay(by: 1) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            DatePicker("日期", selection: dayBinding, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
            Button("新增日程", systemImage: "plus") {
                store.searchText = ""
                store.isAddingEvent = true
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(store.calendarForNewEvents == nil)
        }
    }

    /// 选择器返回的时间统一归到当天 0 点
    private var dayBinding: Binding<Date> {
        Binding(
            get: { store.day },
            set: { store.day = Calendar.current.startOfDay(for: $0) }
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
