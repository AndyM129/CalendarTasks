import AppKit
import EventKit
import SwiftUI

/// 日程编辑浮层，参照系统日历的日程简介面板：标题（右侧选日历）→ 时间（摘要，点开展开全天/起止/重复/提醒）→ 备注 → URL。
/// 地点、受邀人、附件不在这里编辑（EventKit 没有附件接口）；已有的地点保持不变
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
    @State private var askingSpan = false

    private let originalRepeat: RepeatDraft
    private let originalAlarm: AlarmChoice

    init(event: EKEvent, dismiss: @escaping () -> Void) {
        self.event = event
        self.dismiss = dismiss
        _title = State(initialValue: event.title ?? "")
        _isAllDay = State(initialValue: event.isAllDay)
        _start = State(initialValue: event.startDate)
        _end = State(initialValue: event.endDate)
        _calendarID = State(initialValue: event.calendar.calendarIdentifier)
        _notes = State(initialValue: event.notes ?? "")
        _urlText = State(initialValue: event.url?.absoluteString ?? "")
        let draft = RepeatDraft(rule: event.recurrenceRules?.first)
        originalRepeat = draft
        _repeatDraft = State(initialValue: draft)
        let currentAlarm = AlarmChoice.current(of: event)
        originalAlarm = currentAlarm
        _alarm = State(initialValue: currentAlarm)
        #if DEBUG
        // 验证用：启动参数 -debugExpandTime YES 打开时直接展开时间卡片
        _timeExpanded = State(initialValue: UserDefaults.standard.bool(forKey: "debugExpandTime"))
        #endif
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
        .confirmationDialog("这是一个重复日程", isPresented: $askingSpan) {
            // 改了重复规则只能作用于此次及将来
            if repeatDraft == originalRepeat {
                Button("仅此次") { commit(span: .thisEvent) }
            }
            Button("将来所有") { commit(span: .futureEvents) }
        } message: {
            Text(repeatDraft == originalRepeat ? "要修改此次日程，还是此次及将来所有日程？" : "修改重复规则会应用到此次及将来所有日程。")
        }
    }

    private var footer: some View {
        HStack {
            Text("⌘↩ 保存")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("取消", role: .cancel, action: dismiss)
                .keyboardShortcut(.cancelAction)
            // 回车留给输入框换行，保存用 ⌘↩
            Button("保存") {
                if event.hasRecurrenceRules { askingSpan = true } else { commit(span: .thisEvent) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
            .disabled(end < start || (!urlText.isEmpty && parsedURL == nil))
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
        if let calendar = store.calendars.first(where: { $0.calendarIdentifier == calendarID }) {
            event.calendar = calendar
        }
        event.notes = notes.isEmpty ? nil : notes
        event.url = parsedURL
        // 只有改动过才覆盖，避免把编辑器表达不了的原规则 / 提醒冲掉
        if repeatDraft != originalRepeat {
            event.recurrenceRules = repeatDraft.makeRule().map { [$0] }
        }
        if alarm != originalAlarm, !alarm.isKeepExisting {
            var alarms = event.alarms ?? []
            if !alarms.isEmpty { alarms.removeFirst() }
            if let offset = alarm.offset { alarms.insert(EKAlarm(relativeOffset: offset), at: 0) }
            event.alarms = alarms
        }
        if store.save(event, span: span, undoing: before, actionName: "编辑日程") { dismiss() }
    }
}
