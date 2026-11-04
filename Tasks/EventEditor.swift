import EventKit
import SwiftUI

/// (i) 浮层：完整编辑标题、时间、所属日历、地点、备注
struct EventEditor: View {
    @Environment(CalendarStore.self) private var store
    let event: EKEvent
    let dismiss: () -> Void

    @State private var title: String
    @State private var isAllDay: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var calendarID: String
    @State private var location: String
    @State private var notes: String
    @State private var askingSpan = false

    init(event: EKEvent, dismiss: @escaping () -> Void) {
        self.event = event
        self.dismiss = dismiss
        _title = State(initialValue: event.title ?? "")
        _isAllDay = State(initialValue: event.isAllDay)
        _start = State(initialValue: event.startDate)
        _end = State(initialValue: event.endDate)
        _calendarID = State(initialValue: event.calendar.calendarIdentifier)
        _location = State(initialValue: event.location ?? "")
        _notes = State(initialValue: event.notes ?? "")
    }

    var body: some View {
        Form {
            TextField("标题", text: $title)
            Toggle("全天", isOn: $isAllDay.animation(.ui))
                .onChange(of: isAllDay) { _, allDay in
                    // 由全天改为定时且开始在 0 点时，默认当日 9:00–10:00
                    let day = Calendar.current.startOfDay(for: start)
                    guard !allDay, start == day else { return }
                    start = Calendar.current.date(byAdding: .hour, value: 9, to: day) ?? start
                    end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? end
                }
            DatePicker("开始", selection: $start,
                       displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
            DatePicker("结束", selection: $end, in: start...,
                       displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
            Picker("日历", selection: $calendarID) {
                ForEach(store.calendarGroups, id: \.source) { group in
                    Section(group.source) {
                        ForEach(group.calendars.filter(\.allowsContentModifications),
                                id: \.calendarIdentifier) { calendar in
                            Text(calendar.title).tag(calendar.calendarIdentifier)
                        }
                    }
                }
            }
            TextField("地点", text: $location)
            TextField("备注", text: $notes, axis: .vertical)
                .lineLimit(3...8)
        }
        .formStyle(.grouped)
        .frame(width: 360)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: dismiss)
                    .keyboardShortcut(.cancelAction)
                Button("存储") {
                    if event.hasRecurrenceRules { askingSpan = true } else { commit(span: .thisEvent) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(end < start)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .confirmationDialog("这是一个重复日程", isPresented: $askingSpan) {
            Button("仅此次") { commit(span: .thisEvent) }
            Button("将来所有") { commit(span: .futureEvents) }
        } message: {
            Text("要修改此次日程，还是此次及将来所有日程？")
        }
    }

    private func commit(span: EKSpan) {
        event.title = title
        event.isAllDay = isAllDay
        event.startDate = start
        event.endDate = end
        if let calendar = store.calendars.first(where: { $0.calendarIdentifier == calendarID }) {
            event.calendar = calendar
        }
        event.location = location.isEmpty ? nil : location
        event.notes = notes.isEmpty ? nil : notes
        if store.save(event, span: span) { dismiss() }
    }
}
