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
    @FocusState private var listFocused: Bool
    // 折叠状态用 @State 驱动界面、再写回 UserDefaults：直接绑 @AppStorage 时更新不在 withAnimation 事务里，折叠没有动画
    @AppStorage("allDayExpanded") private var savedAllDayExpanded = true
    @AppStorage("timedExpanded") private var savedTimedExpanded = true
    @State private var allDayExpanded = UserDefaults.standard.object(forKey: "allDayExpanded") as? Bool ?? true
    @State private var timedExpanded = UserDefaults.standard.object(forKey: "timedExpanded") as? Bool ?? true
    // 拖动改日期（见 DayListDrag.swift）
    @State private var drag: RowDrag?
    @State private var rowFrames = RowFrames()
    @State private var listWidth: CGFloat = 0
    /// 指针停在两侧时的翻页计时
    @State private var zoneTask: Task<Void, Never>?
    /// 按 Esc 放弃后，忽略这次拖动剩下的事件，直到松手
    @State private var dragCancelled = false
    @State private var escMonitor: Any?
    /// 重复日程拖完，待确认范围
    @State private var pendingMove: PendingMove?

    private struct PendingMove {
        let event: EKEvent
        let days: Int
    }

    var body: some View {
        @Bindable var store = store
        // 用 ScrollView + LazyVStack 而不是 List：List 底层表格增删行是一步完成的，分组折叠、增删日程都没有过渡动画（实测）
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
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
                if store.isAddingEvent {
                    NewEventRow()
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }
                // 点列表末尾空白处新增
                Color.clear
                    .frame(height: 80)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.ui) { store.isAddingEvent = true } }
            }
            .padding(.vertical, 8)
            // 换日期时列表直接换成新内容，不做增删过渡（整列表替换的过渡效果不好）；大标题的逐字动画不受影响
            .transaction(value: store.day) { $0.animation = nil }
        }
        // 拖动手势挂在整个列表上而不是行上：拖到两侧翻页后原来那一行已不在列表里，挂在行上手势会被打断
        .coordinateSpace(name: Self.listSpace)
        .simultaneousGesture(dragGesture)
        .overlay {
            if let drag, !dragCancelled {
                dragOverlay(drag)
                    .transition(.opacity)
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.width, initial: true) { _, width in listWidth = width }
            }
        }
        // 可获得焦点，Delete 键和 ↑↓ 选择才能生效；不画系统焦点框
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onChange(of: allDayExpanded) { _, expanded in savedAllDayExpanded = expanded }
        .onChange(of: timedExpanded) { _, expanded in savedTimedExpanded = expanded }
        #if DEBUG
        // 验证用：启动参数 -debugSelectFirst YES 选中第一条日程；-debugEditFirst YES 再打开它的编辑浮层
        .task {
            guard UserDefaults.standard.bool(forKey: "debugSelectFirst") else { return }
            try? await Task.sleep(for: .seconds(3))
            selection = store.allDayEvents.first ?? store.timedEvents.first
            if UserDefaults.standard.bool(forKey: "debugEditFirst") { editingEvent = selection }
        }
        // 验证用：-debugDragOverlay YES，3 秒后模拟拖着第一条日程停在右侧，只显示引导，不松手、不改日历
        .task {
            guard UserDefaults.standard.bool(forKey: "debugDragOverlay") else { return }
            try? await Task.sleep(for: .seconds(3))
            guard let event = store.allDayEvents.first ?? store.timedEvents.first else { return }
            drag = RowDrag(event: event, originDay: store.day, location: CGPoint(x: listWidth - 40, y: 200))
            drag?.zone = 1
            restartTick(1)
        }
        // 验证用：-debugBench collapse，4 秒后收起「全天」、再展开，记录「日程」分组标题的位置变化
        .task {
            if UserDefaults.standard.string(forKey: "debugBench") == "daychange" {
                // 用 3 秒的慢动画换到后一天，外部在中途截屏：列表应已是新内容，只有标题在过渡
                try? await Task.sleep(for: .seconds(4))
                try? "start\n".write(to: FileManager.default.temporaryDirectory.appending(path: "collapse-start"),
                                     atomically: true, encoding: .utf8)
                withAnimation(.linear(duration: 3)) { store.shiftDay(by: 1) }
                return
            }
            guard UserDefaults.standard.string(forKey: "debugBench") == "collapse" else { return }
            try? await Task.sleep(for: .seconds(4))
            DebugBench.samples.removeAll()
            // 动画放慢到 3 秒并写标记文件，外部在动画中途截屏，看有没有中间态
            try? "start\n".write(to: FileManager.default.temporaryDirectory.appending(path: "collapse-start"),
                                  atomically: true, encoding: .utf8)
            withAnimation(.ui) { allDayExpanded = false }
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.ui) { allDayExpanded = true }
            try? await Task.sleep(for: .seconds(1))
            DebugBench.writeSamples()
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
        .confirmationDialog("这是一个重复日程", isPresented: Binding(get: { pendingMove != nil },
                                                             set: { if !$0 { pendingMove = nil } }),
                            presenting: pendingMove) { move in
            Button("仅此次") { store.shiftEvent(move.event, byDays: move.days, span: .thisEvent) }
            Button("将来所有") { store.shiftEvent(move.event, byDays: move.days, span: .futureEvents) }
        } message: { _ in
            Text("要移动此次日程，还是此次及将来所有日程？")
        }
        // 日程保存失败改用错误提示，这里只剩配置文件读写出错
        .alert("配置文件出错", isPresented: Binding(get: { store.lastError != nil },
                                                set: { if !$0 { store.lastError = nil } })) {
            Button("好") {}
        } message: {
            Text(store.lastError ?? "")
        }
    }

    /// 单击选中（立即生效），双击打开编辑浮层，右键菜单编辑 / 删除；选中时浅灰圆角底
    private func row(_ event: EKEvent) -> some View {
        let editable = event.calendar.allowsContentModifications
        return VStack(spacing: 0) {
            EventRow(event: event, title: event.title ?? "", revision: store.revision,
                     isEditing: Binding(get: { editingEvent == event },
                                        set: { if !$0 { editingEvent = nil } }))
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(selection == event ? 0.08 : 0)))
                // 拖动开始时按位置找是哪一行
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.frame(in: .named(Self.listSpace)), initial: true) { _, frame in
                                rowFrames.set(frame, for: event)
                            }
                            .onDisappear { rowFrames.remove(event) }
                    }
                }
                .opacity(drag?.event == event ? 0.4 : 1)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { if editable { editingEvent = event } }
                .simultaneousGesture(TapGesture().onEnded {
                    selection = event
                    listFocused = true
                })
                .contextMenu {
                    if editable {
                        Button("编辑…") { editingEvent = event }
                        Button("删除…", role: .destructive) { pendingDelete = event }
                    }
                }
            Divider().padding(.leading, 56)
        }
        .padding(.horizontal, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var visibleEvents: [EKEvent] {
        (allDayExpanded ? store.allDayEvents : []) + (timedExpanded ? store.timedEvents : [])
    }

    // MARK: - 拖动改日期

    // 规则：拖到两侧竖条，0.5 秒内松手移 1 天、列表不翻页；停够 0.5 秒列表翻 1 天，之后每多停 1 秒再翻 1 天；
    // 翻页后在两侧或中间松手，都按已翻的天数移动，列表停在已翻到的那天；拖动中按 Esc 放弃，松手后用 ⌘Z 撤销

    private static let listSpace = "dayList"

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(Self.listSpace))
            .onChanged(dragChanged)
            .onEnded { _ in dragEnded() }
    }

    private var zoneWidth: CGFloat { max(listWidth * 0.15, 44) }

    private func zone(at x: CGFloat) -> Int {
        if x < zoneWidth + 8 { return -1 }
        if x > listWidth - zoneWidth - 8 { return 1 }
        return 0
    }

    private func dragChanged(_ value: DragGesture.Value) {
        guard !dragCancelled else { return }
        if drag == nil {
            guard editingEvent == nil,
                  let event = rowFrames.event(at: value.startLocation, among: visibleEvents),
                  event.calendar.allowsContentModifications else { return }
            selection = event
            withAnimation(.ui) { drag = RowDrag(event: event, originDay: store.day, location: value.location) }
            startEscMonitor()
        }
        drag?.location = value.location
        let zone = zone(at: value.location.x)
        if zone != drag?.zone { enterZone(zone) }
    }

    /// 进入某侧开始计时：先等 0.5 秒翻第一页，之后每 1 秒翻一页
    private func enterZone(_ zone: Int) {
        zoneTask?.cancel()
        drag?.zone = zone
        guard zone != 0 else { return }
        restartTick(0.5)
        zoneTask = Task {
            var wait = 0.5
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, drag != nil else { return }
                drag?.offset += zone
                store.shiftDay(by: zone)
                DragHaptics.tick()
                wait = 1
                restartTick(wait)
            }
        }
    }

    private func restartTick(_ length: Double) {
        drag?.tickStart = .now
        drag?.tickLength = length
    }

    private func dragEnded() {
        zoneTask?.cancel()
        stopEscMonitor()
        if dragCancelled {
            dragCancelled = false
            return
        }
        guard let drag else { return }
        withAnimation(.ui) { self.drag = nil }
        let days = drag.releaseDays
        guard days != 0 else { return }
        if drag.event.hasRecurrenceRules {
            pendingMove = PendingMove(event: drag.event, days: days)
        } else {
            store.shiftEvent(drag.event, byDays: days, span: .thisEvent)
        }
    }

    /// Esc 放弃：列表回到开始拖动时那天，不移动
    private func startEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, let drag else { return event }
            zoneTask?.cancel()
            dragCancelled = true
            store.day = drag.originDay
            withAnimation(.ui) { self.drag = nil }
            return nil
        }
    }

    private func stopEscMonitor() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
    }

    private func dragOverlay(_ drag: RowDrag) -> some View {
        let base = Calendar.current.date(byAdding: .day, value: drag.offset, to: drag.originDay) ?? drag.originDay
        let target = { (step: Int) in Calendar.current.date(byAdding: .day, value: step, to: base) ?? base }
        return ZStack {
            HStack {
                DragZone(direction: -1, target: target(-1), isActive: drag.zone == -1, drag: drag)
                    .frame(width: zoneWidth)
                Spacer()
                DragZone(direction: 1, target: target(1), isActive: drag.zone == 1, drag: drag)
                    .frame(width: zoneWidth)
            }
            .padding(8)
            DragResultCapsule(drag: drag)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 16)
            DragGhost(title: drag.event.title ?? "")
                .position(x: drag.location.x, y: drag.location.y - 20)
        }
        .allowsHitTesting(false)
    }

    /// ↑↓ 在可见日程间移动选中
    private func moveSelection(by step: Int) -> KeyPress.Result {
        let visible = visibleEvents
        guard !visible.isEmpty else { return .ignored }
        let index = selection.flatMap { visible.firstIndex(of: $0) }.map { $0 + step } ?? (step > 0 ? 0 : visible.count - 1)
        selection = visible[min(max(index, 0), visible.count - 1)]
        return .handled
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
        VStack(alignment: .leading, spacing: 0) {
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
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            #if DEBUG
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                DebugBench.record(title, $0)
            }
            #endif
            Divider().padding(.horizontal, 20)
                #if DEBUG
                .background(AnimationProbe(value: isExpanded ? 1 : 0, tag: title))
                #endif
            // 收起时内容整体移除，下面的分组随高度变化滑上来；内容单独裁切，上移时不会盖到分组标题
            VStack(spacing: 0) {
                if isExpanded {
                    VStack(spacing: 0) { content }
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .clipped()
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
                // 显示的条数：未隐藏的日程
                Text(store.allDayEvents.count + store.timedEvents.count, format: .number)
                    .font((compact ? Font.title2 : .largeTitle).monospacedDigit())
                    .foregroundStyle(Color.accentColor)
                    .contentTransition(.numericText())
            }
            // 仿提醒事项的「54 项完成 · 清除」：已隐藏 N 项 · 显示 / 隐藏
            HStack(spacing: 6) {
                Text(subtitle)
                let hidden = store.hiddenEventCount
                if hidden > 0 {
                    Text("·")
                    Text("已隐藏 \(hidden) 项")
                    Button(store.showHiddenEvents ? "隐藏" : "显示") {
                        withAnimation(.ui) { store.showHiddenEvents.toggle() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .help("显示或隐藏状态为「已结束」的日程（在设置里配置哪些状态算已结束）")
                }
            }
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
    private struct PendingStatus {
        let title: String
        let change: CalendarStore.StatusTimeChange
    }
    @Environment(CalendarStore.self) private var store
    @AppStorage(EmojiMarkers.statusKey) private var statusText = EmojiMarkers.defaultStatuses
    @AppStorage(EmojiMarkers.priorityKey) private var priorityText = EmojiMarkers.defaultPriorities
    /// 重复日程待确认范围的新状态
    @State private var pendingStatus: PendingStatus?
    /// 非今天的全天日程改成结果状态，待用户选「改为今天」还是「保留原日期」的新标题
    @State private var completingTitle: String?
    /// 重复日程待确认范围的新日历
    @State private var pendingCalendarID: String?
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
            // 单击色点换所属日历，和点开头 emoji 改状态一样不触发行选中
            if editable {
                CalendarColorMenu(calendarID: calendarBinding, dotSize: 8)
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .help("\(event.calendar.title)，点击更换日历")
            } else {
                Circle()
                    .fill(Color(cgColor: event.calendar.cgColor))
                    .frame(width: 8, height: 8)
                    .help(event.calendar.title)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        // 双击行（List 的 primaryAction）打开编辑浮层，挂在整行上；按住浮层往外拖可变成独立窗口
        .detachablePopover(isPresented: isEditing, store: store) { close in
            EventEditor(event: event, dismiss: close)
        }
        .confirmationDialog("这是一个重复日程", isPresented: Binding(get: { pendingStatus != nil },
                                                             set: { if !$0 { pendingStatus = nil } })) {
            Button("仅此次") { commit(span: .thisEvent) }
            Button("将来所有") { commit(span: .futureEvents) }
        } message: {
            Text("要修改此次日程，还是此次及将来所有日程？")
        }
        .alert("标为完成", isPresented: Binding(get: { completingTitle != nil },
                                            set: { if !$0 { completingTitle = nil } })) {
            Button("移到今天（\(Self.dayText(.now))）") { finishCompleting(.completeNow) }
            Button("留在当天（\(Self.dayText(store.day))）") { finishCompleting(.completeOn(store.day)) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("移到今天：完成时间记为现在\n留在当天：完成时间记为当天 00:00")
        }
        .confirmationDialog("这是一个重复日程", isPresented: Binding(get: { pendingCalendarID != nil },
                                                             set: { if !$0 { pendingCalendarID = nil } })) {
            Button("仅此次") { moveCalendar(span: .thisEvent) }
            Button("将来所有") { moveCalendar(span: .futureEvents) }
        } message: {
            Text("要更换此次日程的日历，还是此次及将来所有日程？")
        }
    }

    /// 选了新日历：重复日程先确认范围
    private var calendarBinding: Binding<String> {
        Binding(
            get: { event.calendar.calendarIdentifier },
            set: { id in
                guard id != event.calendar.calendarIdentifier else { return }
                if event.hasRecurrenceRules {
                    pendingCalendarID = id
                } else {
                    store.moveEvent(event, toCalendar: id, span: .thisEvent)
                }
            }
        )
    }

    private func moveCalendar(span: EKSpan) {
        guard let pendingCalendarID else { return }
        store.moveEvent(event, toCalendar: pendingCalendarID, span: span)
        self.pendingCalendarID = nil
    }

    private var statuses: [String] { EmojiMarkers.items(statusText, fallback: EmojiMarkers.defaultStatuses) }
    private var priorities: [String] { EmojiMarkers.items(priorityText, fallback: EmojiMarkers.defaultPriorities) }

    private func setStatus(_ status: String?, in marked: MarkedTitle) {
        var marked = marked
        marked.status = status
        guard marked.title != title else { return }
        if let change = store.statusTimeChange(of: event, to: status) {
            applyStatus(marked.title, change)
        } else {
            completingTitle = marked.title
        }
    }

    /// 重复日程先确认范围，再写回
    private func applyStatus(_ title: String, _ change: CalendarStore.StatusTimeChange) {
        if event.hasRecurrenceRules {
            pendingStatus = PendingStatus(title: title, change: change)
        } else {
            store.updateTitle(of: event, to: title, span: .thisEvent, timeChange: change)
        }
    }

    private func commit(span: EKSpan) {
        guard let pendingStatus else { return }
        store.updateTitle(of: event, to: pendingStatus.title, span: span, timeChange: pendingStatus.change)
        self.pendingStatus = nil
    }

    private func finishCompleting(_ change: CalendarStore.StatusTimeChange) {
        guard let title = completingTitle else { return }
        completingTitle = nil
        // 等这个弹窗收起后再弹重复日程的范围确认，同时弹会被吞掉
        Task { applyStatus(title, change) }
    }

    /// 如「11月25日 星期三」，与列表大标题同一格式
    private static func dayText(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().weekday(.wide))
    }

    /// 简短格式：同一天「08:00 ~ 09:00」，跨天「11/04 08:00 ~ 11/05 08:00」；全天跨天「全天 11/04 ~ 11/06」
    private var timeText: String {
        guard let start = event.startDate, let end = event.endDate else { return "" }
        let calendar = Calendar.current
        let day = { (date: Date) in String(format: "%02d/%02d", calendar.component(.month, from: date),
                                           calendar.component(.day, from: date)) }
        let time = { (date: Date) in String(format: "%02d:%02d", calendar.component(.hour, from: date),
                                            calendar.component(.minute, from: date)) }
        if event.isAllDay {
            // 全天日程的结束可能是最后一天 23:59:59 或次日 0 点，往前退一秒都落在最后一天
            let lastDay = end.addingTimeInterval(-1)
            return calendar.isDate(start, inSameDayAs: lastDay) ? "全天" : "全天 \(day(start)) ~ \(day(lastDay))"
        }
        return calendar.isDate(start, inSameDayAs: end)
            ? "\(time(start)) ~ \(time(end))"
            : "\(day(start)) \(time(start)) ~ \(day(end)) \(time(end))"
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
