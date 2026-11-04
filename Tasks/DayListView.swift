import EventKit
import SwiftUI

/// 右侧：当日、所选日历中的日程。全天在前，定时按开始时间。
struct DayListView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var selection: EKEvent?
    @State private var pendingDelete: EKEvent?
    @AppStorage("allDayExpanded") private var allDayExpanded = true
    @AppStorage("timedExpanded") private var timedExpanded = true

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            Section {
                EmptyView()
            } header: {
                DayHeader()
            }
            if !store.allDayEvents.isEmpty {
                CollapsibleSection(title: "全天", count: store.allDayEvents.count, isExpanded: $allDayExpanded) {
                    ForEach(store.allDayEvents, id: \.self, content: row)
                }
            }
            if !store.timedEvents.isEmpty {
                CollapsibleSection(title: "日程", count: store.timedEvents.count, isExpanded: $timedExpanded) {
                    ForEach(store.timedEvents, id: \.self, content: row)
                }
            }
            Section {
                if store.isAddingEvent {
                    NewEventRow()
                }
                // 点列表末尾空白处新增
                Color.clear
                    .frame(height: 80)
                    .contentShape(Rectangle())
                    .onTapGesture { store.isAddingEvent = true }
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        // 换日期、新增、删除、改状态等都会触发重新加载，列表随之做过渡动画
        .animation(.snappy, value: store.revision)
        .animation(.snappy, value: store.isAddingEvent)
        .onDeleteCommand {
            if let selection, selection.calendar.allowsContentModifications { pendingDelete = selection }
        }
        .overlay {
            if store.events.isEmpty && !store.isAddingEvent {
                ContentUnavailableView(store.selectedCalendarIDs.isEmpty ? "未选择日历" : "无日程",
                                       systemImage: "calendar",
                                       description: Text(store.selectedCalendarIDs.isEmpty ? "" : "点空白处或按 ⌘N 新增"))
                    .allowsHitTesting(false)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil },
                                                              set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { event in
            if event.hasRecurrenceRules {
                Button("仅删除此次", role: .destructive) { delete(event, span: .thisEvent) }
                Button("删除将来所有", role: .destructive) { delete(event, span: .futureEvents) }
            } else {
                Button("删除", role: .destructive) { delete(event, span: .thisEvent) }
            }
        } message: { event in
            Text(event.hasRecurrenceRules
                 ? "可以用 ⌘Z 撤销：「仅此次」恢复为单次日程，「将来所有」从这次起按原规则重建。"
                 : "可以用 ⌘Z 撤销。")
        }
        .alert("无法保存日程", isPresented: Binding(get: { store.lastError != nil },
                                                set: { if !$0 { store.lastError = nil } })) {
            Button("好") {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    private func row(_ event: EKEvent) -> some View {
        EventRow(event: event, title: event.title ?? "", revision: store.revision) {
            pendingDelete = event
        }
    }

    private var deleteTitle: String {
        "删除日程「\(pendingDelete?.title ?? "")」？"
    }

    private func delete(_ event: EKEvent, span: EKSpan) {
        store.delete(event, span: span, undoManager: undoManager)
        selection = nil
    }
}

/// 列表末尾的输入行：回车新增，Esc 或失焦取消
private struct NewEventRow: View {
    @Environment(CalendarStore.self) private var store
    @State private var title = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(EmojiMarkers.placeholder)
                .font(.title3)
                .opacity(0.3)
                .frame(width: 24, height: 24)
            TextField("新日程", text: $title)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(submit)
                .onExitCommand {
                    title = ""
                    store.isAddingEvent = false
                }
        }
        .padding(.vertical, 4)
        .onAppear { focused = true }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { submit() }
        }
    }

    private func submit() {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { store.createEvent(title: text) }
        title = ""
        store.isAddingEvent = false
    }
}

/// 仿提醒事项的分组：粗体标题 + 右侧折叠箭头，折叠时显示条数
private struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content

    var body: some View {
        Section {
            if isExpanded { content }
        } header: {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    if !isExpanded {
                        Text(count, format: .number)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DayHeader: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                // 窗口窄时先缩小字号，再省略
                Text(store.day, format: .dateTime.month().day().weekday(.wide))
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Spacer(minLength: 8)
                Text(store.events.count, format: .number)
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
            }
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.vertical, 8)
    }

    private var subtitle: String {
        let year = store.day.formatted(.dateTime.year())
        return store.isToday ? "\(year) · 今天" : year
    }
}

struct EventRow: View {
    @Environment(CalendarStore.self) private var store
    @AppStorage(EmojiMarkers.statusKey) private var statusText = EmojiMarkers.defaultStatuses
    @AppStorage(EmojiMarkers.priorityKey) private var priorityText = EmojiMarkers.defaultPriorities
    /// 重复日程待确认范围的新标题
    @State private var pendingTitle: String?
    @State private var hovering = false
    @State private var editing = false

    let event: EKEvent
    let title: String
    /// 每次重新加载递增，确保日程其他字段改动后行能刷新
    let revision: Int
    let onDelete: () -> Void

    var body: some View {
        let marked = MarkedTitle(title, statuses: statuses, priorities: priorities)
        let editable = event.calendar.allowsContentModifications
        HStack(spacing: 10) {
            Button {
                setStatus(nextStatus(after: marked.status), in: marked)
            } label: {
                Text(marked.status ?? EmojiMarkers.placeholder)
                    .font(.title3)
                    .opacity(marked.status == nil ? 0.5 : 1)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .help(editable ? "单击切换状态，右键选择" : "该日历不可编辑")
            .contextMenu {
                ForEach(statuses, id: \.self) { status in
                    Button(status) { setStatus(status, in: marked) }
                }
                if marked.status != nil {
                    Divider()
                    Button("清除状态") { setStatus(nil, in: marked) }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text((marked.priority ?? "") + (marked.text.isEmpty ? "新日程" : marked.text))
                Text(timeText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if editable && (hovering || editing) {
                Button("编辑", systemImage: "info.circle") { editing = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .popover(isPresented: $editing, arrowEdge: .trailing) {
                        EventEditor(event: event) { editing = false }
                    }
            }
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 8, height: 8)
                .help(event.calendar.title)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            if editable {
                Button("编辑…") { editing = true }
                Button("删除…", role: .destructive, action: onDelete)
            }
        }
        .confirmationDialog("这是一个重复日程", isPresented: Binding(get: { pendingTitle != nil },
                                                             set: { if !$0 { pendingTitle = nil } })) {
            Button("仅此次") { commit(span: .thisEvent) }
            Button("将来所有") { commit(span: .futureEvents) }
        } message: {
            Text("要修改此次日程，还是此次及将来所有日程？")
        }
    }

    private var statuses: [String] { EmojiMarkers.items(statusText, fallback: EmojiMarkers.defaultStatuses) }
    private var priorities: [String] { EmojiMarkers.items(priorityText, fallback: EmojiMarkers.defaultPriorities) }

    /// 无状态时取序列第一个，否则循环到下一个
    private func nextStatus(after status: String?) -> String? {
        guard let status, let index = statuses.firstIndex(of: status) else { return statuses.first }
        return statuses[(index + 1) % statuses.count]
    }

    private func setStatus(_ status: String?, in marked: MarkedTitle) {
        var marked = marked
        marked.status = status
        guard marked.title != title else { return }
        if event.hasRecurrenceRules {
            pendingTitle = marked.title
        } else {
            store.updateTitle(of: event, to: marked.title, span: .thisEvent)
        }
    }

    private func commit(span: EKSpan) {
        guard let pendingTitle else { return }
        store.updateTitle(of: event, to: pendingTitle, span: span)
        self.pendingTitle = nil
    }

    /// 全天，或起止时间；跨天时带日期
    private var timeText: String {
        guard let start = event.startDate, let end = event.endDate else { return "" }
        if event.isAllDay { return "全天" }
        let calendar = Calendar.current
        let style: (Date) -> String = { date in
            calendar.isDate(date, inSameDayAs: start) && calendar.isDate(start, inSameDayAs: end)
                ? date.formatted(date: .omitted, time: .shortened)
                : date.formatted(.dateTime.month().day().hour().minute())
        }
        return "\(style(start)) – \(style(end))"
    }
}
