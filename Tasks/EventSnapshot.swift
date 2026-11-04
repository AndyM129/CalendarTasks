import EventKit

/// 删除前保存的日程内容，用于撤销时重建
struct EventSnapshot {
    let title: String?
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let timeZone: TimeZone?
    let calendarID: String
    let location: String?
    let notes: String?
    let url: URL?
    let alarms: [EKAlarm]
    /// 只在删除「将来所有」时保留，撤销时从这次开始重建系列
    let recurrenceRules: [EKRecurrenceRule]

    init(_ event: EKEvent, keepsRecurrence: Bool) {
        title = event.title
        startDate = event.startDate
        endDate = event.endDate
        isAllDay = event.isAllDay
        timeZone = event.timeZone
        calendarID = event.calendar.calendarIdentifier
        location = event.location
        notes = event.notes
        url = event.url
        alarms = (event.alarms ?? []).compactMap { $0.copy() as? EKAlarm }
        recurrenceRules = keepsRecurrence
            ? (event.recurrenceRules ?? []).compactMap { $0.copy() as? EKRecurrenceRule }
            : []
    }

    func makeEvent(in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.isAllDay = isAllDay
        event.startDate = startDate
        event.endDate = endDate
        event.timeZone = timeZone
        event.calendar = store.calendar(withIdentifier: calendarID) ?? store.defaultCalendarForNewEvents
        event.location = location
        event.notes = notes
        event.url = url
        event.alarms = alarms.compactMap { $0.copy() as? EKAlarm }
        if !recurrenceRules.isEmpty {
            event.recurrenceRules = recurrenceRules.compactMap { $0.copy() as? EKRecurrenceRule }
        }
        return event
    }
}
