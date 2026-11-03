import EventKit
import SwiftUI

/// 右侧：当日、所选日历中的日程。全天在前，定时按开始时间。
struct DayListView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        List {
            Section {
                EmptyView()
            } header: {
                DayHeader()
            }
            if !store.allDayEvents.isEmpty {
                Section("全天") {
                    ForEach(store.allDayEvents, id: \.self) { EventRow(event: $0) }
                }
            }
            if !store.timedEvents.isEmpty {
                Section("日程") {
                    ForEach(store.timedEvents, id: \.self) { EventRow(event: $0) }
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
    let event: EKEvent

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .strokeBorder(Color(cgColor: event.calendar.cgColor), lineWidth: 1.5)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title?.isEmpty == false ? event.title : "新日程")
                Text(timeText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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
