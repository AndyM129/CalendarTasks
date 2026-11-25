import AppKit
import EventKit
import SwiftUI

/// 日程编辑浮层，参照系统日历的日程简介面板：标题（右侧选日历）→ 时间（摘要，点开展开全天/起止/重复/提醒）→ 备注 → URL。
/// 地点、受邀人、附件不在这里编辑（EventKit 没有附件接口）；已有的地点保持不变。
/// 不设保存 / 取消按钮：面板关闭或拖成的窗口失去焦点时自动保存，改错了用 ⌘Z 撤销
struct EventEditor: View {
    @Environment(CalendarStore.self) private var store
    let event: EKEvent
    let dismiss: () -> Void

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var calendarID: String
    @State private var notes: String
    @State private var urlText: String
    @State private var repeatDraft: RepeatDraft
    @State private var alarm: AlarmChoice
    @State private var timeExpanded = false
    /// 上次保存（或打开时）的内容，和它相同就不保存
    @State private var baseline: Fields
    @State private var session = EditorSession()

    private struct Fields: Equatable {
        var title, notes, urlText, calendarID: String
        var isAllDay: Bool
        var start, end: Date
        var repeatDraft: RepeatDraft
        var alarm: AlarmChoice
    }

    init(event: EKEvent, dismiss: @escaping () -> Void) {
        self.event = event
        self.dismiss = dismiss
        let fields = Fields(title: event.title ?? "", notes: event.notes ?? "",
                            urlText: event.url?.absoluteString ?? "", calendarID: event.calendar.calendarIdentifier,
                            isAllDay: event.isAllDay, start: event.startDate, end: event.endDate,
                            repeatDraft: RepeatDraft(rule: event.recurrenceRules?.first),
                            alarm: AlarmChoice.current(of: event))
        _baseline = State(initialValue: fields)
        _title = State(initialValue: fields.title)
        _isAllDay = State(initialValue: fields.isAllDay)
        _start = State(initialValue: fields.start)
        _end = State(initialValue: fields.end)
        _calendarID = State(initialValue: fields.calendarID)
        _notes = State(initialValue: fields.notes)
        _urlText = State(initialValue: fields.urlText)
        _repeatDraft = State(initialValue: fields.repeatDraft)
        _alarm = State(initialValue: fields.alarm)
        #if DEBUG
        // 验证用：启动参数 -debugExpandTime YES 打开时直接展开时间卡片
        _timeExpanded = State(initialValue: UserDefaults.standard.bool(forKey: "debugExpandTime"))
        #endif
    }

    private var current: Fields {
        Fields(title: title, notes: notes, urlText: urlText, calendarID: calendarID, isAllDay: isAllDay,
               start: start, end: end, repeatDraft: repeatDraft, alarm: alarm)
    }

    var body: some View {
        VStack(spacing: 10) {
            EditorCard {
                HStack(alignment: .top, spacing: 8) {
                    GrowingTextView(text: $title, placeholder: "标题", maxLines: 5, focusOnAppear: true)
                        .placeholderOverlay()
                    CalendarColorMenu(calendarID: $calendarID)
                }
            }
            EditorCard {
                if timeExpanded {
                    timeDetails
                } else {
                    Button {
                        withAnimation(.ui) { timeExpanded = true }
                    } label: {
                        timeSummary.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("编辑时间、重复与提醒")
                }
            }
            EditorCard {
                GrowingTextView(text: $notes, placeholder: "添加备注", maxLines: 8)
                    .placeholderOverlay()
            }
            EditorCard {
                HStack(spacing: 8) {
                    TextField("添加 URL", text: $urlText)
                        .textFieldStyle(.plain)
                    if let url = parsedURL, !urlText.isEmpty {
                        Button("打开") { NSWorkspace.shared.open(url) }
                            .buttonStyle(.borderless)
                    }
                }
                if !urlText.isEmpty && parsedURL == nil {
                    Text("URL 格式不正确")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            footer
        }
        .padding(12)
        .frame(width: 340)
        .onChange(of: isAllDay) { _, allDay in
            // 由全天改为定时且开始在 0 点时，默认当日 9:00–10:00
            let day = Calendar.current.startOfDay(for: start)
            if !allDay, start == day {
                start = Calendar.current.date(byAdding: .hour, value: 9, to: day) ?? start
                end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? end
            }
            // 全天与定时的提醒选项不同，切换后原选项不再适用时改为「无」
            if !alarm.isKeepExisting, !AlarmChoice.choices(allDay: allDay).contains(alarm) { alarm = .none }
        }
        .background(WindowReader(session: session))
        // 关闭面板（点外面、Esc、点「完成」、关掉拖出的窗口）时保存
        .onDisappear(perform: autosave)
        // 拖成独立窗口后，焦点离开时也保存，窗口保留：本 App 的别的窗口成为主窗口，或切到别的 App。
        // 不只靠面板窗口自己的 didResignKey：实测拖出的窗口在切到别的 App 时收不到它
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let window = session.view?.window, note.object as? NSWindow !== window { autosave() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            if session.view?.window != nil { autosave() }
        }
    }

    private var footer: some View {
        HStack {
            Text("关闭时自动保存 · ⌘Z 撤销")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            // 回车留给输入框换行，关闭用 ⌘↩
            Button("完成", action: dismiss)
                .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.top, 2)
    }

    /// 无协议时按 https 补全
    private var parsedURL: URL? {
        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let url = URL(string: text.contains("://") ? text : "https://" + text)
        return url?.host() == nil && url?.scheme != "file" ? nil : url
    }
    // MARK: - 时间

    /// 收起时的一行摘要，下面再列重复与提醒
    private var timeSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(dateRangeText)
            let extras = [repeatDraft.enabled ? repeatDraft.summary(start: start) : nil,
                          alarm == .none ? nil : "提醒：\(alarm.title)"].compactMap { $0 }
            if !extras.isEmpty {
                Text(extras.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateRangeText: String {
        let calendar = Calendar.current
        let day = start.formatted(.dateTime.year().month().day())
        if isAllDay {
            // 全天日程的结束日期就是最后一天
            return calendar.isDate(start, inSameDayAs: end)
                ? day : "\(day) – \(end.formatted(.dateTime.month().day()))"
        }
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        return calendar.isDate(start, inSameDayAs: end)
            ? "\(day)  \(time(start)) – \(time(end))"
            : "\(day) \(time(start)) – \(end.formatted(.dateTime.month().day())) \(time(end))"
    }

    private var timeDetails: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                label("全天")
                Toggle("", isOn: $isAllDay.animation(.ui)).toggleStyle(.checkbox).labelsHidden()
            }
            GridRow {
                label("开始")
                DatePicker("", selection: $start, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field)
            }
            GridRow {
                label("结束")
                DatePicker("", selection: $end, in: start..., displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field)
            }
            GridRow {
                label("重复")
                Picker("", selection: repeatPreset) {
                    ForEach(RepeatDraft.Preset.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
            if repeatDraft.preset(start: start) == .custom {
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    CustomRepeatEditor(draft: $repeatDraft)
                }
            }
            if repeatDraft.enabled {
                GridRow {
                    label("结束重复")
                    RepeatEndEditor(end: $repeatDraft.end, start: start)
                }
            }
            GridRow {
                label("提醒")
                Picker("", selection: $alarm) {
                    if alarm.isKeepExisting { Text(alarm.title).tag(alarm) }
                    ForEach(AlarmChoice.choices(allDay: isAllDay)) { Text($0.title).tag($0) }
                }
                .labelsHidden().fixedSize()
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text + "：")
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    /// 选「自定义…」时保留当前设置继续编辑，选预设时直接替换
    private var repeatPreset: Binding<RepeatDraft.Preset> {
        Binding(
            get: { repeatDraft.preset(start: start) },
            set: { preset in withAnimation(.ui) { repeatDraft.apply(preset, start: start) } }
        )
    }

    // MARK: - 存储

    /// 有改动才保存。内容不合法时不保存并提示；重复日程每次都问范围（这一次拆出来后不再是重复日程，之后不再问）
    private func autosave() {
        guard !session.isSaving, current != baseline else { return }
        if end < start || (!urlText.isEmpty && parsedURL == nil) {
            store.toasts.show(end < start ? "未保存：结束时间早于开始时间" : "未保存：URL 格式不正确", kind: .error)
            return
        }
        session.isSaving = true
        defer { session.isSaving = false }
        guard let span = event.hasRecurrenceRules ? askSpan() : .thisEvent else { return }
        commit(span: span)
    }

    /// 面板可能已经关掉，确认用独立的系统弹窗；选「不保存」返回 nil
    private func askSpan() -> EKSpan? {
        let alert = NSAlert()
        alert.messageText = "这是一个重复日程"
        // 改了重复规则只能作用于此次及将来
        let rulesChanged = repeatDraft != baseline.repeatDraft
        alert.informativeText = rulesChanged ? "修改重复规则会应用到此次及将来所有日程。" : "要修改此次日程，还是此次及将来所有日程？"
        if !rulesChanged { alert.addButton(withTitle: "仅此次") }
        alert.addButton(withTitle: "将来所有")
        alert.addButton(withTitle: "不保存")
        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        switch (rulesChanged, index) {
        case (false, 0): return .thisEvent
        case (false, 1), (true, 0): return .futureEvents
        default: return nil
        }
    }

    private func commit(span: EKSpan) {
        let before = EventSnapshot(event, keepsRecurrence: true)
        // 去掉首尾空白（含换行）
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.isAllDay = isAllDay
        // 全天改非全天时原 timeZone 为 nil（浮动时间），补上本机时区，否则起止会偏一个时区
        if !isAllDay, event.timeZone == nil {
            event.timeZone = .current
        }
        event.startDate = start
        event.endDate = end
        // 日历变了才写：拆出来的那一次哪怕写回同一个日历，EventKit 也会报「无法更改重复字段」
        if calendarID != event.calendar.calendarIdentifier,
           let calendar = store.calendars.first(where: { $0.calendarIdentifier == calendarID }) {
            event.calendar = calendar
        }
        event.notes = notes.isEmpty ? nil : notes
        event.url = parsedURL
        // 只有改动过才覆盖，避免把编辑器表达不了的原规则 / 提醒冲掉
        if repeatDraft != baseline.repeatDraft {
            event.recurrenceRules = repeatDraft.makeRule().map { [$0] }
        }
        if alarm != baseline.alarm, !alarm.isKeepExisting {
            var alarms = event.alarms ?? []
            if !alarms.isEmpty { alarms.removeFirst() }
            if let offset = alarm.offset { alarms.insert(EKAlarm(relativeOffset: offset), at: 0) }
            event.alarms = alarms
        }
        if store.save(event, span: span, undoing: before, actionName: "编辑日程", message: "已保存修改") {
            baseline = current
        }
    }
}

/// 编辑面板的非界面状态。放在引用类型里：范围确认弹窗期间会再收到失焦通知，要立即看到 isSaving
@MainActor
private final class EditorSession {
    /// 面板里的一个视图；拖成独立窗口后它会换到新窗口里，所以每次都从它取当前窗口
    weak var view: NSView?
    var isSaving = false
}

/// 把面板里的一个 NSView 交给 session，用来判断失焦的是不是面板自己的窗口
private struct WindowReader: NSViewRepresentable {
    let session: EditorSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        session.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
