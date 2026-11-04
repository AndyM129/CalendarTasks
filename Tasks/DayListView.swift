import EventKit
import SwiftUI

/// 右侧：当日、所选日历中的日程。全天在前，定时按开始时间。
struct DayListView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.undoManager) private var undoManager
    @State private var selection: EKEvent?
    @State private var pendingDelete: EKEvent?
    /// 正在编辑（浮层打开）的日程
    @State private var editingEvent: EKEvent?
    @AppStorage("allDayExpanded") private var allDayExpanded = true
    @AppStorage("timedExpanded") private var timedExpanded = true

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
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
        #if DEBUG
        // 验证用：启动参数 -debugSelectFirst YES 选中第一条日程；-debugEditFirst YES 再打开它的编辑浮层
        .task {
            guard UserDefaults.standard.bool(forKey: "debugSelectFirst") else { return }
            try? await Task.sleep(for: .seconds(3))
            selection = store.allDayEvents.first ?? store.timedEvents.first
            if UserDefaults.standard.bool(forKey: "debugEditFirst") { editingEvent = selection }
        }
        #endif
        // 大标题固定在列表上方：放在 List 的分区标题里时，点标题弹出的月历浮层显示不出来
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                DayHeader()
                    .padding(.horizontal, 20)
                Divider()
            }
            .background(.background)
        }
        // 换日期、新增、删除、改状态等都会触发重新加载，列表随之做过渡动画
        .animation(.ui, value: store.revision)
        .animation(.ui, value: store.isAddingEvent)
        .onDeleteCommand {
            if let selection, selection.calendar.allowsContentModifications { pendingDelete = selection }
        }
        // 右键菜单与双击编辑。用列表级的 primaryAction，单击选中不会被双击识别拖慢
        .contextMenu(forSelectionType: EKEvent.self) { events in
            if let event = events.first, event.calendar.allowsContentModifications {
                Button("编辑…") { editingEvent = event }
                Button("删除…", role: .destructive) { pendingDelete = event }
            }
        } primaryAction: { events in
            if let event = events.first, event.calendar.allowsContentModifications { editingEvent = event }
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
        EventRow(event: event, title: event.title ?? "", revision: store.revision,
                 isEditing: Binding(get: { editingEvent == event },
                                    set: { if !$0 { editingEvent = nil } }))
            .background(SystemSelectionHighlightRemover())
            // 系统的强调蓝选中底太抢眼，改为浅灰圆角底
            .listRowBackground(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(selection == event ? 0.08 : 0))
                    .padding(.horizontal, 6)
            )
    }

    private var deleteTitle: String {
        "删除日程「\(pendingDelete?.title ?? "")」？"
    }

    private func delete(_ event: EKEvent, span: EKSpan) {
        store.delete(event, span: span, undoManager: undoManager)
        selection = nil
    }
}

/// 列表末尾的输入行：回车新增，⌥↩ 换行，Esc 取消，失焦时有内容就新增
private struct NewEventRow: View {
    @Environment(CalendarStore.self) private var store
    @State private var title = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(EmojiMarkers.placeholder)
                .font(.title3)
                .opacity(0.3)
                .frame(width: 24, height: 24)
            // 长标题自适应换行，最多 4 行
            GrowingTextView(text: $title, placeholder: "新日程", maxLines: 4, focusOnAppear: true,
                            returnSubmits: submit,
                            onCancel: {
                                title = ""
                                store.isAddingEvent = false
                            },
                            onEndEditing: submit)
                .placeholderOverlay()
        }
        .padding(.vertical, 4)
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
                withAnimation(.ui) { isExpanded.toggle() }
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
    /// 只在跨过阈值时变化，拖动窗口时不会每帧重算标题
    @State private var compact = false
    @State private var hoveringTitle = false

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                // 点大标题弹出月历选日期；鼠标移上去时显示 ⌄ 提示可点
                Button {
                    store.isPickingDate.toggle()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // 等宽数字：换日期时数字宽度不变，后面不变的字不会被挤动
                        PerCharacterText(text: dayTitle)
                            .font((compact ? Font.title2 : .largeTitle).bold().monospacedDigit())
                        Image(systemName: "chevron.down")
                            .font((compact ? Font.callout : .title3).bold())
                            .opacity(hoveringTitle || store.isPickingDate ? 1 : 0)
                    }
                    .foregroundStyle(Color.accentColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in withAnimation(.ui) { hoveringTitle = hovering } }
                .help("选择日期（⌘J）")
                .popover(isPresented: $store.isPickingDate, arrowEdge: .bottom) {
                    DatePicker("日期", selection: dayBinding, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .padding()
                }
                Spacer(minLength: 8)
                Text(store.events.count, format: .number)
                    .font((compact ? Font.title2 : .largeTitle).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
            }
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.vertical, 8)
        // 窄窗口换小一号字体
        .onGeometryChange(for: Bool.self) { $0.size.width < 320 } action: { compact = $0 }
    }

    private var dayTitle: String {
        store.day.formatted(.dateTime.month().day().weekday(.wide))
    }

    /// 选择器返回的时间统一归到当天 0 点，选中后收起
    private var dayBinding: Binding<Date> {
        Binding(
            get: { store.day },
            set: { date in
                withAnimation(.ui) { store.day = Calendar.current.startOfDay(for: date) }
                store.isPickingDate = false
            }
        )
    }

    private var subtitle: String {
        let year = store.day.formatted(.dateTime.year())
        return store.isToday ? "\(year) · 今天" : year
    }
}

/// 逐字拆开的文字：换日期时只有变了的字做过渡（如「4日 星期三」→「5日 星期四」只动「4」「三」）
private struct PerCharacterText: View {
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .contentTransition(.numericText())
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

struct EventRow: View {
    @Environment(CalendarStore.self) private var store
    @AppStorage(EmojiMarkers.statusKey) private var statusText = EmojiMarkers.defaultStatuses
    @AppStorage(EmojiMarkers.priorityKey) private var priorityText = EmojiMarkers.defaultPriorities
    /// 重复日程待确认范围的新标题
    @State private var pendingTitle: String?
    @State private var choosingStatus = false

    let event: EKEvent
    let title: String
    /// 每次重新加载递增，确保日程其他字段改动后行能刷新
    let revision: Int
    /// 编辑浮层是否打开，由列表统一管理（双击或右键「编辑…」）
    let isEditing: Binding<Bool>

    var body: some View {
        let marked = MarkedTitle(title, statuses: statuses, priorities: priorities)
        let editable = event.calendar.allowsContentModifications
        HStack(spacing: 10) {
            Button {
                choosingStatus = true
            } label: {
                Text(marked.status ?? EmojiMarkers.placeholder)
                    .font(.title3)
                    .opacity(marked.status == nil ? 0.5 : 1)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(!editable)
            .help(editable ? "选择状态" : "该日历不可编辑")
            // 点击弹出气泡，列出设置里配置的状态，点选后写回
            .popover(isPresented: $choosingStatus, arrowEdge: .bottom) {
                StatusPicker(statuses: statuses, current: marked.status) { status in
                    choosingStatus = false
                    setStatus(status, in: marked)
                }
            }
            // 标题里的 #标签 挪到副标题行，只影响显示
            let (bodyText, tags) = TitleTags.split(marked.text)
            VStack(alignment: .leading, spacing: 2) {
                Text((marked.priority ?? "") + (bodyText.isEmpty ? (marked.text.isEmpty ? "新日程" : marked.text) : bodyText))
                HStack(spacing: 6) {
                    Text(timeText)
                    ForEach(bodyText.isEmpty ? [] : tags, id: \.self) { tag in
                        Text(tag)
                            .foregroundStyle(Color.accentColor.opacity(0.8))
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 8, height: 8)
                .help(event.calendar.title)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // 双击行（List 的 primaryAction）打开编辑浮层，挂在整行上
        .popover(isPresented: isEditing, arrowEdge: .trailing) {
            EventEditor(event: event) { isEditing.wrappedValue = false }
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

/// 状态选择气泡：一排可选的状态 emoji，当前状态带底色；有状态时末尾多一个「清除」
private struct StatusPicker: View {
    let statuses: [String]
    let current: String?
    let choose: (String?) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(statuses, id: \.self) { status in
                Button { choose(status) } label: {
                    Text(status)
                        .font(.title2)
                        .frame(width: 34, height: 34)
                        .background(status == current ? Color.primary.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if current != nil {
                Divider().frame(height: 24)
                Button("清除") { choose(nil) }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 4)
            }
        }
        .padding(8)
    }
}
