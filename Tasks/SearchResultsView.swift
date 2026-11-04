import EventKit
import SwiftUI

/// 搜索结果：勾选日历中当日前后各一年，按日期分组，点击跳到该日
struct SearchResultsView: View {
    @Environment(CalendarStore.self) private var store
    @State private var results: [EKEvent] = []

    var body: some View {
        let groups = Dictionary(grouping: results) { Calendar.current.startOfDay(for: $0.startDate) }
            .sorted { $0.key < $1.key }
        List {
            ForEach(groups, id: \.key) { day, events in
                Section {
                    ForEach(events, id: \.self) { event in
                        Button {
                            store.day = day
                            store.searchText = ""
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title ?? "")
                                Text(detail(of: event))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(day, format: .dateTime.year().month().day().weekday(.wide))
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: store.searchText)
            }
        }
        // 输入停顿 250ms 后再查，避免每个字都查一遍
        .task(id: store.searchText) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            results = store.search(store.searchText)
        }
    }

    private func detail(of event: EKEvent) -> String {
        let time = event.isAllDay ? "全天" : event.startDate.formatted(date: .omitted, time: .shortened)
        return [time, event.calendar.title, event.location].compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }
}
