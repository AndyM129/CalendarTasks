import EventKit
import SwiftUI

/// 右侧：当日、所选日历中的日程。全天在前，定时按开始时间。
struct DayListView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var store = store
        List {
            Section {
                EmptyView()
            } header: {
                DayHeader()
            }
            if !store.allDayEvents.isEmpty {
                Section("全天") {
                    ForEach(store.allDayEvents, id: \.self) { EventRow(event: $0, title: $0.title ?? "") }
                }
            }
            if !store.timedEvents.isEmpty {
                Section("日程") {
                    ForEach(store.timedEvents, id: \.self) { EventRow(event: $0, title: $0.title ?? "") }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if store.events.isEmpty {
                ContentUnavailableView(store.selectedCalendarIDs.isEmpty ? "未选择日历" : "无日程",
                                       systemImage: "calendar")
            }
        }
        .alert("无法保存日程", isPresented: Binding(get: { store.lastError != nil },
                                                set: { if !$0 { store.lastError = nil } })) {
            Button("好") {}
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

private struct DayHeader: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.day, format: .dateTime.month().day().weekday(.wide))
                    .font(.largeTitle.bold())
                    .foregroundStyle(Color.accentColor)
                Spacer()
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

    let event: EKEvent
    let title: String

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
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 8, height: 8)
                .help(event.calendar.title)
        }
        .padding(.vertical, 4)
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
